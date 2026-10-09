import Foundation
import GRDB
import InvoiceCore

/// The free-tier counts the database keeps (`spec/billing.md`, Free tier).
public struct GRDBFreeTierRepository: FreeTierRepository {
    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func fetchCounts() async throws -> FreeTierCounts {
        try await database.writer.read { db in
            FreeTierCounts(
                local: try FreeTierCounter.count(db),
                deviceMirror: Int(try DeviceStateRecord.current(db)?.freeCounterMirror ?? 0),
                issuedInDatabase: try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM document WHERE doc_type = 'invoice' AND lifecycle <> 'draft'
                    """) ?? 0
            )
        }
    }
}
