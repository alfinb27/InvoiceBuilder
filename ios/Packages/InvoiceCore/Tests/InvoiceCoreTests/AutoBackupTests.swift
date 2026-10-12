import Foundation
import Testing
@testable import InvoiceCore

/// `AutoBackupRunner` against an in-memory cloud (`spec/backup.md` §7). The pure rules run as fixtures.
@Suite("Automatic cloud backup")
struct AutoBackupTests {
    static let day: Int64 = 86_400_000
    static let start: Int64 = 1_791_600_000_000

    final class Clock: @unchecked Sendable {
        var now = AutoBackupTests.start
        var today = LocalDate(year: 2026, month: 10, day: 10)!
        var time: TimeSource { TimeSource(now: { self.now }, today: { self.today }) }
    }

    func makeRunner(clock: Clock, cloud: FakeCloud = FakeCloud(), state: FakeState = FakeState(),
                    deviceID: String = "dev-me") -> (AutoBackupRunner, FakeCloud, FakeState, FakeBackups) {
        let backups = FakeBackups(time: clock.time)
        let runner = AutoBackupRunner(destination: cloud, backups: backups, state: state, time: clock.time,
                                      device: .init(id: deviceID, name: "iPhone",
                                                    app: .init(platform: "ios", version: "1.0")))
        return (runner, cloud, state, backups)
    }

    @Test func connectingSignsInAndBacksUpAtOnce() async throws {
        let clock = Clock()
        let (runner, cloud, state, backups) = makeRunner(clock: clock)
        try await runner.connect()
        let saved = try await state.cloudBackupState()
        #expect(saved.accountEmail == "owner@example.com")
        #expect(saved.folderID != nil)
        #expect(saved.lastBackupAt == clock.now)
        #expect(saved.lastError == nil)
        let files = await cloud.files
        #expect(files.count == 1)
        let file = try #require(files.values.first)
        #expect(file.name == "InvoiceBackup-2026-10-10.invoicebackup")
        #expect(file.properties["ibDeviceId"] == "dev-me")
        #expect(file.properties["ibPlatform"] == "ios")
        #expect(file.properties["ibBusinesses"] == "Bharat Web Studio")
        #expect(await backups.recorded == [clock.now]) // §7.5: the 30-day nudge clears too
    }

    @Test func aNewPhoneConnectingToRestoreWritesNoEmptyBackup() async throws {
        let clock = Clock()
        let state = FakeState()
        await state.setLatestChange(nil) // nothing in the database yet
        let (runner, cloud, _, _) = makeRunner(clock: clock, state: state)
        try await runner.connect()
        #expect(try await state.cloudBackupState().isConnected)
        #expect(await cloud.files.isEmpty)
    }

    @Test func aSecondBackupTheSameDayReplacesTodaysFile() async throws {
        let clock = Clock()
        let (runner, cloud, _, _) = makeRunner(clock: clock)
        try await runner.connect()
        clock.now += 60_000
        try await runner.backUpNow()
        #expect(await cloud.files.count == 1)
        #expect(await cloud.updates == 1)
    }

    @Test func anotherDevicesFileIsNeverOverwritten() async throws {
        let clock = Clock()
        let cloud = FakeCloud()
        let (other, _, _, _) = makeRunner(clock: clock, cloud: cloud, deviceID: "dev-other")
        try await other.connect()
        let (mine, _, _, _) = makeRunner(clock: clock, cloud: cloud, deviceID: "dev-me")
        try await mine.connect()
        let devices = await cloud.files.values.map { $0.properties["ibDeviceId"] }
        #expect(Set(devices) == ["dev-other", "dev-me"])
    }

    @Test func onlyTheTenNewestOfThisDeviceStay() async throws {
        let clock = Clock()
        let (runner, cloud, _, _) = makeRunner(clock: clock)
        try await runner.connect()
        for _ in 0..<12 {
            clock.now += Self.day
            clock.today = clock.today.adding(days: 1)
            try await runner.backUpNow()
        }
        let names = await cloud.files.values.map(\.name).sorted()
        #expect(names.count == AutoBackupRules.keep)
        #expect(names.first == "InvoiceBackup-2026-10-13.invoicebackup")
        #expect(names.last == "InvoiceBackup-2026-10-22.invoicebackup")
    }

    @Test func automaticBackupsFollowTheRule() async throws {
        let clock = Clock()
        let state = FakeState()
        let (runner, cloud, _, _) = makeRunner(clock: clock, state: state)
        try await runner.connect()
        // Nothing changed since the backup.
        await state.setLatestChange(clock.now - 1)
        #expect(await runner.backUpIfDue() == false)
        // A change, but the last attempt was a minute ago.
        clock.now += 60_000
        await state.setLatestChange(clock.now)
        #expect(await runner.backUpIfDue() == false)
        // Fifteen minutes later it runs.
        clock.now += AutoBackupRules.minimumInterval
        #expect(await runner.backUpIfDue() == true)
        #expect(await cloud.updates == 1)
    }

    @Test func aFailureIsRecordedAndSignedOutStopsAutomaticAttempts() async throws {
        let clock = Clock()
        let cloud = FakeCloud()
        let state = FakeState()
        let (runner, _, _, _) = makeRunner(clock: clock, cloud: cloud, state: state)
        try await runner.connect()
        await cloud.fail(with: .quotaExceeded)
        clock.now += Self.day
        await #expect(throws: CloudBackupError.quotaExceeded) { try await runner.backUpNow() }
        #expect(try await state.cloudBackupState().lastError == .quotaExceeded)

        await cloud.fail(with: .signedOut)
        clock.now += Self.day
        await state.setLatestChange(clock.now)
        await #expect(throws: CloudBackupError.signedOut) { try await runner.backUpNow() }
        clock.now += Self.day
        await state.setLatestChange(clock.now)
        #expect(await runner.backUpIfDue() == false) // waits for the user to reconnect
    }

