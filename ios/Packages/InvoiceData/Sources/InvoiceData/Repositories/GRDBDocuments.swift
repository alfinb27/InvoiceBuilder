import Foundation
import GRDB
import InvoiceCore

/// Documents and their lines (`spec/documents.md` §5). Reads never return tombstoned rows.
public struct GRDBDocumentRepository: DocumentRepository {
    let database: AppDatabase
    let time: TimeSource

    public init(database: AppDatabase, time: TimeSource) {
        self.database = database
        self.time = time
    }

    public func observeDocuments(businessID: String) -> AsyncThrowingStream<[DocumentSummary], any Error> {
        database.observe { db in try Self.summaries(businessID: businessID, db: db) }
    }

    public func observeDocument(id: String) -> AsyncThrowingStream<Document?, any Error> {
        database.observe { db in try DocumentRecord.fetchDocument(id: id, db: db) }
    }

    public func fetchDocument(id: String) async throws -> Document? {
        try await database.writer.read { db in try DocumentRecord.fetchDocument(id: id, db: db) }
    }

    @discardableResult
    public func saveDraft(_ document: Document) async throws -> Document {
        let now = time.now()
        return try await database.writer.write { db in
            guard document.lifecycle == .draft else { throw DocumentServiceError.notADraft }
            var stored = document
            stored.updatedAt = now
            if let existing = try DocumentRecord.fetchOne(db, key: document.id) {
                guard existing.lifecycle == DocumentLifecycle.draft.rawValue else {
                    throw DocumentServiceError.notADraft
                }
                stored.createdAt = existing.createdAt
                // A draft deleted while its builder was open (§9) comes back when it is edited again, rather than
                // failing every save from then on.
                stored.deletedAt = nil
                try DocumentRecord(stored).update(db)
            } else {
                stored.createdAt = now
                try DocumentRecord(stored).insert(db)
            }
            try LineItemRecord.replaceLines(stored.lines, documentID: stored.id, now: now, db: db)
            return stored
        }
    }

    public func highestIssuedSequence(seriesID: String, periodKey: String) async throws -> Int? {
        try await database.writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT MAX(sequence) FROM document
                WHERE series_id = ? AND period_key = ? AND lifecycle <> 'draft' AND deleted_at IS NULL
                """, arguments: [seriesID, periodKey])
        }
    }

    public func markSent(documentID: String, at timestamp: Int64?) async throws {
        let now = time.now()
        let changed = try await database.writer.write { db in
            try DocumentRecord.live.filter(key: documentID)
                .filter(DBColumns.lifecycle != DocumentLifecycle.draft.rawValue)
                .updateAll(db, DBColumns.sentAt.set(to: timestamp), DBColumns.updatedAt.set(to: now))
        }
        if changed == 0 { throw DocumentServiceError.notFound }
    }

    /// The list rows: newest issue date first, then the most recently edited.
    static func summaries(businessID: String, db: Database) throws -> [DocumentSummary] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT d.id, d.doc_type, d.number, d.lifecycle, d.issue_date, d.due_date, d.valid_until, d.sent_at,
                   d.quote_outcome, d.client_id, d.buyer_snapshot, d.currency, d.total_minor, d.updated_at,
                   (SELECT COUNT(*) FROM line_item l WHERE l.document_id = d.id AND l.deleted_at IS NULL) AS line_count
            FROM document d
            WHERE d.business_id = ? AND d.deleted_at IS NULL
            ORDER BY d.issue_date DESC, d.updated_at DESC, d.id
            """, arguments: [businessID])
        return try rows.map { row in
            let buyer = try JSONColumn.decode(BuyerSnapshot.self, from: row["buyer_snapshot"])
            let quoteOutcome: String? = row["quote_outcome"]
            let dueDate: String? = row["due_date"]
            let validUntil: String? = row["valid_until"]
            return DocumentSummary(
                id: row["id"], docType: DocumentType(rawValue: row["doc_type"]), number: row["number"],
                lifecycle: DocumentLifecycle(rawValue: row["lifecycle"]),
                issueDate: try DocumentRecord.date(row["issue_date"]),
                dueDate: try dueDate.map(DocumentRecord.date), validUntil: try validUntil.map(DocumentRecord.date),
                sentAt: row["sent_at"], quoteOutcome: quoteOutcome.map(QuoteOutcome.init(rawValue:)),
                clientId: row["client_id"], buyerName: buyer?.name, currency: CurrencyCode(rawValue: row["currency"]),
                totalMinor: row["total_minor"], lineCount: row["line_count"], updatedAt: row["updated_at"]
            )
        }
    }
}

