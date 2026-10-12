import Foundation

/// A file in the cloud backup folder (`spec/backup.md` §7.3). The `ib…` app properties are nil on a file the app
/// didn't tag (put there by hand).
public struct CloudBackupEntry: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var deviceID: String?
    public var deviceName: String?
    /// `ios` or `android`.
    public var platform: String?
    /// The backup's `createdAt`, epoch ms UTC.
    public var createdAt: Int64?
    public var businesses: String?
    public var invoiceCount: Int?
    public var clientCount: Int?

    public init(id: String, name: String, deviceID: String? = nil, deviceName: String? = nil, platform: String? = nil,
                createdAt: Int64? = nil, businesses: String? = nil, invoiceCount: Int? = nil, clientCount: Int? = nil) {
        self.id = id
        self.name = name
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.platform = platform
        self.createdAt = createdAt
        self.businesses = businesses
        self.invoiceCount = invoiceCount
        self.clientCount = clientCount
    }

    /// The app wrote this file (it carries the device and the time).
    public var isTagged: Bool { deviceID != nil && createdAt != nil }

    /// §7.3: reads the Drive `appProperties`.
    public init(id: String, name: String, properties: [String: String]) {
        self.init(id: id, name: name, deviceID: properties[Key.deviceID], deviceName: properties[Key.deviceName],
                  platform: properties[Key.platform], createdAt: properties[Key.createdAt].flatMap { Int64($0) },
                  businesses: properties[Key.businesses], invoiceCount: properties[Key.invoices].flatMap { Int($0) },
                  clientCount: properties[Key.clients].flatMap { Int($0) })
    }

    enum Key {
        static let deviceID = "ibDeviceId", deviceName = "ibDeviceName", platform = "ibPlatform"
        static let createdAt = "ibCreatedAt", formatVersion = "ibFormatVersion", businesses = "ibBusinesses"
        static let invoices = "ibInvoices", clients = "ibClients"
    }
}

/// Where a backup goes (`spec/backup.md` §7.3).
public enum CloudBackupTarget: Hashable, Sendable {
    case create
    /// Replace this file's content and properties.
    case update(id: String)
}

/// The pure rules of automatic cloud backup (`spec/backup.md` §7; fixtures kind `autobackup`).
public enum AutoBackupRules {
    /// §7.2: at most one automatic attempt per 15 minutes.
    public static let minimumInterval: Int64 = 15 * 60 * 1000
    /// §7.4: the newest backups of this device that stay.
    public static let keep = 10
    /// Drive allows 124 bytes per property, key plus value.
    static let propertyBytes = 124

    /// §7.2: something changed since the last cloud backup and no attempt ran in the last 15 minutes.
    public static func isDue(lastBackupAt: Int64?, latestChangeAt: Int64?, lastAttemptAt: Int64?, now: Int64) -> Bool {
        guard let latestChangeAt else { return false }
        if let lastBackupAt, latestChangeAt <= lastBackupAt { return false }
        if let lastAttemptAt, now - lastAttemptAt < minimumInterval { return false }
        return true
    }

    /// §7.3: replace this device's newest file of today, otherwise create one. Never another device's file.
    public static func target(entries: [CloudBackupEntry], fileName: String, deviceID: String) -> CloudBackupTarget {
        let own = newestFirst(entries).first { $0.name == fileName && $0.deviceID == deviceID }
        return own.map { .update(id: $0.id) } ?? .create
    }

    /// §7.4: this device's files beyond the `keep` newest, oldest first.
    public static func filesToDelete(entries: [CloudBackupEntry], deviceID: String, keep: Int = keep) -> [String] {
        let own = newestFirst(entries).filter { $0.deviceID == deviceID }
        return own.dropFirst(keep).reversed().map(\.id)
    }

    /// §7.6: tagged files, newest first (larger `createdAt`; then larger id).
    public static func newestFirst(_ entries: [CloudBackupEntry]) -> [CloudBackupEntry] {
        entries.filter(\.isTagged).sorted { a, b in
            let (x, y) = (a.createdAt ?? 0, b.createdAt ?? 0)
            return x != y ? x > y : a.id > b.id
        }
    }

