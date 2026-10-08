import Foundation
import GRDB
import InvoiceCore

/// Numbering on several devices (`spec/sync.md` §3–4).
public struct GRDBNumberingService: NumberingService {
    let database: AppDatabase
    let time: TimeSource
    let ids: IDGenerator
    let configs: TaxConfigStore

    public init(database: AppDatabase, time: TimeSource, ids: IDGenerator, configs: TaxConfigStore) {
        self.database = database
        self.time = time
        self.ids = ids
        self.configs = configs
    }

    public func createDeviceSeries(businessID: String, docType: DocumentType, deviceID: String) async throws
        -> NumberingSeries {
        let now = time.now(), today = time.today(), id = ids.make(), configs = self.configs
        return try await database.writer.write { db in
            guard let business = try BusinessRecord.live.filter(key: businessID).fetchOne(db)?.business() else {
                throw NumberingServiceError.businessNotFound
            }
            guard let config = configs.latest(family: business.taxConfig, on: today)
                ?? configs.latest(family: "GENERIC", on: today) else {
                throw NumberingServiceError.businessNotFound
            }
            let existing = try NumberingSeriesRecord.live.filter(DBColumns.businessID == businessID).fetchAll(db)
                .map { try $0.series() }
            switch SeriesOwnership.deviceSeries(id: id, businessID: businessID, docType: docType, config: config,
                                                existing: existing, deviceID: deviceID, now: now) {
            case .success(let series):
                try NumberingSeriesRecord(series).insert(db)
                return series
            case .failure:
                throw NumberingServiceError.noDeviceLetter
            }
        }
    }

    public func takeOver(seriesID: String, deviceID: String) async throws -> NumberingSeries {
        let now = time.now()
        return try await database.writer.write { db in
            guard let series = try NumberingSeriesRecord.live.filter(key: seriesID).fetchOne(db)?.series() else {
                throw NumberingServiceError.seriesNotFound
            }
            let rows = try Row.fetchAll(db, sql: """
                SELECT period_key, MAX(sequence) AS highest FROM document
                WHERE series_id = ? AND lifecycle <> 'draft' AND deleted_at IS NULL
                      AND period_key IS NOT NULL AND sequence IS NOT NULL
                GROUP BY period_key
                """, arguments: [seriesID])
            let highest = Dictionary(uniqueKeysWithValues: rows.map { ($0["period_key"] as String, $0["highest"] as Int) })
            let taken = SeriesOwnership.takeOver(series, deviceID: deviceID, highest: highest, now: now)
            try NumberingSeriesRecord(taken).update(db)
            return taken
        }
    }

    public func observeDuplicateNumbers(businessID: String)
        -> AsyncThrowingStream<[DuplicateNumbers.Group], any Error> {
        database.observe { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, doc_type, lifecycle, number FROM document
                WHERE business_id = ? AND deleted_at IS NULL AND lifecycle <> 'draft' AND number IS NOT NULL
                """, arguments: [businessID])
            return DuplicateNumbers.find(rows.map {
                DuplicateNumbers.Row(id: $0["id"], docType: DocumentType(rawValue: $0["doc_type"]),
                                     lifecycle: DocumentLifecycle(rawValue: $0["lifecycle"]), number: $0["number"])
            })
        }
    }
}
