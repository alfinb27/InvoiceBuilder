/// A product or service in the item catalogue (`domain.schema.json#/$defs/CatalogItem`).
public struct CatalogItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var deletedAt: Int64?

    public var businessId: String
    public var name: String
    public var description: String?
    public var kind: ItemKind
    /// A `spec/reference/units.json` id (UQC).
    public var unit: String
    public var unitPriceMinor: Int64
    public var currency: CurrencyCode
    public var rateId: String
    /// HSN/SAC (India) or commodity code.
    public var productCode: String?
    public var priceIncludesTax: Bool
    public var archivedAt: Int64?

    public init(id: String, createdAt: Int64 = 0, updatedAt: Int64 = 0, deletedAt: Int64? = nil, businessId: String,
                name: String, description: String? = nil, kind: ItemKind = .service, unit: String,
                unitPriceMinor: Int64, currency: CurrencyCode, rateId: String, productCode: String? = nil,
                priceIncludesTax: Bool = false, archivedAt: Int64? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.businessId = businessId
        self.name = name
        self.description = description
        self.kind = kind
        self.unit = unit
        self.unitPriceMinor = unitPriceMinor
        self.currency = currency
        self.rateId = rateId
        self.productCode = productCode
        self.priceIncludesTax = priceIncludesTax
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }
    public var unitPrice: Money { Money(minorUnits: unitPriceMinor, currency: currency) }
}

/// Goods or service. An open set.
public struct ItemKind: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let goods = ItemKind(rawValue: "goods")
    public static let service = ItemKind(rawValue: "service")
    public static let known: [ItemKind] = [.goods, .service]

    /// The unit a new item of this kind starts with (`spec/setup.md` §10).
    public var defaultUnit: String { self == .goods ? "NOS" : "OTH" }
}