    /// §7.3: the `appProperties` a backup file carries, each cut to fit Drive's limit.
    public static func properties(for file: BackupFile, deviceID: String, deviceName: String) -> [String: String] {
        let data = file.data
        let businesses = data.businesses.filter { $0.deletedAt == nil }.map(\.name).joined(separator: ", ")
        let invoices = data.documents.filter {
            $0.deletedAt == nil && $0.docType == .invoice && $0.lifecycle == .issued
        }.count
        let clients = data.clients.filter { $0.deletedAt == nil }.count
        typealias Key = CloudBackupEntry.Key
        let raw: [String: String] = [
            Key.deviceID: deviceID, Key.deviceName: deviceName, Key.platform: file.app.platform,
            Key.createdAt: String(file.createdAt), Key.formatVersion: String(file.formatVersion),
            Key.businesses: businesses, Key.invoices: String(invoices), Key.clients: String(clients),
        ]
        return raw.reduce(into: [:]) { result, pair in result[pair.key] = fit(pair.value, key: pair.key) }
    }

    /// Cuts `value` (adding "…") so key plus value fit in Drive's 124 bytes.
    static func fit(_ value: String, key: String) -> String {
        let room = propertyBytes - key.utf8.count
        guard value.utf8.count > room else { return value }
        var cut = value
        while !cut.isEmpty, cut.utf8.count + "…".utf8.count > room { cut.removeLast() }
        return cut + "…"
    }
}

/// Why a cloud backup failed (`spec/backup.md` §7.5); the raw value is `app_state.drive_last_error`.
public enum CloudBackupError: String, Error, Hashable, Sendable {
    /// Consent revoked or expired: the user reconnects.
    case signedOut
    case quotaExceeded
    case networkUnavailable
    /// The user closed the sign-in sheet (never stored).
    case cancelled
    case other
}

/// The cloud backup state kept in `app_state` (`spec/backup.md` §7.7).
public struct CloudBackupState: Hashable, Sendable {
    public var accountEmail: String?
    public var folderID: String?
    public var lastBackupAt: Int64?
    public var lastAttemptAt: Int64?
    public var lastError: CloudBackupError?

    public init(accountEmail: String? = nil, folderID: String? = nil, lastBackupAt: Int64? = nil,
                lastAttemptAt: Int64? = nil, lastError: CloudBackupError? = nil) {
        self.accountEmail = accountEmail
        self.folderID = folderID
        self.lastBackupAt = lastBackupAt
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
    }

    public var isConnected: Bool { accountEmail != nil }

    static let keys = (account: "drive_account_email", folder: "drive_folder_id", lastBackup: "drive_last_backup_at",
                       lastAttempt: "drive_last_attempt_at", lastError: "drive_last_error")

    /// The `app_state` rows (nil = delete the row).
    public var rows: [String: String?] {
        [Self.keys.account: accountEmail, Self.keys.folder: folderID, Self.keys.lastBackup: lastBackupAt.map(String.init),
         Self.keys.lastAttempt: lastAttemptAt.map(String.init), Self.keys.lastError: lastError?.rawValue]
    }

    public init(rows: [String: String]) {
        self.init(accountEmail: rows[Self.keys.account], folderID: rows[Self.keys.folder],
                  lastBackupAt: rows[Self.keys.lastBackup].flatMap { Int64($0) },
                  lastAttemptAt: rows[Self.keys.lastAttempt].flatMap { Int64($0) },
                  lastError: rows[Self.keys.lastError].flatMap(CloudBackupError.init(rawValue:)))
    }

    public static var rowKeys: [String] {
        [keys.account, keys.folder, keys.lastBackup, keys.lastAttempt, keys.lastError]
    }
}

/// A cloud the user backs up to (`spec/backup.md` §7; Google Drive in `InvoiceDrive`). Calls throw
/// `CloudBackupError`.
public protocol CloudBackupDestination: Sendable {
    /// Signs in (asking for the one scope) and returns the account's email.
    func connect() async throws -> String
    /// Revokes the token and forgets the account on this device.
    func disconnect() async
    /// §7.1: the app's folder — `knownID` when it is still there, otherwise found or created.
    func folder(knownID: String?) async throws -> String
    func list(folderID: String) async throws -> [CloudBackupEntry]
    /// Writes `data` (create or replace per `target`) and returns the file's id.
    func upload(_ data: Data, name: String, properties: [String: String], target: CloudBackupTarget,
                folderID: String) async throws -> String
    func download(id: String) async throws -> Data
    func delete(id: String) async throws
}

/// Reads and writes the §7.7 state and knows when data last changed (`BackupService` implementations add these).
public protocol CloudBackupStateStore: Sendable {
    func cloudBackupState() async throws -> CloudBackupState
    func saveCloudBackupState(_ state: CloudBackupState) async throws
    func observeCloudBackupState() -> AsyncThrowingStream<CloudBackupState, any Error>
    /// §7.2: the highest `updated_at` over the synced tables; nil without rows.
    func latestChangeAt() async throws -> Int64?
}