/// `IssueDocument`, duplicate, convert and delete (`spec/documents.md` §6–9), each in one write transaction.
public struct GRDBDocumentService: DocumentService {
    let database: AppDatabase
    let time: TimeSource
    let ids: IDGenerator
    let configs: TaxConfigStore
    let currencies: CurrencyCatalog

    public init(database: AppDatabase, time: TimeSource, ids: IDGenerator, configs: TaxConfigStore,
                currencies: CurrencyCatalog) {
        self.database = database
        self.time = time
        self.ids = ids
        self.configs = configs
        self.currencies = currencies
    }

    public func issue(documentID: String, deviceID: String) async throws -> Document {
        let now = time.now()
        let ids = self.ids, configs = self.configs, currencies = self.currencies
        return try await database.writer.write { db in
            let context = try Context.load(documentID: documentID, configs: configs, currencies: currencies, db: db)
            let document = context.document
            guard document.isDraft else { throw DocumentServiceError.notADraft }
            let rules = context.rules
            let config = rules.config(for: document)
            let seller = rules.sellerSnapshot(config: config)
            let buyer = rules.buyerSnapshot(for: document, client: context.client)
            let result = rules.compute(document, seller: seller, buyer: buyer)
            var problems = rules.issueProblems(document, result: result)

            let series = try NumberingSeriesRecord.live.filter(DBColumns.businessID == document.businessId)
                .fetchAll(db).map { try $0.series() }
            var allocation: NumberAllocator.Allocation?
            if let owned = NumberAllocator.series(for: document.docType, deviceID: deviceID, among: series) {
                switch NumberAllocator.allocate(from: owned, issueDate: document.issueDate, config: config) {
                case .success(let value): allocation = value
                case .failure(let error): problems.append(.numbering(error))
                }
            } else {
                problems.append(.noSeries)
            }
            guard problems.isEmpty, let allocation, case .success(let computed) = result else {
                throw DocumentServiceError.blocked(problems)
            }

            var issued = rules.issued(document, seller: seller, buyer: buyer, computed: computed,
                                      allocation: allocation)
            issued.updatedAt = now
            try DocumentRecord(issued).update(db)
            try LineItemRecord.replaceLines(issued.lines, documentID: issued.id, now: now, db: db)
            var advanced = allocation.series
            advanced.updatedAt = now
            try NumberingSeriesRecord(advanced).update(db)
            for taxLine in computed.taxLines {
                try TaxLineRecord(id: ids.make(), documentID: issued.id, taxLine: taxLine, now: now).insert(db)
            }
            if issued.docType == .invoice { try FreeTierCounter.increment(now: now, db: db) }
            return issued
        }
    }

    public func duplicate(documentID: String) async throws -> Document {
        let now = time.now(), today = time.today()
        let ids = self.ids, configs = self.configs, currencies = self.currencies
        return try await database.writer.write { db in
            let context = try Context.load(documentID: documentID, configs: configs, currencies: currencies, db: db)
            let copy = context.rules.duplicate(context.document, id: ids.make(), today: today, now: now,
                                               newLineID: ids.make)
            return try Self.insertDraft(context.rules.preparedDraft(copy, client: context.client), now: now, db: db)
        }
    }

