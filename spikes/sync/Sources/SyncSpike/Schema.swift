import Foundation
import GRDB

/// Applies the canonical v0 schema (copied from spec/schema/db/migrations) with GRDB's migrator.
public func makeDatabase(at path: String? = nil) throws -> DatabaseQueue {
    let db = try path.map { try DatabaseQueue(path: $0) } ?? DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("0001_init") { db in
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("spec/schema/db/migrations/0001_init.sql")
        try db.execute(sql: String(contentsOf: url, encoding: .utf8))
    }
    try migrator.migrate(db)
    return db
}
