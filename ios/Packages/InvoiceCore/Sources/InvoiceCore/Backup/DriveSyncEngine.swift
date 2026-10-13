import Foundation

/// A change file (`spec/drive-sync.md` §3): one push's records, written once by one device.
public struct DriveSyncChanges: Codable, Hashable, Sendable {
    public static let formatVersion = 1

    public var formatVersion: Int
    public var deviceId: String
    public var seq: Int
    public var createdAt: Int64
    public var data: BackupData

    public init(formatVersion: Int = Self.formatVersion, deviceId: String, seq: Int, createdAt: Int64, data: BackupData) {
        self.formatVersion = formatVersion
        self.deviceId = deviceId
        self.seq = seq
        self.createdAt = createdAt
        self.data = data
    }

    public static func fileName(deviceID: String, seq: Int) -> String {
        "changes-\(deviceID)-\(String(format: "%08d", seq)).json"
    }
}

/// A device's snapshot (§8): all records, plus the change files they include.
public struct DriveSyncSnapshot: Codable, Hashable, Sendable {
    public var formatVersion: Int
    public var deviceId: String
    public var createdAt: Int64
    /// The highest `seq` per device this snapshot includes (this device's own among them).
    public var covers: [String: Int]
    public var data: BackupData

    public init(formatVersion: Int = DriveSyncChanges.formatVersion, deviceId: String, createdAt: Int64,
                covers: [String: Int], data: BackupData) {
        self.formatVersion = formatVersion
        self.deviceId = deviceId
        self.createdAt = createdAt
        self.covers = covers
        self.data = data
    }

    public static func fileName(deviceID: String) -> String { "snapshot-\(deviceID).json" }
}

/// The Drive sync state in `app_state` (`spec/drive-sync.md` §4, §6, §9).
public struct DriveSyncState: Hashable, Sendable {
    public var accountEmail: String?
    public var folderID: String?
    /// §4: records with `updatedAt` at or after this are pushed next (epoch ms; 0 = everything).
    public var pushedAt: Int64
    public var nextSeq: Int
    /// §6: the highest `seq` merged per other device.
    public var seen: [String: Int]
    /// §8: the drive id of this device's snapshot file, and the own `seq` it covers.
    public var snapshotID: String?
    public var snapshotCovers: Int?
    public var lastSyncAt: Int64?
    public var lastError: CloudBackupError?

    public init(accountEmail: String? = nil, folderID: String? = nil, pushedAt: Int64 = 0, nextSeq: Int = 1,
                seen: [String: Int] = [:], snapshotID: String? = nil, snapshotCovers: Int? = nil,
                lastSyncAt: Int64? = nil, lastError: CloudBackupError? = nil) {
        self.accountEmail = accountEmail
        self.folderID = folderID
        self.pushedAt = pushedAt
        self.nextSeq = nextSeq
        self.seen = seen
        self.snapshotID = snapshotID
        self.snapshotCovers = snapshotCovers
        self.lastSyncAt = lastSyncAt
        self.lastError = lastError
    }

    public var isConnected: Bool { accountEmail != nil }

    enum Key {
        static let account = "drive_sync_account_email", folder = "drive_sync_folder_id"
        static let pushedAt = "drive_sync_pushed_at", nextSeq = "drive_sync_next_seq", seen = "drive_sync_seen"
        static let snapshotID = "drive_sync_snapshot_id", snapshotCovers = "drive_sync_snapshot_covers"
        static let lastSync = "drive_sync_last_sync_at", lastError = "drive_sync_last_error"
    }

    public static let rowKeys = [Key.account, Key.folder, Key.pushedAt, Key.nextSeq, Key.seen, Key.snapshotID,
                                 Key.snapshotCovers, Key.lastSync, Key.lastError]

    /// The `app_state` rows (nil = delete the row).
    public var rows: [String: String?] {
        let seenText = (try? JSONEncoder.sorted.encode(seen)).flatMap { String(data: $0, encoding: .utf8) }
        return [Key.account: accountEmail, Key.folder: folderID, Key.pushedAt: String(pushedAt),
                Key.nextSeq: String(nextSeq), Key.seen: seen.isEmpty ? nil : seenText,
                Key.snapshotID: snapshotID, Key.snapshotCovers: snapshotCovers.map(String.init),
                Key.lastSync: lastSyncAt.map(String.init), Key.lastError: lastError?.rawValue]
    }