    public func convertQuote(documentID: String) async throws -> Document {
        let now = time.now(), today = time.today()
        let ids = self.ids, configs = self.configs, currencies = self.currencies
        return try await database.writer.write { db in
            let context = try Context.load(documentID: documentID, configs: configs, currencies: currencies, db: db)
            guard context.rules.canConvert(context.document) else { throw DocumentServiceError.notConvertible }
            let invoice = context.rules.convertedInvoice(from: context.document, id: ids.make(), today: today,
                                                         now: now, newLineID: ids.make)
            try DocumentRecord.live.filter(key: documentID).updateAll(
                db, DBColumns.quoteOutcome.set(to: QuoteOutcome.converted.rawValue), DBColumns.updatedAt.set(to: now))
            return try Self.insertDraft(context.rules.preparedDraft(invoice, client: context.client), now: now, db: db)
        }
    }

    public func deleteDraft(documentID: String) async throws {
        let now = time.now()
        try await database.writer.write { db in
            guard let record = try DocumentRecord.live.filter(key: documentID).fetchOne(db) else {
                throw DocumentServiceError.notFound
            }
            guard record.lifecycle == DocumentLifecycle.draft.rawValue else { throw DocumentServiceError.notADraft }
            try DocumentRecord.live.filter(key: documentID)
                .updateAll(db, DBColumns.deletedAt.set(to: now), DBColumns.updatedAt.set(to: now))
            // A converted quote whose invoice draft is gone can be converted again.
            if let quoteID = record.convertedFromId {
                let others = try DocumentRecord.live.filter(DBColumns.convertedFromID == quoteID).fetchCount(db)
                if others == 0 {
                    try DocumentRecord.live
                        .filter(key: quoteID)
                        .filter(DBColumns.quoteOutcome == QuoteOutcome.converted.rawValue)
                        .updateAll(db, DBColumns.quoteOutcome.set(to: nil), DBColumns.updatedAt.set(to: now))
                }
            }
        }
    }

    private static func insertDraft(_ draft: Document, now: Int64, db: Database) throws -> Document {
        var stored = draft
        stored.createdAt = now
        stored.updatedAt = now
        try DocumentRecord(stored).insert(db)
        try LineItemRecord.replaceLines(stored.lines, documentID: stored.id, now: now, db: db)
        return stored
    }

    /// A live document with the live business and client it refers to.
    private struct Context {
        let document: Document
        let client: Client?
        let rules: DocumentRules

        static func load(documentID: String, configs: TaxConfigStore, currencies: CurrencyCatalog,
                         db: Database) throws -> Context {
            guard let document = try DocumentRecord.fetchDocument(id: documentID, db: db) else {
                throw DocumentServiceError.notFound
            }
            guard let business = try BusinessRecord.live.filter(key: document.businessId).fetchOne(db)?.business()
            else {
                throw RecordNotFound(table: BusinessRecord.databaseTableName, id: document.businessId)
            }
            let client = try document.clientId.flatMap { id in
                try ClientRecord.live.filter(key: id).fetchOne(db)?.client()
            }
            return Context(document: document, client: client,
                           rules: try DocumentRules(configs: configs, business: business, currencies: currencies))
        }
    }
}

/// The free-tier counter (`spec/billing.md`): `app_state.issued_invoice_count` and this device's
/// `free_counter_mirror`, both local and never decreased.
enum FreeTierCounter {
    static let key = "issued_invoice_count"

    static func increment(now: Int64, db: Database) throws {
        try db.execute(sql: """
            INSERT INTO app_state (key, value) VALUES (?, '1')
            ON CONFLICT(key) DO UPDATE SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT)
            """, arguments: [key])
        if var device = try DeviceStateRecord.current(db) {
            device.freeCounterMirror += 1
            device.updatedAt = now
            try device.update(db)
        }
    }

    static func count(_ db: Database) throws -> Int {
        try String.fetchOne(db, sql: "SELECT value FROM app_state WHERE key = ?", arguments: [key])
            .flatMap { Int($0) } ?? 0
    }
}
