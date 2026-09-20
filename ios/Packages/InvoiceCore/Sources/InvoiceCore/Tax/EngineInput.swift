/// Everything `TaxEngine.compute` reads (`spec/tax/ENGINE.md` §1). The JSON form of `seller`, `buyer` and `draft`
/// is the fixture input shape, and it is what issued documents freeze as their snapshots.
public struct EngineInput: Sendable {
    public var config: TaxConfig
    public var seller: EngineSeller
    public var buyer: EngineBuyer
    public var draft: EngineDraft
    /// Currency exponents for home-currency conversion.
    public var currencies: CurrencyCatalog

    public init(config: TaxConfig, seller: EngineSeller, buyer: EngineBuyer, draft: EngineDraft,
                currencies: CurrencyCatalog) {
        self.config = config
        self.seller = seller
        self.buyer = buyer
        self.draft = draft
        self.currencies = currencies
    }
}

public struct EngineSeller: Codable, Hashable, Sendable {
    public var registration: String
    public var taxId: String?
    /// The seller's region when known; otherwise read from the tax ID prefix (GSTIN).
    public var region: String?
    public var country: String
    public var homeCurrency: CurrencyCode
    public var lutReference: String?
    /// One line, for the `seller.address` check.
    public var address: String?
    public var turnoverMinor: Int64?
    /// Business-defined rates (`ratesFrom = business`).
    public var customRates: [TaxRate]?

    public init(registration: String, taxId: String? = nil, region: String? = nil, country: String,
                homeCurrency: CurrencyCode, lutReference: String? = nil, address: String? = nil,
                turnoverMinor: Int64? = nil, customRates: [TaxRate]? = nil) {
        self.registration = registration
        self.taxId = taxId
        self.region = region
        self.country = country
        self.homeCurrency = homeCurrency
        self.lutReference = lutReference
        self.address = address
        self.turnoverMinor = turnoverMinor
        self.customRates = customRates
    }
}

public struct EngineBuyer: Codable, Hashable, Sendable {
    public var name: String?
    public var address: String?
    /// Nil means domestic (walk-in customers, quick bills).
    public var country: String?
    public var region: String?
    public var taxId: String?
    public var isBusiness: Bool

    public init(name: String? = nil, address: String? = nil, country: String? = nil, region: String? = nil,
                taxId: String? = nil, isBusiness: Bool = false) {
        self.name = name
        self.address = address
        self.country = country
        self.region = region
        self.taxId = taxId
        self.isBusiness = isBusiness
    }
}

public struct EngineDraft: Codable, Hashable, Sendable {
    public var docType: DocumentType
    public var issueDate: LocalDate
    /// Tax point; selects the rates in force (defaults to `issueDate`).
    public var supplyDate: LocalDate?
    public var dueDate: LocalDate?
    public var currency: CurrencyCode
    /// Units of home currency per 1 unit of document currency (decimal string).
    public var exchangeRate: String?
    public var supplyType: String
    /// Overrides the derived place of supply.
    public var placeOfSupply: String?
    public var reverseCharge: Bool
    public var pricesIncludeTax: Bool
    public var lines: [EngineLine]
    public var discount: Discount?
    /// Minor units, on the same price basis as the lines.
    public var shipping: Int64?
    /// Overrides the config's `grandTotal.defaultOn`.
    public var roundOff: Bool?

    public init(docType: DocumentType, issueDate: LocalDate, supplyDate: LocalDate? = nil, dueDate: LocalDate? = nil,
                currency: CurrencyCode, exchangeRate: String? = nil, supplyType: String, placeOfSupply: String? = nil,
                reverseCharge: Bool = false, pricesIncludeTax: Bool = false, lines: [EngineLine],
                discount: Discount? = nil, shipping: Int64? = nil, roundOff: Bool? = nil) {
        self.docType = docType
        self.issueDate = issueDate
        self.supplyDate = supplyDate
        self.dueDate = dueDate
        self.currency = currency
        self.exchangeRate = exchangeRate
        self.supplyType = supplyType
        self.placeOfSupply = placeOfSupply
        self.reverseCharge = reverseCharge
        self.pricesIncludeTax = pricesIncludeTax
        self.lines = lines
        self.discount = discount
        self.shipping = shipping
        self.roundOff = roundOff
    }

    enum CodingKeys: String, CodingKey {
        case docType, issueDate, supplyDate, dueDate, currency, exchangeRate, supplyType, placeOfSupply, reverseCharge,
             pricesIncludeTax, lines, discount, shipping, roundOff
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        docType = try c.decode(DocumentType.self, forKey: .docType)
        issueDate = try c.decode(LocalDate.self, forKey: .issueDate)
        supplyDate = try c.decodeIfPresent(LocalDate.self, forKey: .supplyDate)
        dueDate = try c.decodeIfPresent(LocalDate.self, forKey: .dueDate)
        currency = try c.decode(CurrencyCode.self, forKey: .currency)
        exchangeRate = try c.decodeIfPresent(String.self, forKey: .exchangeRate)
        supplyType = try c.decode(String.self, forKey: .supplyType)
        placeOfSupply = try c.decodeIfPresent(String.self, forKey: .placeOfSupply)
        reverseCharge = try c.decodeIfPresent(Bool.self, forKey: .reverseCharge) ?? false
        pricesIncludeTax = try c.decodeIfPresent(Bool.self, forKey: .pricesIncludeTax) ?? false
        lines = try c.decode([EngineLine].self, forKey: .lines)
        discount = try c.decodeIfPresent(Discount.self, forKey: .discount)
        shipping = try c.decodeIfPresent(Int64.self, forKey: .shipping)
        roundOff = try c.decodeIfPresent(Bool.self, forKey: .roundOff)
    }
}

public struct EngineLine: Codable, Hashable, Sendable {
    public var description: String?
    public var productCode: String?
    /// Decimal string.
    public var quantity: String
    /// Minor units of the document currency.
    public var unitPrice: Int64
    public var discount: Discount?
    public var rateId: String

    public init(description: String? = nil, productCode: String? = nil, quantity: String, unitPrice: Int64,
                discount: Discount? = nil, rateId: String) {
        self.description = description
        self.productCode = productCode
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discount = discount
        self.rateId = rateId
    }
}

/// A line or invoice discount: a percentage (decimal string) or an amount (minor units).
/// JSON: `{ "type": "percent", "value": "10" }` or `{ "type": "amount", "value": 5000 }`.
public enum Discount: Codable, Hashable, Sendable {
    case percent(String)
    case amount(Int64)

    enum CodingKeys: String, CodingKey { case type, value }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "percent": self = .percent(try c.decode(String.self, forKey: .value))
        case "amount": self = .amount(try c.decode(Int64.self, forKey: .value))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown discount \(other)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .percent(let value):
            try c.encode("percent", forKey: .type)
            try c.encode(value, forKey: .value)
        case .amount(let value):
            try c.encode("amount", forKey: .type)
            try c.encode(value, forKey: .value)
        }
    }
}