    @Test func aTrashedFolderIsFoundOrCreatedAgain() async throws {
        let clock = Clock()
        let (runner, cloud, state, _) = makeRunner(clock: clock)
        try await runner.connect()
        let first = try #require(try await state.cloudBackupState().folderID)
        await cloud.trashFolder(first)
        clock.now += 60_000
        try await runner.backUpNow()
        let second = try #require(try await state.cloudBackupState().folderID)
        #expect(second != first)
    }

    @Test func theRestoreListIsNewestFirstAndDownloads() async throws {
        let clock = Clock()
        let (runner, _, _, _) = makeRunner(clock: clock)
        try await runner.connect()
        clock.now += Self.day
        clock.today = clock.today.adding(days: 1)
        try await runner.backUpNow()
        let list = try await runner.list()
        #expect(list.map(\.name) == ["InvoiceBackup-2026-10-11.invoicebackup", "InvoiceBackup-2026-10-10.invoicebackup"])
        #expect(list.first?.invoiceCount == 1)
        let bytes = try await runner.download(try #require(list.first))
        let file = try JSONDecoder().decode(BackupFile.self, from: bytes) // the restore flow validates it (§4)
        #expect(file.data.businesses.map(\.name) == ["Bharat Web Studio"])
    }

    @Test func disconnectingForgetsTheAccountAndKeepsTheFiles() async throws {
        let clock = Clock()
        let (runner, cloud, state, _) = makeRunner(clock: clock)
        try await runner.connect()
        try await runner.disconnect()
        #expect(try await state.cloudBackupState() == CloudBackupState())
        #expect(await cloud.files.count == 1)
        #expect(await cloud.connected == false)
    }

    @Test func longPropertiesAreCutToDrivesLimit() {
        let value = String(repeating: "Ä", count: 100) // 200 bytes
        let cut = AutoBackupRules.fit(value, key: "ibBusinesses")
        #expect(cut.hasSuffix("…"))
        #expect("ibBusinesses".utf8.count + cut.utf8.count <= 124)
        #expect(AutoBackupRules.fit("Rao Traders", key: "ibBusinesses") == "Rao Traders")
    }
}

// MARK: - Fakes

actor FakeCloud: CloudBackupDestination {
    struct File {
        var name: String
        var properties: [String: String]
        var data: Data
        var folder: String
    }

    private(set) var files: [String: File] = [:]
    private(set) var folders: Set<String> = []
    private(set) var updates = 0
    private(set) var connected = false
    private var nextID = 0
    private var failure: CloudBackupError?

    func fail(with error: CloudBackupError?) { failure = error }
    func trashFolder(_ id: String) { folders.remove(id) }

    func connect() async throws -> String {
        connected = true
        return "owner@example.com"
    }

    func disconnect() async { connected = false }

    func folder(knownID: String?) async throws -> String {
        if let knownID, folders.contains(knownID) { return knownID }
        if let existing = folders.sorted().first { return existing }
        let id = makeID("folder")
        folders.insert(id)
        return id
    }

    func list(folderID: String) async throws -> [CloudBackupEntry] {
        files.filter { $0.value.folder == folderID }
            .map { CloudBackupEntry(id: $0.key, name: $0.value.name, properties: $0.value.properties) }
    }

    func upload(_ data: Data, name: String, properties: [String: String], target: CloudBackupTarget,
                folderID: String) async throws -> String {
        if let failure { throw failure }
        switch target {
        case .create:
            let id = makeID("file")
            files[id] = File(name: name, properties: properties, data: data, folder: folderID)
            return id
        case .update(let id):
            updates += 1
            files[id] = File(name: name, properties: properties, data: data, folder: folderID)
            return id
        }
    }

    func download(id: String) async throws -> Data {
        guard let file = files[id] else { throw CloudBackupError.other }
        return file.data
    }

    func delete(id: String) async throws { files[id] = nil }

    private func makeID(_ prefix: String) -> String {
        nextID += 1
        return "\(prefix)-\(String(format: "%03d", nextID))"
    }
}

actor FakeState: CloudBackupStateStore {
    private var state = CloudBackupState()
    private var latest: Int64? = AutoBackupTests.start - 1

    func setLatestChange(_ value: Int64?) { latest = value }

    func cloudBackupState() async throws -> CloudBackupState { state }
    func saveCloudBackupState(_ state: CloudBackupState) async throws { self.state = state }
    nonisolated func observeCloudBackupState() -> AsyncThrowingStream<CloudBackupState, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func latestChangeAt() async throws -> Int64? { latest }
}

actor FakeBackups: BackupService {
    nonisolated let schemaVersion = 4
    let time: TimeSource
    private(set) var recorded: [Int64] = []

    init(time: TimeSource) { self.time = time }

    /// One business with one issued invoice; `createdAt` is the clock's now.
    func makeBackup(app: BackupFile.AppInfo) async throws -> BackupFile {
        var invoice = DocumentSamples.rules().newDocument(docType: .invoice, id: "d1", today: TestConfigs.today, now: 1)
        invoice.lifecycle = .issued
        return BackupFile(createdAt: time.now(), app: app, dbSchemaVersion: 4,
                          data: BackupData(businesses: [DocumentSamples.india], documents: [invoice]))
    }

    func restore(_ file: BackupFile, deviceID: String) async throws {}
    func writeSafetySnapshot() async throws {}
    func recordBackup(at timestamp: Int64) async throws { recorded.append(timestamp) }
    nonisolated func observeStatus() -> AsyncThrowingStream<BackupStatus, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
