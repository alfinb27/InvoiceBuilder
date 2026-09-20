import CryptoKit
import Foundation
import GRDB
import InvoiceCore

/// Multi-table setup operations, each in one write transaction (all or nothing).
public struct GRDBBusinessSetupService: BusinessSetupService {
    let database: AppDatabase
    let time: TimeSource
    let ids: IDGenerator

    public init(database: AppDatabase, time: TimeSource, ids: IDGenerator) {
        self.database = database
        self.time = time
        self.ids = ids
    }

    public func createBusiness(_ business: Business, series: [NumberingSeries], logo: ImagePayload?,
                               signature: ImagePayload?, deviceID: String) async throws -> Business {
        let now = time.now()
        let ids = self.ids
        return try await database.writer.write { db in
            var stored = business
            stored.createdAt = now
            stored.updatedAt = now
            stored.logoAssetId = nil
            stored.signatureAssetId = nil
            try BusinessRecord(stored).insert(db) // assets reference the business, so it goes first

            stored.logoAssetId = try logo.map {
                try AssetStore.store($0, kind: .logo, businessID: stored.id, now: now, newID: ids.make, db: db).id
            }
            stored.signatureAssetId = try signature.map {
                try AssetStore.store($0, kind: .signature, businessID: stored.id, now: now, newID: ids.make, db: db).id
            }
            if stored.logoAssetId != nil || stored.signatureAssetId != nil {
                try BusinessRecord(stored).update(db)
            }
            for var entry in series {
                entry.createdAt = now
                entry.updatedAt = now
                try NumberingSeriesRecord(entry).insert(db)
            }
            try DeviceStateRecord.setActiveBusiness(stored.id, now: now, db: db)
            return stored
        }
    }

    public func setImage(_ image: ImagePayload?, kind: AssetKind, businessID: String) async throws -> Business {
        let now = time.now()
        let ids = self.ids
        return try await database.writer.write { db in
            guard let record = try BusinessRecord.live.filter(key: businessID).fetchOne(db) else {
                throw RecordNotFound(table: BusinessRecord.databaseTableName, id: businessID)
            }
            var business = try record.business()
            let previous = kind == .logo ? business.logoAssetId : business.signatureAssetId
            let newID = try image.map {
                try AssetStore.store($0, kind: kind, businessID: businessID, now: now, newID: ids.make, db: db).id
            }
            if kind == .logo { business.logoAssetId = newID } else { business.signatureAssetId = newID }
            business.updatedAt = now
            try BusinessRecord(business).update(db)
            if let previous, previous != newID {
                try AssetStore.releaseIfUnused(previous, now: now, db: db)
            }
            return business
        }
    }
}

/// Asset rows (`spec/setup.md` §9).
enum AssetStore {
    /// Stores the bytes, or returns the live asset of the same business and kind with the same SHA-256.
    static func store(_ image: ImagePayload, kind: AssetKind, businessID: String, now: Int64,
                      newID: () -> String, db: Database) throws -> Asset {
        let digest = sha256Hex(image.data)
        if let existing = try AssetRecord.live
            .filter(DBColumns.businessID == businessID && DBColumns.kind == kind.rawValue && DBColumns.sha256 == digest)
            .fetchOne(db) {
            return existing.asset()
        }
        let asset = Asset(id: newID(), createdAt: now, updatedAt: now, businessId: businessID, kind: kind,
                          mime: image.mime, sha256: digest, data: image.data)
        try AssetRecord(asset).insert(db)
        return asset
    }

    /// Tombstones the asset when no live business and no issued document's seller snapshot points at it any more
    /// (issued documents keep the images they were issued with).
    static func releaseIfUnused(_ assetID: String, now: Int64, db: Database) throws {
        let users = try BusinessRecord.live
            .filter(DBColumns.logoAssetID == assetID || DBColumns.signatureAssetID == assetID)
            .fetchCount(db)
        let documents = try DocumentRecord.live
            .filter(DBColumns.lifecycle != DocumentLifecycle.draft.rawValue)
            .filter(sql: """
                json_extract(seller_snapshot, '$.logoAssetId') = ?
                OR json_extract(seller_snapshot, '$.signatureAssetId') = ?
                """, arguments: [assetID, assetID])
            .fetchCount(db)
        guard users == 0, documents == 0 else { return }
        try AssetRecord.live.filter(key: assetID)
            .updateAll(db, DBColumns.deletedAt.set(to: now), Column("updated_at").set(to: now))
    }

    /// Lowercase hex SHA-256.
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
