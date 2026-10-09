import Foundation
import GRDB
import InvoiceCore

struct DocumentRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "document"

    var id: String
    var businessId: String
    var docType: String
    var number: String?
    var seriesId: String?
    var periodKey: String?
    var lifecycle: String
    var issueDate: String
    var supplyDate: String?
    var dueDate: String?
    var reminderDaysAfterDueOverride: Int?
    var validUntil: String?
    var sentAt: Int64?
    var voidedAt: Int64?
    var voidReason: String?
    var quoteOutcome: String?
    var convertedFromId: String?
    var currency: String
    var exchangeRate: String?
    var supplyType: String
    var placeOfSupply: String?
    var reverseCharge: Bool
    var pricesIncludeTax: Bool
    var roundOff: Bool?
    var clientId: String?
    var sellerSnapshot: String?
    var buyerSnapshot: String?
    var discount: String?
    var shippingMinor: Int64
    var notes: String?
    var terms: String?
    var templateId: String
    var taxConfigRef: String
    var revision: Int
    var subtotalMinor: Int64
    var discountMinor: Int64
    var taxableMinor: Int64
    var taxMinor: Int64
    var taxNotChargedMinor: Int64
    var roundOffMinor: Int64
    var totalMinor: Int64
    var computed: String?
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?
    var sequence: Int?

    init(_ document: Document) throws {
        id = document.id
        businessId = document.businessId
        docType = document.docType.rawValue
        number = document.number
        seriesId = document.seriesId
        periodKey = document.periodKey
        lifecycle = document.lifecycle.rawValue
        issueDate = document.issueDate.iso
        supplyDate = document.supplyDate?.iso
        dueDate = document.dueDate?.iso
        reminderDaysAfterDueOverride = document.reminderDaysAfterDueOverride
        validUntil = document.validUntil?.iso
        sentAt = document.sentAt
        voidedAt = document.voidedAt
        voidReason = document.voidReason
        quoteOutcome = document.quoteOutcome?.rawValue
        convertedFromId = document.convertedFromId
        currency = document.currency.rawValue
        exchangeRate = document.exchangeRate
        supplyType = document.supplyType
        placeOfSupply = document.placeOfSupply
        reverseCharge = document.reverseCharge
        pricesIncludeTax = document.pricesIncludeTax
        roundOff = document.roundOff
        clientId = document.clientId
        sellerSnapshot = try JSONColumn.encode(document.sellerSnapshot)
        buyerSnapshot = try JSONColumn.encode(document.buyerSnapshot)
        discount = try JSONColumn.encode(document.discount)
        shippingMinor = document.shippingMinor
        notes = document.notes
        terms = document.terms
        templateId = document.templateId.rawValue
        taxConfigRef = document.taxConfigRef
        revision = document.revision
        subtotalMinor = document.totals.subtotalMinor
        discountMinor = document.totals.discountMinor
        taxableMinor = document.totals.taxableMinor
        taxMinor = document.totals.taxMinor
        taxNotChargedMinor = document.totals.taxNotChargedMinor
        roundOffMinor = document.totals.roundOffMinor
        totalMinor = document.totals.totalMinor
        computed = try JSONColumn.encode(document.computed)
        createdAt = document.createdAt
        updatedAt = document.updatedAt
        deletedAt = document.deletedAt
        sequence = document.sequence
    }

    func document(lines: [LineItem]) throws -> Document {
        Document(
            id: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, businessId: businessId,
            docType: DocumentType(rawValue: docType), number: number, seriesId: seriesId, periodKey: periodKey,
            sequence: sequence, lifecycle: DocumentLifecycle(rawValue: lifecycle), issueDate: try Self.date(issueDate),
            supplyDate: try supplyDate.map(Self.date), dueDate: try dueDate.map(Self.date),
            reminderDaysAfterDueOverride: reminderDaysAfterDueOverride, validUntil: try validUntil.map(Self.date),
            sentAt: sentAt, voidedAt: voidedAt, voidReason: voidReason,
            quoteOutcome: quoteOutcome.map(QuoteOutcome.init(rawValue:)), convertedFromId: convertedFromId,
            currency: CurrencyCode(rawValue: currency), exchangeRate: exchangeRate, supplyType: supplyType,
            placeOfSupply: placeOfSupply, reverseCharge: reverseCharge, pricesIncludeTax: pricesIncludeTax,
            roundOff: roundOff, clientId: clientId,
            sellerSnapshot: try JSONColumn.decode(SellerSnapshot.self, from: sellerSnapshot),
            buyerSnapshot: try JSONColumn.decode(BuyerSnapshot.self, from: buyerSnapshot),
            discount: try JSONColumn.decode(Discount.self, from: discount), shippingMinor: shippingMinor,
            notes: notes, terms: terms, templateId: TemplateID(rawValue: templateId), taxConfigRef: taxConfigRef,
            revision: revision, lines: lines,
            totals: DocumentTotals(subtotalMinor: subtotalMinor, discountMinor: discountMinor,
                                   shippingMinor: shippingMinor, taxableMinor: taxableMinor, taxMinor: taxMinor,
                                   taxNotChargedMinor: taxNotChargedMinor, roundOffMinor: roundOffMinor,
                                   totalMinor: totalMinor),
            computed: try JSONColumn.decode(ComputedDocument.self, from: computed)
        )
    }

    static func date(_ text: String) throws -> LocalDate {
        guard let date = LocalDate(iso: text) else { throw CorruptValue(column: "date", value: text) }
        return date
    }

    /// The live document `id` with its live lines, in position order.
    static func fetchDocument(id: String, db: Database) throws -> Document? {
        guard let record = try live.filter(key: id).fetchOne(db) else { return nil }
        return try record.document(lines: LineItemRecord.lines(ofDocument: id, db: db).map { try $0.line() })
    }
}

