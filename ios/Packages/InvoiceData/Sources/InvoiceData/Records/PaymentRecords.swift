import Foundation
import GRDB
import InvoiceCore

struct PaymentRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "payment"

    var id: String
    var businessId: String
    var documentId: String
    var amountMinor: Int64
    var date: String
    var method: String
    var reference: String?
    var note: String?
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    init(_ payment: Payment) {
        id = payment.id
        businessId = payment.businessId
        documentId = payment.documentId
        amountMinor = payment.amountMinor
        date = payment.date.iso
        method = payment.method.rawValue
        reference = payment.reference
        note = payment.note
        createdAt = payment.createdAt
        updatedAt = payment.updatedAt
        deletedAt = payment.deletedAt
    }

    func payment() throws -> Payment {
        Payment(id: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, businessId: businessId,
                documentId: documentId, amountMinor: amountMinor, date: try DocumentRecord.date(date),
                method: PaymentMethod(rawValue: method), reference: reference, note: note)
    }
}
