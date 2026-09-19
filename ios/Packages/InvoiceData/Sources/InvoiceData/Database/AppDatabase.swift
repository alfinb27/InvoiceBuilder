import Foundation
import GRDB
import InvoiceCore

/// The app's SQLite database. Opening it applies the spec's migrations in order, so the schema always matches
/// `spec/schema/db/schema.sql` (ADR-0003).
public final class AppDatabase: Sendable {
    /// A `DatabasePool` (WAL) on disk, a `DatabaseQueue` in memory.
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator().migrate(writer)
    }

    /// The on-disk database. `configure` lets other packages adjust the configuration (e.g. the sync layer).
    public static func openOnDisk(at url: URL, configure: (inout Configuration) -> Void = { _ in }) throws
        -> AppDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        configure(&configuration)
        return try AppDatabase(DatabasePool(path: url.path, configuration: configuration))
    }

    /// An empty in-memory database for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    /// `Application Support/InvoiceBuilder/invoices.sqlite`.
    public static func defaultURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "InvoiceBuilder/invoices.sqlite")
    }

    // MARK: Migrations

    /// The bundled copy of `spec/schema/db/migrations` (written by `make sync-spec`), sorted by number.
    public static func migrationFiles() throws -> [URL] {
        guard let folder = Bundle.module.url(forResource: "spec", withExtension: nil)?
            .appending(path: "schema/db/migrations") else {
            throw SpecLoadingError(path: "schema/db/migrations", reason: "not bundled; run `make sync-spec`")
        }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sql" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// One GRDB migration per spec file, identified by its name (`0001_init`).
    public static func migrator() throws -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        for file in try migrationFiles() {
            let sql = try String(contentsOf: file, encoding: .utf8)
            migrator.registerMigration(file.deletingPathExtension().lastPathComponent) { db in
                try db.execute(sql: sql)
            }
        }
        return migrator
    }

    /// The highest migration number (backups record it as `dbSchemaVersion`).
    public static func schemaVersion() throws -> Int {
        try migrationFiles().last.flatMap { Int($0.lastPathComponent.prefix(4)) } ?? 0
    }
}

// MARK: - Observation

private let observationQueue = DispatchQueue(label: "InvoiceData.observation")

extension AppDatabase {
    /// A stream of `fetch` results: the current value, then a new one after every commit that changes it.
    func observe<Value: Sendable & Equatable>(
        _ fetch: @escaping @Sendable (Database) throws -> Value
    ) -> AsyncThrowingStream<Value, any Error> {
        let observation = ValueObservation.tracking(fetch).removeDuplicates()
        let writer = self.writer
        return AsyncThrowingStream { continuation in
            let cancellable = observation.start(
                in: writer,
                scheduling: .async(onQueue: observationQueue),
                onError: { continuation.finish(throwing: $0) },
                onChange: { continuation.yield($0) }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}

/// A row that the caller expected to exist is missing (or tombstoned).
public struct RecordNotFound: Error, CustomStringConvertible, Sendable {
    public let table: String
    public let id: String

    public var description: String { "\(table) \(id) not found" }
}
