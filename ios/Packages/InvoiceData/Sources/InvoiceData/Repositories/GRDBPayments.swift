import Foundation
import GRDB
import InvoiceCore

/// Payments recorded against invoices (`spec/documents.md` §10). Reads never return tombstoned rows; writing a new
/// payment always goes through `GRDBPaymentService.recordPayment`, never through this repository directly, so an
/// unpayable document can never receive one.
public struct GRDBPaymentRepository: PaymentRepository {
    let database: AppDatabase
    let time: TimeSource

    public init(database: AppDatabase, time: TimeSource) {
        self.database = database
        self.time = time
    }

    public func observePayments(documentID: String) -> AsyncThrowingStream<[Payment], any Error> {
        database.observe { db in try Self.payments(documentID: documentID, db: db) }
    }

    public func fetchPayments(documentID: String) async throws -> [Payment] {
        try await database.writer.read { db in try Self.payments(documentID: documentID, db: db) }
    }

    public func softDelete(paymentID: String) async throws {
        try await database.stamp(PaymentRecord.self, id: paymentID, now: time.now(), column: "deleted_at", set: true)
    }

    /// Live payments of a document, most recent date first, then most recently recorded.
    static func payments(documentID: String, db: Database) throws -> [Payment] {
        try PaymentRecord.live.filter(DBColumns.documentID == documentID)
            .order(Column("date").desc, DBColumns.createdAt.desc)
            .fetchAll(db).map { try $0.payment() }
    }
}

/// `recordPayment` (`spec/documents.md` §10): checks the document is a live, issued invoice, then inserts one
/// payment row. One write transaction.
public struct GRDBPaymentService: PaymentService {
    let database: AppDatabase
    let time: TimeSource
    let ids: IDGenerator

    public init(database: AppDatabase, time: TimeSource, ids: IDGenerator) {
        self.database = database
        self.time = time
        self.ids = ids
    }

    @discardableResult
    public func recordPayment(documentID: String, amountMinor: Int64, date: LocalDate, method: PaymentMethod,
                              reference: String?, note: String?) async throws -> Payment {
        let now = time.now()
        let id = ids.make()
        return try await database.writer.write { db in
            guard let document = try DocumentRecord.live.filter(key: documentID).fetchOne(db) else {
                throw PaymentServiceError.documentNotFound
            }
            guard document.docType == DocumentType.invoice.rawValue,
                  document.lifecycle == DocumentLifecycle.issued.rawValue else {
                throw PaymentServiceError.notPayable
            }
            let payment = Payment(id: id, createdAt: now, updatedAt: now, businessId: document.businessId,
                                  documentId: documentID, amountMinor: amountMinor, date: date, method: method,
                                  reference: reference?.trimmedOrNil, note: note?.trimmedOrNil)
            try PaymentRecord(payment).insert(db)
            return payment
        }
    }
}
