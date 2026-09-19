/// A customer (`domain.schema.json#/$defs/Client`).
public struct Client: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var deletedAt: Int64?

    public var businessId: String
    public var name: String
    public var contactName: String?
    public var email: String?
    public var phone: String?
    public var billingAddress: Address?
    public var shippingAddress: Address?
    public var countryCode: String
    public var regionCode: String?
    public var taxId: String?
    /// B2B when true.
    public var isBusiness: Bool
    /// Nil = the business home currency.
    public var defaultCurrency: CurrencyCode?
    public var notes: String?
    public var archivedAt: Int64?

    public init(id: String, createdAt: Int64 = 0, updatedAt: Int64 = 0, deletedAt: Int64? = nil, businessId: String,
                name: String, contactName: String? = nil, email: String? = nil, phone: String? = nil,
                billingAddress: Address? = nil, shippingAddress: Address? = nil, countryCode: String,
                regionCode: String? = nil, taxId: String? = nil, isBusiness: Bool = false,
                defaultCurrency: CurrencyCode? = nil, notes: String? = nil, archivedAt: Int64? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.businessId = businessId
        self.name = name
        self.contactName = contactName
        self.email = email
        self.phone = phone
        self.billingAddress = billingAddress
        self.shippingAddress = shippingAddress
        self.countryCode = countryCode
        self.regionCode = regionCode
        self.taxId = taxId
        self.isBusiness = isBusiness
        self.defaultCurrency = defaultCurrency
        self.notes = notes
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }
}
