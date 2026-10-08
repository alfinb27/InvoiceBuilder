import Foundation
import GRDB
import InvoiceCore

/// Export and "replace all" restore (`spec/backup.md`).
public struct GRDBBackupService: BackupService {
    let database: AppDatabase
    let time: TimeSource
    let ids: IDGenerator
    /// Where safety snapshots go (§4 step 3).
    let snapshots: BackupSnapshotStore
    public let schemaVersion: Int

    public init(database: AppDatabase, time: TimeSource, ids: IDGenerator, snapshots: BackupSnapshotStore) throws {
        self.database = database
        self.time = time
        self.ids = ids
        self.snapshots = snapshots
        schemaVersion = try AppDatabase.schemaVersion()
    }

    public func makeBackup(app: BackupFile.AppInfo) async throws -> BackupFile {
        let now = time.now()
        let data = try await database.writer.read { db in try Self.exportData(db) }
        return BackupFile(createdAt: now, app: app, dbSchemaVersion: schemaVersion, data: data)
    }

    public func writeSafetySnapshot() async throws {
        let snapshot = try await makeBackup(app: BackupFile.AppInfo(platform: "ios", version: "snapshot"))
        try snapshots.write(snapshot, at: time.now())
    }

    public func restore(_ file: BackupFile, deviceID: String) async throws {
        // §4 step 3: no snapshot, no restore.
        try await writeSafetySnapshot()

        let now = time.now(), ids = self.ids
        try await database.writer.write { db in
            try Self.replaceAll(with: file.data, deviceID: deviceID, now: now, ids: ids, db: db)
        }
    }

