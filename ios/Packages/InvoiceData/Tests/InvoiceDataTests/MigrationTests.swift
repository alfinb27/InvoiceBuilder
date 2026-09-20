import Foundation
import GRDB
import InvoiceCore
import Testing
@testable import InvoiceData

/// The repository's `spec/` folder, found from this file's location.
enum Spec {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        // InvoiceDataTests → Tests → InvoiceData → Packages → ios → repository root
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url.appending(path: "spec")
    }()
}

@Suite("Migrations")
struct MigrationTests {
    /// GRDB's migrations produce exactly the canonical schema: same tables, columns (order, types, NOT NULL,
    /// defaults, primary keys), foreign keys and indexes as `spec/schema/db/schema.sql` (ADR-0003).
    @Test func migratedSchemaMatchesSchemaSQL() throws {
        let migrated = try AppDatabase.inMemory().writer
        let canonical = try DatabaseQueue()
        let schemaSQL = try String(contentsOf: Spec.root.appending(path: "schema/db/schema.sql"), encoding: .utf8)
        try canonical.write { db in try db.execute(sql: schemaSQL) }

        let expected = try canonical.read(Self.describeSchema)
        let actual = try migrated.read(Self.describeSchema)
        #expect(expected.keys.sorted() == actual.keys.sorted())
        #expect(expected.count == 11)
        for table in expected.keys.sorted() {
            #expect(actual[table] == expected[table], "table \(table) differs from schema.sql")
        }
    }

    @Test func bundledMigrationsMatchTheSpec() throws {
        let files = try AppDatabase.migrationFiles()
        let specFolder = Spec.root.appending(path: "schema/db/migrations")
        let specFiles = try FileManager.default.contentsOfDirectory(atPath: specFolder.path)
            .filter { $0.hasSuffix(".sql") }.sorted()
        #expect(files.map(\.lastPathComponent) == specFiles)
        for file in files {
            let original = try Data(contentsOf: specFolder.appending(path: file.lastPathComponent))
            #expect(try Data(contentsOf: file) == original, "\(file.lastPathComponent) is stale; run `make sync-spec`")
        }
        #expect(try AppDatabase.schemaVersion() == specFiles.count)
    }

    @Test func migratingTwiceIsANoOp() throws {
        let database = try AppDatabase.inMemory()
        let migrator = try AppDatabase.migrator()
        try migrator.migrate(database.writer)
        let applied = try database.writer.read { db in try migrator.appliedIdentifiers(db) }
        #expect(applied == ["0001_init", "0002_document_sequence"])
    }

    @Test func onDiskDatabaseUsesWALAndForeignKeys() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "InvoiceDataTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try AppDatabase.openOnDisk(at: folder.appending(path: "nested/invoices.sqlite"))
        let (journal, foreignKeys) = try database.writer.read { db in
            (try String.fetchOne(db, sql: "PRAGMA journal_mode"), try Bool.fetchOne(db, sql: "PRAGMA foreign_keys"))
        }
        #expect(journal == "wal")
        #expect(foreignKeys == true)
    }

    /// Table name → a canonical description of its columns, foreign keys and indexes.
    static func describeSchema(_ db: Database) throws -> [String: [String]] {
        let tables = try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
            """)
        var result: [String: [String]] = [:]
        for table in tables {
            let columns = try Row.fetchAll(db, sql: "SELECT * FROM pragma_table_xinfo(?)", arguments: [table])
                .map { "column \($0["cid"] as Int) \($0["name"] as String) \($0["type"] as String) notnull=\($0["notnull"] as Int) default=\(($0["dflt_value"] as String?) ?? "-") pk=\($0["pk"] as Int)" }
            let foreignKeys = try Row.fetchAll(db, sql: "SELECT * FROM pragma_foreign_key_list(?)", arguments: [table])
                .map { "fk \($0["from"] as String) -> \($0["table"] as String).\(($0["to"] as String?) ?? "") on delete \($0["on_delete"] as String)" }
                .sorted()
            let indexes = try Row.fetchAll(db, sql: "SELECT * FROM pragma_index_list(?)", arguments: [table])
                .map { row -> String in
                    let name: String = row["name"]
                    let columns = try String.fetchAll(db, sql: "SELECT name FROM pragma_index_info(?)", arguments: [name])
                    return "index \(name) unique=\(row["unique"] as Int) origin=\(row["origin"] as String) (\(columns.joined(separator: ",")))"
                }
                .sorted()
            result[table] = columns + foreignKeys + indexes
        }
        return result
    }
}
