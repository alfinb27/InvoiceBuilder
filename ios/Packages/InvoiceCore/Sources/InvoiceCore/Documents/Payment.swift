/// How a payment was made (`spec/documents.md` §10). An open set, like every stored value list.
public struct PaymentMethod: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let cash = PaymentMethod(rawValue: "cash")
    public static let bank = PaymentMethod(rawValue: "bank")
    public static let upi = PaymentMethod(rawValue: "upi")
    public static let card = PaymentMethod(rawValue: "card")
    public static let cheque = PaymentMethod(rawValue: "cheque")
    public static let other = PaymentMethod(rawValue: "other")
}

/// A payment recorded against an issued invoice (`domain.schema.json#/$defs/Payment`, `spec/documents.md` §10).
/// The document row is never touched by recording one; `paid` is always the sum of an invoice's live payments,
/// never stored.
public struct Payment: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var deletedAt: Int64?

    public var businessId: String
    public var documentId: String
    public var amountMinor: Int64
    public var date: LocalDate
    public var method: PaymentMethod
    public var reference: String?
    public var note: String?

    public init(id: String, createdAt: Int64 = 0, updatedAt: Int64 = 0, deletedAt: Int64? = nil, businessId: String,
                documentId: String, amountMinor: Int64, date: LocalDate, method: PaymentMethod,
                reference: String? = nil, note: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.businessId = businessId
        self.documentId = documentId
        self.amountMinor = amountMinor
        self.date = date
        self.method = method
        self.reference = reference
        self.note = note
    }
}