    public func recordBackup(at timestamp: Int64) async throws {
        try await database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO app_state (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """, arguments: [Self.lastBackupKey, String(timestamp)])
        }
    }

    public func observeStatus() -> AsyncThrowingStream<BackupStatus, any Error> {
        database.observe { db in
            let last = try String.fetchOne(db, sql: "SELECT value FROM app_state WHERE key = ?",
                                           arguments: [Self.lastBackupKey]).flatMap { Int64($0) }
            let issued = try Bool.fetchOne(db, sql: """
                SELECT EXISTS (SELECT 1 FROM document WHERE lifecycle <> 'draft' AND deleted_at IS NULL)
                """) ?? false
            return BackupStatus(lastBackupAt: last, hasIssuedDocuments: issued)
        }
    }

    static let lastBackupKey = "last_backup_at"

    // MARK: Export (§1)

    static func exportData(_ db: Database) throws -> BackupData {
        let byCreation = [DBColumns.createdAt, DBColumns.id]
        var linesByDocument: [String: [LineItem]] = [:]
        for record in try LineItemRecord.live.order(DBColumns.position, DBColumns.id).fetchAll(db) {
            linesByDocument[record.documentId, default: []].append(try record.line())
        }
        return BackupData(
            businesses: try BusinessRecord.order(byCreation).fetchAll(db).map { try $0.business() },
            clients: try ClientRecord.order(byCreation).fetchAll(db).map { try $0.client() },
            catalogItems: try CatalogItemRecord.order(byCreation).fetchAll(db).map { $0.item() },
            numberingSeries: try NumberingSeriesRecord.order(byCreation).fetchAll(db).map { try $0.series() },
            documents: try DocumentRecord.order(byCreation).fetchAll(db).map { record in
                try record.document(lines: linesByDocument[record.id] ?? [])
            },
            payments: try PaymentRecord.order(byCreation).fetchAll(db).map { try $0.payment() },
            assets: try AssetRecord.order(byCreation).fetchAll(db).map { $0.asset() }
        ).sorted()
    }

    // MARK: Restore (§4 step 4)

    static func replaceAll(with data: BackupData, deviceID: String, now: Int64, ids: IDGenerator,
                           db: Database) throws {
        // Rows reference each other in every direction (business ↔ asset, document → document); checking keys at
        // commit lets them be written in any order.
        try db.execute(sql: "PRAGMA defer_foreign_keys = ON")

        try write(data.assets.map(AssetRecord.init), db: db)
        try write(data.businesses.map(BusinessRecord.init), db: db)
        try write(data.clients.map(ClientRecord.init), db: db)
        try write(data.catalogItems.map(CatalogItemRecord.init), db: db)
        try write(data.numberingSeries.map(NumberingSeriesRecord.init), db: db)
        try write(data.documents.map(DocumentRecord.init), db: db)
        try write(data.payments.map(PaymentRecord.init), db: db)
        try write(data.documents.flatMap { document in
            try document.lines.map {
                try LineItemRecord($0, documentID: document.id, createdAt: document.updatedAt,
                                   updatedAt: document.updatedAt)
            }
        }, db: db)

        // Everything else that is live goes, as tombstones so sync carries the deletion.
        try tombstoneOthers(TaxLineRecord.self, keeping: [], now: now, db: db)
        for document in data.documents {
            for taxLine in document.computed?.taxLines ?? [] {
                try TaxLineRecord(id: ids.make(), documentID: document.id, taxLine: taxLine, now: now).insert(db)
            }
        }
        try tombstoneOthers(LineItemRecord.self, keeping: Set(data.documents.flatMap { $0.lines.map(\.id) }),
                            now: now, db: db)
        try tombstoneOthers(PaymentRecord.self, keeping: Set(data.payments.map(\.id)), now: now, db: db)
        try tombstoneOthers(DocumentRecord.self, keeping: Set(data.documents.map(\.id)), now: now, db: db)
        try tombstoneOthers(NumberingSeriesRecord.self, keeping: Set(data.numberingSeries.map(\.id)), now: now, db: db)
        try tombstoneOthers(CatalogItemRecord.self, keeping: Set(data.catalogItems.map(\.id)), now: now, db: db)
        try tombstoneOthers(ClientRecord.self, keeping: Set(data.clients.map(\.id)), now: now, db: db)
        try tombstoneOthers(BusinessRecord.self, keeping: Set(data.businesses.map(\.id)), now: now, db: db)
        try tombstoneOthers(AssetRecord.self, keeping: Set(data.assets.map(\.id)), now: now, db: db)

        try takeOverSeries(deviceID: deviceID, now: now, db: db)
    }

    /// Each row as the backup has it: an existing row with the id is updated, otherwise inserted (never a
    /// replacing `INSERT`, whose implicit delete would cascade).
    private static func write<Record: SnakeCaseRecord>(_ records: [Record], db: Database) throws {
        for record in records { try record.save(db) }
    }

    private static func tombstoneOthers<Record: SnakeCaseRecord>(_ type: Record.Type, keeping kept: Set<String>,
                                                                 now: Int64, db: Database) throws {
        let live = try String.fetchAll(db, Record.live.select(DBColumns.id))
        for id in live where !kept.contains(id) {
            try Record.filter(key: id)
                .updateAll(db, DBColumns.deletedAt.set(to: now), DBColumns.updatedAt.set(to: now))
        }
    }

    /// §4: for each live business and document type with no live series owned by this device, take over the one
    /// the allocator would pick (earliest `createdAt`, then lowest `id`).
    private static func takeOverSeries(deviceID: String, now: Int64, db: Database) throws {
        let liveBusinesses = Set(try String.fetchAll(db, BusinessRecord.live.select(DBColumns.id)))
        let series = try NumberingSeriesRecord.live.order(DBColumns.createdAt, DBColumns.id).fetchAll(db)
            .filter { liveBusinesses.contains($0.businessId) }
        let groups = Dictionary(grouping: series) { "\($0.businessId)|\($0.docType)" }
        for group in groups.values where !group.contains(where: { $0.ownerDeviceId == deviceID }) {
            guard var first = group.first else { continue }
            first.ownerDeviceId = deviceID
            first.updatedAt = now
            try first.update(db)
        }
    }
}

/// Safety snapshots (`spec/backup.md` §4 step 3): `pre-restore-<epoch ms>.invoicebackup`, newest 3 kept.
public struct BackupSnapshotStore: Sendable {
    public let directory: URL
    public static let kept = 3

    public init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/InvoiceBuilder/Snapshots`, beside the database.
    public static func defaultStore() throws -> BackupSnapshotStore {
        BackupSnapshotStore(directory: try AppDatabase.defaultURL().deletingLastPathComponent()
            .appending(path: "Snapshots"))
    }

    /// A fresh folder in the temporary directory (tests, in-memory launches).
    public static func temporary() -> BackupSnapshotStore {
        BackupSnapshotStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "InvoiceBuilder-snapshots-\(UUID().uuidString.lowercased())"))
    }

    @discardableResult
    public func write(_ file: BackupFile, at timestamp: Int64) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "pre-restore-\(timestamp).\(BackupFile.fileExtension)")
        try BackupCodec.encode(file).write(to: url, options: [.atomic, .completeFileProtection])
        let old = try snapshots().dropFirst(Self.kept)
        for stale in old { try? FileManager.default.removeItem(at: stale) }
        return url
    }

    /// Newest first.
    public func snapshots() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("pre-restore-") && $0.pathExtension == BackupFile.fileExtension }
            .sorted { Self.stamp($0) > Self.stamp($1) }
    }

    private static func stamp(_ url: URL) -> Int64 {
        Int64(url.deletingPathExtension().lastPathComponent.dropFirst("pre-restore-".count)) ?? 0
    }
}
