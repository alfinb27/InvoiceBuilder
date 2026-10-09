import Foundation
import GRDB
import InvoiceCore

// GRDB implementations of InvoiceCore's repository protocols. Reads never return tombstoned rows; deletes write a
// tombstone (`spec/setup.md` §1). `save` inserts or updates by id, keeps the stored `created_at` and stamps
// `updated_at`.

public struct GRDBBusinessRepository: BusinessRepository {
    let database: AppDatabase
    let time: TimeSource

    public init(database: AppDatabase, time: TimeSource) {
        self.database = database
        self.time = time
    }

    public func observeBusiness(id: String) -> AsyncThrowingStream<Business?, any Error> {
        database.observe { db in try BusinessRecord.live.filter(key: id).fetchOne(db)?.business() }
    }

    public func fetchBusiness(id: String) async throws -> Business? {
        try await database.writer.read { db in try BusinessRecord.live.filter(key: id).fetchOne(db)?.business() }
    }

    public func fetchBusinesses() async throws -> [Business] {
        try await database.writer.read { db in
            try BusinessRecord.live.order(DBColumns.createdAt, DBColumns.id).fetchAll(db).map { try $0.business() }
        }
    }

    @discardableResult
    public func save(_ business: Business) async throws -> Business {
        let now = time.now()
        return try await database.writer.write { db in
            var stored = business
            stored.updatedAt = now
            if let existing = try BusinessRecord.fetchOne(db, key: business.id) {
                stored.createdAt = existing.createdAt
                try BusinessRecord(stored).update(db)
            } else {
                stored.createdAt = now
                try BusinessRecord(stored).insert(db)
            }
            return stored
        }
    }
}

public struct GRDBClientRepository: ClientRepository {
    let database: AppDatabase
    let time: TimeSource

    public init(database: AppDatabase, time: TimeSource) {
        self.database = database
        self.time = time
    }

    public func observeClients(businessID: String) -> AsyncThrowingStream<[Client], any Error> {
        database.observe { db in
            try ClientRecord.live.filter(DBColumns.businessID == businessID).fetchAll(db).map { try $0.client() }
        }
    }

    public func observeClient(id: String) -> AsyncThrowingStream<Client?, any Error> {
        database.observe { db in try ClientRecord.live.filter(key: id).fetchOne(db)?.client() }
    }

    public func fetchClient(id: String) async throws -> Client? {
        try await database.writer.read { db in try ClientRecord.live.filter(key: id).fetchOne(db)?.client() }
    }

    @discardableResult
    public func save(_ client: Client) async throws -> Client {
        let now = time.now()
        return try await database.writer.write { db in
            var stored = client
            stored.updatedAt = now
            if let existing = try ClientRecord.fetchOne(db, key: client.id) {
                stored.createdAt = existing.createdAt
                try ClientRecord(stored).update(db)
            } else {
                stored.createdAt = now
                try ClientRecord(stored).insert(db)
            }
            return stored
        }
    }

    public func setArchived(_ archived: Bool, clientID: String) async throws {
        try await database.stamp(ClientRecord.self, id: clientID, now: time.now(), column: "archived_at",
                                 set: archived)
    }

    public func delete(clientID: String) async throws {
        try await database.stamp(ClientRecord.self, id: clientID, now: time.now(), column: "deleted_at", set: true)
    }
}

public struct GRDBCatalogRepository: CatalogRepository {
    let database: AppDatabase
    let time: TimeSource

    public init(database: AppDatabase, time: TimeSource) {
        self.database = database
        self.time = time
    }

    public func observeItems(businessID: String) -> AsyncThrowingStream<[CatalogItem], any Error> {
        database.observe { db in
            try CatalogItemRecord.live.filter(DBColumns.businessID == businessID).fetchAll(db).map { $0.item() }
        }
    }

    public func observeItem(id: String) -> AsyncThrowingStream<CatalogItem?, any Error> {
        database.observe { db in try CatalogItemRecord.live.filter(key: id).fetchOne(db)?.item() }
    }

    public func fetchItem(id: String) async throws -> CatalogItem? {
        try await database.writer.read { db in try CatalogItemRecord.live.filter(key: id).fetchOne(db)?.item() }
    }

    @discardableResult
    public func save(_ item: CatalogItem) async throws -> CatalogItem {
        let now = time.now()
        return try await database.writer.write { db in
            var stored = item
            stored.updatedAt = now
            if let existing = try CatalogItemRecord.fetchOne(db, key: item.id) {
                stored.createdAt = existing.createdAt
                try CatalogItemRecord(stored).update(db)
            } else {
                stored.createdAt = now
                try CatalogItemRecord(stored).insert(db)
            }
            return stored
        }
    }

    public func setArchived(_ archived: Bool, itemID: String) async throws {
        try await database.stamp(CatalogItemRecord.self, id: itemID, now: time.now(), column: "archived_at",
                                 set: archived)
    }

    public func delete(itemID: String) async throws {
        try await database.stamp(CatalogItemRecord.self, id: itemID, now: time.now(), column: "deleted_at", set: true)
    }

    public func countItems(businessID: String, usingRate rateID: String) async throws -> Int {
        try await database.writer.read { db in
            try CatalogItemRecord.live.filter(DBColumns.businessID == businessID && DBColumns.rateID == rateID)
                .fetchCount(db)
        }
    }
}

public struct GRDBNumberingSeriesRepository: NumberingSeriesRepository {
    let database: AppDatabase
    let time: TimeSource

