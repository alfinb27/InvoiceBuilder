import Foundation
import GRDB
import InvoiceCore
import Testing
@testable import InvoiceData

/// An in-memory Drive sync folder shared by several test "devices".
final class FakeSyncDrive: DriveSyncDestination, @unchecked Sendable {
    struct File {
        var name: String
        var properties: [String: String]
        var data: Data
    }

    private let lock = NSLock()
    private var files: [String: File] = [:]
    private var next = 0
    let folderID = "sync-folder"

    func withFiles<T>(_ body: (inout [String: File]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&files)
    }

    func connect() async throws -> String { "owner@example.com" }
    func disconnect() async {}
    func folder(knownID: String?) async throws -> String { "backup-folder" }
    func list(folderID: String) async throws -> [CloudBackupEntry] { [] }
    func syncFolder(knownID: String?) async throws -> String { folderID }

    func syncEntries(folderID: String) async throws -> [DriveSyncEntry] {
        withFiles { files in files.map { DriveSyncEntry(id: $0.key, properties: $0.value.properties) } }
    }

    func upload(_ data: Data, name: String, properties: [String: String], target: CloudBackupTarget,
                folderID: String) async throws -> String {
        withFiles { files in
            let id: String
            switch target {
            case .create:
                next += 1
                id = "file-\(next)"
            case .update(let existing): id = existing
            }
            files[id] = File(name: name, properties: properties, data: data)
            return id
        }
    }

    func download(id: String) async throws -> Data {
        guard let data = withFiles({ $0[id]?.data }) else { throw CloudBackupError.other }
        return data
    }

    func delete(id: String) async throws { withFiles { _ = $0.removeValue(forKey: id) } }
}

extension TestStore {
    func syncEngine(_ drive: FakeSyncDrive, deviceID: String) throws -> DriveSyncEngine {
        DriveSyncEngine(destination: drive, store: try backupService(), time: time, deviceID: deviceID)
    }

    /// Live records as an export has them, without the device-specific parts.
    func liveRecords() async throws -> BackupData {
        try await backupService().allRecords()
    }
}

@Suite("Drive sync")
struct DriveSyncTests {
    @Test func aSecondDeviceReceivesEverything() async throws {
        let drive = FakeSyncDrive()
        let a = try TestStore(), b = try TestStore()
        _ = try await a.populate()
        try await a.syncEngine(drive, deviceID: "dev-a").connect()
        try await b.syncEngine(drive, deviceID: "dev-b").connect()

        let (fromA, onB) = (try await a.liveRecords(), try await b.liveRecords())
        #expect(onB.clients == fromA.clients)
        #expect(onB.documents == fromA.documents)
        #expect(onB.payments == fromA.payments)
        #expect(onB.assets == fromA.assets)
        #expect(onB.numberingSeries == fromA.numberingSeries)
        #expect(try await b.liveTaxLines() == (try await a.liveTaxLines()))

        // A's records came back from B as one change file; merging them again changes nothing on A.
        #expect(try await a.syncEngine(drive, deviceID: "dev-a").syncNow() == 0)
        #expect(try await a.backupService().driveSyncState().seen == ["dev-b": 1])
    }

    @Test func anEditTravelsBothWays() async throws {
        let drive = FakeSyncDrive()
        let a = try TestStore(), b = try TestStore()
        _ = try await a.populate()
        let engineA = try a.syncEngine(drive, deviceID: "dev-a"), engineB = try b.syncEngine(drive, deviceID: "dev-b")
        try await engineA.connect()
        try await engineB.connect()

        let client = try #require(try await b.liveRecords().clients.first { $0.deletedAt == nil })
        // B's clock is behind A's here; move it past A's edits, as a later real edit would be.
        try await b.database.writer.write { db in
            try db.execute(sql: "UPDATE client SET name = ?, updated_at = 1000000 WHERE id = ?",
                           arguments: ["Renamed on B", client.id])
        }
        try await engineB.syncNow()
        #expect(try await engineA.syncNow() == 1)
        #expect(try await a.liveRecords().clients.first { $0.id == client.id }?.name == "Renamed on B")
    }

    @Test func anIssueBeatsALaterDraftEditOnBothDevices() async throws {
        let drive = FakeSyncDrive()
        let a = try TestStore(), b = try TestStore()
        let (business, device) = try await a.setUpInvoicing()
        try await a.saveDraft(business, id: "d1", lines: [TestStore.line("l1", "Website", price: 100_000)])
        let engineA = try a.syncEngine(drive, deviceID: "dev-a"), engineB = try b.syncEngine(drive, deviceID: "dev-b")
        try await engineA.connect()
        try await engineB.connect()

        _ = try await a.documentService.issue(documentID: "d1", deviceID: device.id)
        try await b.database.writer.write { db in
            try db.execute(sql: "UPDATE document SET notes = 'edited on B', updated_at = 9000000 WHERE id = 'd1'")
        }
        try await engineB.syncNow()
        try await engineA.syncNow()
        try await engineB.syncNow()

        for store in [a, b] {
            let document = try #require(try await store.liveRecords().documents.first { $0.id == "d1" })
            #expect(document.lifecycle == .issued)
            #expect(document.number != nil)
        }
    }

    @Test func aNewDeviceCatchesUpFromASnapshot() async throws {
        let drive = FakeSyncDrive()
        let a = try TestStore()
        _ = try await a.populate()
        let engineA = try a.syncEngine(drive, deviceID: "dev-a")
        try await engineA.connect()
        let client = try #require(try await a.liveRecords().clients.first { $0.deletedAt == nil })
        for index in 1...DriveSync.snapshotAfter {
            try await a.database.writer.write { db in
                try db.execute(sql: "UPDATE client SET name = ?, updated_at = ? WHERE id = ?",
                               arguments: ["Name \(index)", 2_000_000 + index, client.id])
            }
            try await engineA.syncNow()
        }
        let state = try await a.backupService().driveSyncState()
        #expect(state.snapshotCovers == DriveSync.snapshotAfter + 1)

        // Compaction would delete the old change files after 30 days; do it now.
        drive.withFiles { files in
            files = files.filter { $0.value.properties[DriveSyncEntry.Key.kind] == "snapshot" }
        }
        let c = try TestStore()
        try await c.syncEngine(drive, deviceID: "dev-c").connect()
        #expect(try await c.liveRecords().clients.first { $0.id == client.id }?.name == "Name \(DriveSync.snapshotAfter)")
        #expect(try await c.backupService().driveSyncState().seen["dev-a"] == DriveSync.snapshotAfter + 1)
    }

    @Test func syncStateRoundTripsThroughAppState() async throws {
        let store = try TestStore()
        let service = try store.backupService()
        let state = DriveSyncState(accountEmail: "o@example.com", folderID: "f", pushedAt: 42, nextSeq: 7,
                                   seen: ["dev-b": 3], snapshotID: "s", snapshotCovers: 5, lastSyncAt: 9,
                                   lastError: .quotaExceeded)
        try await service.saveDriveSyncState(state)
        #expect(try await service.driveSyncState() == state)
        try await service.saveDriveSyncState(DriveSyncState())
        #expect(try await service.driveSyncState() == DriveSyncState())
    }
}