struct LineItemRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "line_item"

    var id: String
    var documentId: String
    var position: Int
    var catalogItemId: String?
    var description: String
    var productCode: String?
    var unit: String?
    var quantity: String
    var unitPriceMinor: Int64
    var discount: String?
    var rateId: String
    var rateSnapshot: String?
    var amountMinor: Int64?
    var taxableMinor: Int64?
    var taxMinor: Int64?
    var totalMinor: Int64?
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    init(_ line: LineItem, documentID: String, createdAt: Int64, updatedAt: Int64) throws {
        id = line.id
        documentId = documentID
        position = line.position
        catalogItemId = line.catalogItemId
        description = line.description
        productCode = line.productCode
        unit = line.unit
        quantity = line.quantity
        unitPriceMinor = line.unitPriceMinor
        discount = try JSONColumn.encode(line.discount)
        rateId = line.rateId
        rateSnapshot = try JSONColumn.encode(line.rateSnapshot)
        amountMinor = line.amountMinor
        taxableMinor = line.taxableMinor
        taxMinor = line.taxMinor
        totalMinor = line.totalMinor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        deletedAt = nil
    }

    func line() throws -> LineItem {
        LineItem(id: id, position: position, catalogItemId: catalogItemId, description: description,
                 productCode: productCode, unit: unit, quantity: quantity, unitPriceMinor: unitPriceMinor,
                 discount: try JSONColumn.decode(Discount.self, from: discount), rateId: rateId,
                 rateSnapshot: try JSONColumn.decode(RateSnapshot.self, from: rateSnapshot), amountMinor: amountMinor,
                 taxableMinor: taxableMinor, taxMinor: taxMinor, totalMinor: totalMinor)
    }

    static func lines(ofDocument documentID: String, db: Database) throws -> [LineItemRecord] {
        try live.filter(DBColumns.documentID == documentID).order(DBColumns.position, DBColumns.id).fetchAll(db)
    }

    /// Writes `lines` for a document: unchanged rows are left alone, changed ones updated (keeping `created_at`),
    /// new ones inserted, and live rows that are no longer there tombstoned.
    static func replaceLines(_ lines: [LineItem], documentID: String, now: Int64, db: Database) throws {
        let stored = try filter(DBColumns.documentID == documentID).fetchAll(db)
        let byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for line in lines {
            if let existing = byID[line.id] {
                var record = try LineItemRecord(line, documentID: documentID, createdAt: existing.createdAt,
                                                updatedAt: existing.updatedAt)
                guard record != existing else { continue }
                record.updatedAt = now
                try record.update(db)
            } else {
                try LineItemRecord(line, documentID: documentID, createdAt: now, updatedAt: now).insert(db)
            }
        }
        let kept = Set(lines.map(\.id))
        for record in stored where record.deletedAt == nil && !kept.contains(record.id) {
            try live.filter(key: record.id)
                .updateAll(db, DBColumns.deletedAt.set(to: now), DBColumns.updatedAt.set(to: now))
        }
    }
}

struct TaxLineRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "tax_line"

    var id: String
    var documentId: String
    var lineId: String?
    var component: String?
    var rate: String
    var category: String
    var taxableMinor: Int64
    var taxMinor: Int64
    var charged: Bool
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    init(id: String, documentID: String, taxLine: ComputedTaxLine, now: Int64) {
        self.id = id
        documentId = documentID
        lineId = nil
        component = taxLine.component
        rate = taxLine.rate
        category = taxLine.category.rawValue
        taxableMinor = taxLine.taxable
        taxMinor = taxLine.tax
        charged = taxLine.charged
        createdAt = now
        updatedAt = now
        deletedAt = nil
    }
}

/// A stored value that cannot be read back (a hand-edited or corrupted row).
struct CorruptValue: Error, CustomStringConvertible {
    let column: String
    let value: String

    var description: String { "unreadable \(column): \(value)" }
}