    public init(database: AppDatabase, time: TimeSource) {
        self.database = database
        self.time = time
    }

    public func observeSeries(businessID: String) -> AsyncThrowingStream<[NumberingSeries], any Error> {
        database.observe { db in
            try NumberingSeriesRecord.live.filter(DBColumns.businessID == businessID)
                .order(Column("doc_type"), DBColumns.createdAt, DBColumns.id)
                .fetchAll(db).map { try $0.series() }
        }
    }

    @discardableResult
    public func save(_ series: NumberingSeries) async throws -> NumberingSeries {
        let now = time.now()
        return try await database.writer.write { db in
            var stored = series
            stored.updatedAt = now
            if let existing = try NumberingSeriesRecord.fetchOne(db, key: series.id) {
                stored.createdAt = existing.createdAt
                try NumberingSeriesRecord(stored).update(db)
            } else {
                stored.createdAt = now
                try NumberingSeriesRecord(stored).insert(db)
            }
            return stored
        }
    }
}

public struct GRDBAssetRepository: AssetRepository {
    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func fetchAsset(id: String) async throws -> Asset? {
        try await database.writer.read { db in try AssetRecord.live.filter(key: id).fetchOne(db)?.asset() }
    }

    public func observeAsset(id: String) -> AsyncThrowingStream<Asset?, any Error> {
        database.observe { db in try AssetRecord.live.filter(key: id).fetchOne(db)?.asset() }
    }
}

public struct GRDBDeviceStateRepository: DeviceStateRepository {
    let database: AppDatabase
    let time: TimeSource
    let ids: IDGenerator
    /// This device's id outside the database (`spec/setup.md` §2, ADR-0019): the Keychain in the app, in memory in
    /// tests. It must outlive the database exactly as long as the device does.
    let marker: any DeviceMarkerStore

    public init(database: AppDatabase, time: TimeSource, ids: IDGenerator, marker: any DeviceMarkerStore) {
        self.database = database
        self.time = time
        self.ids = ids
        self.marker = marker
    }

    /// This device's row, created on first use. A row copied from another device by an OS backup (the marker is
    /// missing or names another id) takes a new id and keeps everything else — only once the new marker is stored, so a
    /// marker that can't be written never changes the id. The marker is read and written inside the write
    /// transaction, so two callers at launch agree on one id.
    public func loadOrCreate(deviceName: String) async throws -> DeviceState {
        let now = time.now()
        let newID = ids.make()
        let marker = self.marker
        return try await database.writer.write { db in
            let existing = try DeviceStateRecord.current(db)
            switch DeviceIdentity.check(rowID: existing?.id, marker: marker.read()) {
            case .keep:
                return try existing!.deviceState()
            case .create:
                let state = DeviceState(id: newID, deviceName: deviceName, createdAt: now, updatedAt: now)
                try DeviceStateRecord(state).insert(db)
                marker.write(newID)
                return state
            case .replace:
                var state = try existing!.deviceState()
                // Marker first: if it can't be stored, keep the id rather than replacing it on every launch.
                guard marker.write(newID) else { return state }
                try db.execute(sql: "UPDATE device_state SET id = ?, updated_at = ? WHERE id = ?",
                               arguments: [newID, now, state.id])
                state.id = newID
                state.updatedAt = now
                return state
            }
        }
    }

    public func setActiveBusiness(id: String?) async throws {
        let now = time.now()
        try await database.writer.write { db in try DeviceStateRecord.setActiveBusiness(id, now: now, db: db) }
    }

    public func setSyncEnabled(_ enabled: Bool) async throws {
        let now = time.now()
        try await database.writer.write { db in
            try DeviceStateRecord.updatePreferences(now: now, db: db) { $0.syncEnabled = enabled }
        }
    }
}

// MARK: - Shared helpers

extension SnakeCaseRecord {
    /// Rows that are not tombstoned.
    static var live: QueryInterfaceRequest<Self> { filter(DBColumns.deletedAt == nil) }
}

extension DeviceStateRecord {
    /// This device's row: the earliest one if there are several (`spec/setup.md` §2).
    static func current(_ db: Database) throws -> DeviceStateRecord? {
        try order(DBColumns.createdAt, DBColumns.id).fetchOne(db)
    }

    static func setActiveBusiness(_ businessID: String?, now: Int64, db: Database) throws {
        try updatePreferences(now: now, db: db) { $0.activeBusinessId = businessID }
    }

    static func updatePreferences(now: Int64, db: Database, _ change: (inout DevicePreferences) -> Void) throws {
        guard var record = try current(db) else { throw RecordNotFound(table: databaseTableName, id: "this device") }
        var state = try record.deviceState()
        change(&state.preferences)
        state.updatedAt = now
        record = try DeviceStateRecord(state)
        try record.update(db)
    }
}

extension AppDatabase {
    /// Sets (or clears) a timestamp column such as `archived_at` or `deleted_at` on a live row and stamps
    /// `updated_at`. Throws when the row is missing or already tombstoned.
    func stamp<Record: SnakeCaseRecord>(_ type: Record.Type, id: String, now: Int64, column: String, set: Bool)
        async throws {
        let changed = try await writer.write { db in
            try Record.live.filter(key: id).updateAll(
                db, Column(column).set(to: set ? now : nil), Column("updated_at").set(to: now))
        }
        if changed == 0 { throw RecordNotFound(table: Record.databaseTableName, id: id) }
    }
}