    public init(rows: [String: String]) {
        let seen = rows[Key.seen].flatMap { try? JSONDecoder().decode([String: Int].self, from: Data($0.utf8)) }
        self.init(accountEmail: rows[Key.account], folderID: rows[Key.folder],
                  pushedAt: rows[Key.pushedAt].flatMap { Int64($0) } ?? 0,
                  nextSeq: rows[Key.nextSeq].flatMap { Int($0) } ?? 1, seen: seen ?? [:],
                  snapshotID: rows[Key.snapshotID], snapshotCovers: rows[Key.snapshotCovers].flatMap { Int($0) },
                  lastSyncAt: rows[Key.lastSync].flatMap { Int64($0) },
                  lastError: rows[Key.lastError].flatMap(CloudBackupError.init(rawValue:)))
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// The sync folder in the user's Drive (`spec/drive-sync.md` §3), beside the backup calls.
public protocol DriveSyncDestination: CloudBackupDestination {
    /// "InvoiceBuilder sync": `knownID` when it is still there, otherwise found or created.
    func syncFolder(knownID: String?) async throws -> String
    func syncEntries(folderID: String) async throws -> [DriveSyncEntry]
}

/// The database side of Drive sync (`GRDBBackupService` implements it).
public protocol DriveSyncStore: Sendable {
    func driveSyncState() async throws -> DriveSyncState
    func saveDriveSyncState(_ state: DriveSyncState) async throws
    func observeDriveSyncState() -> AsyncThrowingStream<DriveSyncState, any Error>
    /// §4: every record with `updatedAt >= since`, tombstones included (a document with its live lines).
    func changes(since: Int64) async throws -> BackupData
    /// Every record, for a snapshot.
    func allRecords() async throws -> BackupData
    /// §5: merges `data` record by record in one transaction and saves `state` in the same transaction.
    /// Returns how many records changed.
    @discardableResult
    func merge(_ data: BackupData, state: DriveSyncState) async throws -> Int
}

/// Runs live sync through Google Drive (`spec/drive-sync.md`): connect, pull, push, compaction.
public actor DriveSyncEngine {
    let destination: any DriveSyncDestination
    let store: any DriveSyncStore
    let time: TimeSource
    let deviceID: String
    /// The sync in progress: a second request waits for it.
    private var current: Task<Int, any Error>?

    public init(destination: any DriveSyncDestination, store: any DriveSyncStore, time: TimeSource, deviceID: String) {
        self.destination = destination
        self.store = store
        self.time = time
        self.deviceID = deviceID
    }

    /// §7: sign in, find or create the folder, then a full sync from scratch (`seen = {}`, everything pushed).
    public func connect() async throws {
        let email = try await destination.connect()
        let folder = try await destination.syncFolder(knownID: nil)
        try await store.saveDriveSyncState(DriveSyncState(accountEmail: email, folderID: folder))
        try await syncNow()
    }

    /// §7: turn sync off and forget the state; the files stay.
    public func disconnect() async throws {
        try await store.saveDriveSyncState(DriveSyncState())
    }

    /// Pull, then push (§4, §6). Returns how many records the pull changed (the app then runs `sync.md` §5).
    @discardableResult
    public func syncNow() async throws -> Int {
        if let current { return try await current.value }
        let task = Task { try await perform() }
        current = task
        defer { current = nil }
        return try await task.value
    }

    private func perform() async throws -> Int {
        var state = try await store.driveSyncState()
        guard state.isConnected else { throw CloudBackupError.signedOut }
        do {
            let folder = try await destination.syncFolder(knownID: state.folderID)
            if folder != state.folderID {
                // A new folder (the old one was trashed): start over in it.
                state = DriveSyncState(accountEmail: state.accountEmail, folderID: folder)
                try await store.saveDriveSyncState(state)
            }
            let changed = try await pull(folder: folder)
            try await push(folder: folder)
            state = try await store.driveSyncState()
            state.lastSyncAt = time.now()
            state.lastError = nil
            try await store.saveDriveSyncState(state)
            return changed
        } catch {
            let failure = (error as? CloudBackupError) ?? .other
            var failed = (try? await store.driveSyncState()) ?? state
            failed.lastError = failure
            try? await store.saveDriveSyncState(failed)
            throw failure
        }
    }

    // MARK: §6 pull

    private func pull(folder: String) async throws -> Int {
        var changed = 0
        // A snapshot read changes `seen`, so list again until only change files (or nothing) remain.
        for _ in 0..<16 {
            let entries = try await destination.syncEntries(folderID: folder)
            var state = try await store.driveSyncState()
            let ids = DriveSync.toRead(entries: entries, seen: state.seen, thisDevice: deviceID)
            guard !ids.isEmpty else { break }
            let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var readSnapshot = false
            for id in ids {
                let bytes = try await destination.download(id: id)
                if byID[id]?.kind == .snapshot {
                    let snapshot = try decode(DriveSyncSnapshot.self, bytes)
                    for (device, seq) in snapshot.covers where device != deviceID {
                        state.seen[device] = max(state.seen[device] ?? 0, seq)
                    }
                    changed += try await store.merge(snapshot.data, state: state)
                    readSnapshot = true
                } else {
                    let file = try decode(DriveSyncChanges.self, bytes)
                    state.seen[file.deviceId] = max(state.seen[file.deviceId] ?? 0, file.seq)
                    changed += try await store.merge(file.data, state: state)
                }
            }
            if !readSnapshot { break }
        }
        return changed
    }

    /// §9: a newer format stops the pull at that file.
    private func decode<T: Decodable>(_ type: T.Type, _ bytes: Data) throws -> T {
        if let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
           let version = object["formatVersion"] as? Int, version > DriveSyncChanges.formatVersion {
            throw CloudBackupError.other
        }
        do { return try JSONDecoder().decode(type, from: bytes) } catch { throw CloudBackupError.other }
    }

    // MARK: §4 push

    private func push(folder: String) async throws {
        var state = try await store.driveSyncState()
        let start = time.now()
        let data = try await store.changes(since: state.pushedAt)
        guard data.counts != BackupData().counts else { return }
        let seq = state.nextSeq
        let file = DriveSyncChanges(deviceId: deviceID, seq: seq, createdAt: start, data: data)
        _ = try await destination.upload(try JSONEncoder.sorted.encode(file),
                                         name: DriveSyncChanges.fileName(deviceID: deviceID, seq: seq),
                                         properties: [DriveSyncEntry.Key.kind: DriveSyncEntry.Kind.changes.rawValue,
                                                      DriveSyncEntry.Key.deviceID: deviceID,
                                                      DriveSyncEntry.Key.seq: String(seq),
                                                      DriveSyncEntry.Key.createdAt: String(start)],
                                         target: .create, folderID: folder)
        state.pushedAt = start
        state.nextSeq = seq + 1
        try await store.saveDriveSyncState(state)
        try? await compact(folder: folder)
    }

    // MARK: §8 compaction

    private func compact(folder: String) async throws {
        var state = try await store.driveSyncState()
        let entries = try await destination.syncEntries(folderID: folder)
        let own = entries.filter { $0.kind == .changes && $0.deviceID == deviceID }
        if own.count > DriveSync.snapshotAfter {
            let covered = state.nextSeq - 1
            var covers = state.seen
            covers[deviceID] = covered
            let snapshot = DriveSyncSnapshot(deviceId: deviceID, createdAt: time.now(), covers: covers,
                                             data: try await store.allRecords())
            let existing = entries.first { $0.kind == .snapshot && $0.deviceID == deviceID }?.id ?? state.snapshotID
            let id = try await destination.upload(
                try JSONEncoder.sorted.encode(snapshot), name: DriveSyncSnapshot.fileName(deviceID: deviceID),
                properties: [DriveSyncEntry.Key.kind: DriveSyncEntry.Kind.snapshot.rawValue,
                             DriveSyncEntry.Key.deviceID: deviceID,
                             DriveSyncEntry.Key.createdAt: String(snapshot.createdAt)],
                target: existing.map { .update(id: $0) } ?? .create, folderID: folder)
            state.snapshotID = id
            state.snapshotCovers = covered
            try await store.saveDriveSyncState(state)
        }
        for id in DriveSync.filesToDelete(entries: entries, thisDevice: deviceID,
                                          snapshotCovers: state.snapshotCovers, now: time.now()) {
            try? await destination.delete(id: id)
        }
    }
}
