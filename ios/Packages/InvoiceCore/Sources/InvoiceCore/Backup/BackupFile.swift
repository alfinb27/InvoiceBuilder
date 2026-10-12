import Foundation

/// A portable `.invoicebackup` file (`spec/schema/backup.schema.json`, `spec/backup.md`).
public struct BackupFile: Codable, Hashable, Sendable {
    public static let format = "invoicebuilder-backup"
    /// The newest `formatVersion` this app reads and the one it writes.
    public static let formatVersion = 1
    public static let fileExtension = "invoicebackup"

    public var format: String
    public var formatVersion: Int
    /// Export time, epoch ms UTC.
    public var createdAt: Int64
    public var app: AppInfo
    /// The highest migration applied when the file was written.
    public var dbSchemaVersion: Int
    public var counts: BackupCounts
    public var data: BackupData

    public init(createdAt: Int64, app: AppInfo, dbSchemaVersion: Int, data: BackupData) {
        format = Self.format
        formatVersion = Self.formatVersion
        self.createdAt = createdAt
        self.app = app
        self.dbSchemaVersion = dbSchemaVersion
        counts = data.counts
        self.data = data
    }

    public struct AppInfo: Codable, Hashable, Sendable {
        /// `ios` or `android`.
        public var platform: String
        public var version: String

        public init(platform: String, version: String) {
            self.platform = platform
            self.version = version
        }
    }

    /// `InvoiceBackup-YYYY-MM-DD.invoicebackup` (§1).
    public static func fileName(on date: LocalDate) -> String {
        "InvoiceBackup-\(date.iso).\(fileExtension)"
    }
}

/// Every row of the synced tables, tombstones included (`spec/backup.md` §1).
public struct BackupData: Codable, Hashable, Sendable {
    public var businesses: [Business]
    public var clients: [Client]
    public var catalogItems: [CatalogItem]
    public var numberingSeries: [NumberingSeries]
    public var documents: [Document]
    public var payments: [Payment]
    public var assets: [Asset]

    public init(businesses: [Business] = [], clients: [Client] = [], catalogItems: [CatalogItem] = [],
                numberingSeries: [NumberingSeries] = [], documents: [Document] = [], payments: [Payment] = [],
                assets: [Asset] = []) {
        self.businesses = businesses
        self.clients = clients
        self.catalogItems = catalogItems
        self.numberingSeries = numberingSeries
        self.documents = documents
        self.payments = payments
        self.assets = assets
    }

    /// Array lengths, tombstones included.
    public var counts: BackupCounts {
        BackupCounts(businesses: businesses.count, clients: clients.count, catalogItems: catalogItems.count,
                     numberingSeries: numberingSeries.count, documents: documents.count, payments: payments.count,
                     assets: assets.count)
    }

    /// Rows whose `deletedAt` is nil: what the restore preview shows.
    public var liveCounts: BackupCounts {
        BackupCounts(
            businesses: businesses.count { $0.deletedAt == nil }, clients: clients.count { $0.deletedAt == nil },
            catalogItems: catalogItems.count { $0.deletedAt == nil },
            numberingSeries: numberingSeries.count { $0.deletedAt == nil },
            documents: documents.count { $0.deletedAt == nil }, payments: payments.count { $0.deletedAt == nil },
            assets: assets.count { $0.deletedAt == nil })
    }

    /// Each collection by `createdAt`, then `id` (§1), so the same data always gives the same file.
    public func sorted() -> BackupData {
        func order<T>(_ rows: [T], _ created: (T) -> Int64, _ id: (T) -> String) -> [T] {
            rows.sorted { created($0) != created($1) ? created($0) < created($1) : id($0) < id($1) }
        }
        return BackupData(
            businesses: order(businesses, \.createdAt, \.id), clients: order(clients, \.createdAt, \.id),
            catalogItems: order(catalogItems, \.createdAt, \.id),
            numberingSeries: order(numberingSeries, \.createdAt, \.id),
            documents: order(documents, \.createdAt, \.id).map { document in
                var document = document
                document.lines.sort { $0.position != $1.position ? $0.position < $1.position : $0.id < $1.id }
                return document
            },
            payments: order(payments, \.createdAt, \.id), assets: order(assets, \.createdAt, \.id))
    }
}

public struct BackupCounts: Codable, Hashable, Sendable {
    public var businesses: Int
    public var clients: Int
    public var catalogItems: Int
    public var numberingSeries: Int
    public var documents: Int
    public var payments: Int
    public var assets: Int

    public init(businesses: Int, clients: Int, catalogItems: Int, numberingSeries: Int, documents: Int,
                payments: Int, assets: Int) {
        self.businesses = businesses
        self.clients = clients
        self.catalogItems = catalogItems
        self.numberingSeries = numberingSeries
        self.documents = documents
        self.payments = payments
        self.assets = assets
    }
}

/// A file that passed `BackupCodec.validate`: what the user confirms before restoring (§4 step 2).
public struct BackupPreview: Hashable, Sendable {
    public var file: BackupFile
    /// Live rows per collection.
    public var live: BackupCounts

    public init(file: BackupFile) {
        self.file = file
        live = file.data.liveCounts
    }
}

/// Why a file cannot be restored (`spec/backup.md` §3). `code` is the spec's error code.
public struct BackupError: Error, Hashable, Sendable, CustomStringConvertible {
    public enum Code: String, Sendable, CaseIterable {
        case notJSON = "not_json"
        case notABackup = "not_a_backup"
        case newerFormat = "newer_format"
        case newerSchema = "newer_schema"
        case invalidRecord = "invalid_record"
        case countMismatch = "count_mismatch"
        case duplicateID = "duplicate_id"
        case assetHashMismatch = "asset_hash_mismatch"
        case danglingReference = "dangling_reference"
    }

    public var code: Code
    /// Where it went wrong (`documents[3]`, an id, a decoding path), for logs and support.
    public var detail: String?

    public init(_ code: Code, _ detail: String? = nil) {
        self.code = code
        self.detail = detail
    }

    public var description: String { detail.map { "\(code.rawValue): \($0)" } ?? code.rawValue }
}

/// What Settings shows about backups (`spec/backup.md` §5).
public struct BackupStatus: Hashable, Sendable {
    /// `app_state.last_backup_at`, epoch ms UTC.
    public var lastBackupAt: Int64?
    /// At least one live document is issued or void.
    public var hasIssuedDocuments: Bool

    public static let dueAfterDays = 30

    public init(lastBackupAt: Int64?, hasIssuedDocuments: Bool) {
        self.lastBackupAt = lastBackupAt
        self.hasIssuedDocuments = hasIssuedDocuments
    }

    /// Whole calendar days since the last backup, in `timeZone`; nil when there has been none.
    public func daysSinceLastBackup(today: LocalDate, timeZone: TimeZone = .current) -> Int? {
        guard let lastBackupAt else { return nil }
        let date = LocalDate.today(in: timeZone, at: Date(timeIntervalSince1970: Double(lastBackupAt) / 1000))
        return max(0, today.daysSinceEpoch - date.daysSinceEpoch)
    }

    /// §5: something has been issued and the last backup is missing or 30 or more days old.
    public func isDue(today: LocalDate, timeZone: TimeZone = .current) -> Bool {
        guard hasIssuedDocuments else { return false }
        guard let days = daysSinceLastBackup(today: today, timeZone: timeZone) else { return true }
        return days >= Self.dueAfterDays
    }
}