/// Runs automatic cloud backups (`spec/backup.md` §7): connect, back up when due or now, prune, list, download.
public actor AutoBackupRunner {
    public struct Device: Sendable {
        public var id: String
        /// The model name ("iPhone", "Pixel 8").
        public var name: String
        public var app: BackupFile.AppInfo

        public init(id: String, name: String, app: BackupFile.AppInfo) {
            self.id = id
            self.name = name
            self.app = app
        }
    }

    let destination: any CloudBackupDestination
    let backups: any BackupService
    let state: any CloudBackupStateStore
    let time: TimeSource
    let device: Device
    private var running = false

    public init(destination: any CloudBackupDestination, backups: any BackupService, state: any CloudBackupStateStore,
                time: TimeSource, device: Device) {
        self.destination = destination
        self.backups = backups
        self.state = state
        self.time = time
        self.device = device
    }

    /// §7.1: sign in, find or create the folder, back up at once when there is data (a new phone restoring has none).
    /// A failed first backup keeps the connection.
    public func connect() async throws {
        let email = try await destination.connect()
        let folder = try await destination.folder(knownID: nil)
        var current = try await state.cloudBackupState()
        current.accountEmail = email
        current.folderID = folder
        current.lastError = nil
        try await state.saveCloudBackupState(current)
        if try await state.latestChangeAt() != nil { try? await backUpNow() }
    }

    /// §7.1: revoke and forget; files stay in the cloud.
    public func disconnect() async throws {
        await destination.disconnect()
        try await state.saveCloudBackupState(CloudBackupState())
    }

    /// §7.2: the automatic path. Returns whether a backup was written.
    @discardableResult
    public func backUpIfDue() async -> Bool {
        guard let current = try? await state.cloudBackupState(), current.isConnected,
              current.lastError != .signedOut,
              let latest = try? await state.latestChangeAt(),
              AutoBackupRules.isDue(lastBackupAt: current.lastBackupAt, latestChangeAt: latest,
                                    lastAttemptAt: current.lastAttemptAt, now: time.now())
        else { return false }
        return (try? await backUpNow()) != nil
    }

    /// §7.2 "Back up now": export, upload (§7.3), prune (§7.4), record the result (§7.5).
    public func backUpNow() async throws {
        guard !running else { return }
        running = true
        defer { running = false }
        var current = try await state.cloudBackupState()
        guard current.isConnected else { throw CloudBackupError.signedOut }
        current.lastAttemptAt = time.now()
        try await state.saveCloudBackupState(current)
        do {
            let file = try await backups.makeBackup(app: device.app)
            // §7.3: a folder that is gone or trashed is found or created again.
            let folder = try await destination.folder(knownID: current.folderID)
            try await upload(file, folderID: folder)
            current.folderID = folder
            current.lastBackupAt = file.createdAt
            current.lastError = nil
            try await state.saveCloudBackupState(current)
            try await backups.recordBackup(at: time.now())
        } catch {
            current.lastError = (error as? CloudBackupError) ?? .other
            try? await state.saveCloudBackupState(current)
            throw current.lastError ?? CloudBackupError.other
        }
    }

    /// §7.6: every tagged backup in the folder, newest first.
    public func list() async throws -> [CloudBackupEntry] {
        let folder = try await destination.folder(knownID: try await state.cloudBackupState().folderID)
        return AutoBackupRules.newestFirst(try await destination.list(folderID: folder))
    }

    public func download(_ entry: CloudBackupEntry) async throws -> Data {
        try await destination.download(id: entry.id)
    }

    private func upload(_ file: BackupFile, folderID: String) async throws {
        let data = try BackupCodec.encode(file)
        let name = BackupFile.fileName(on: time.today())
        let entries = try await destination.list(folderID: folderID)
        let target = AutoBackupRules.target(entries: entries, fileName: name, deviceID: device.id)
        let properties = AutoBackupRules.properties(for: file, deviceID: device.id, deviceName: device.name)
        let id = try await destination.upload(data, name: name, properties: properties, target: target,
                                              folderID: folderID)
        // §7.4: prune with the new file in the list (a failed delete waits for the next backup).
        var after = entries.filter { $0.id != id }
        after.append(CloudBackupEntry(id: id, name: name, properties: properties))
        for old in AutoBackupRules.filesToDelete(entries: after, deviceID: device.id) {
            try? await destination.delete(id: old)
        }
    }
}
