import Foundation

/// A country tax configuration (`spec/schema/tax-config.schema.json`): data-driven rules that the tax engine
/// interprets (`spec/tax/ENGINE.md`). Adding a country is a new JSON file plus fixtures, not code.
public struct TaxConfig: Decodable, Hashable, Sendable {
    public let schemaVersion: Int
    /// ISO 3166-1 alpha-2; `ZZ` is the generic config.
    public let country: String
    /// The date the rules in this file take effect.
    public let configVersion: LocalDate
    public let reviewStatus: String
    public let currency: CurrencyCode?
    public let paperSize: String
    public let fiscalYearStart: MonthDay
    public let amountInWords: Bool
    public let labels: TaxLabels
    public let taxIdFormats: [TaxIDFormat]
    public let regions: [TaxRegion]
    public let foreignRegion: String?
    public let registrations: [TaxRegistration]
    public let ratesFrom: RatesSource
    public let rates: [TaxRate]
    public let supplyTypes: [SupplyType]
    public let componentRules: [ComponentRule]
    public let reverseCharge: ReverseChargeRules
    public let rounding: RoundingRules
    public let shipping: ShippingRules
    public let productCodes: ProductCodeRules?
    public let numbering: NumberingRules
    public let foreignCurrency: ForeignCurrencyRules
    public let checks: [TaxCheck]
    public let notesCatalog: [String: NoteText]

    enum CodingKeys: String, CodingKey {
        case schemaVersion, country, configVersion, reviewStatus, currency, paperSize, fiscalYearStart, amountInWords,
             labels, taxIdFormats, regions, foreignRegion, registrations, ratesFrom, rates, supplyTypes,
             componentRules, reverseCharge, rounding, shipping, productCodes, numbering, foreignCurrency, checks,
             notesCatalog
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        country = try c.decode(String.self, forKey: .country)
        configVersion = try c.decode(LocalDate.self, forKey: .configVersion)
        reviewStatus = try c.decode(String.self, forKey: .reviewStatus)
        currency = try c.decodeIfPresent(CurrencyCode.self, forKey: .currency)
        paperSize = try c.decode(String.self, forKey: .paperSize)
        fiscalYearStart = try c.decode(MonthDay.self, forKey: .fiscalYearStart)
        amountInWords = try c.decodeIfPresent(Bool.self, forKey: .amountInWords) ?? false
        labels = try c.decode(TaxLabels.self, forKey: .labels)
        taxIdFormats = try c.decodeIfPresent([TaxIDFormat].self, forKey: .taxIdFormats) ?? []
        regions = try c.decodeIfPresent([TaxRegion].self, forKey: .regions) ?? []
        foreignRegion = try c.decodeIfPresent(String.self, forKey: .foreignRegion)
        registrations = try c.decode([TaxRegistration].self, forKey: .registrations)
        ratesFrom = try c.decodeIfPresent(RatesSource.self, forKey: .ratesFrom) ?? .config
        rates = try c.decode([TaxRate].self, forKey: .rates)
        supplyTypes = try c.decode([SupplyType].self, forKey: .supplyTypes)
        componentRules = try c.decode([ComponentRule].self, forKey: .componentRules)
        reverseCharge = try c.decode(ReverseChargeRules.self, forKey: .reverseCharge)
        rounding = try c.decode(RoundingRules.self, forKey: .rounding)
        shipping = try c.decode(ShippingRules.self, forKey: .shipping)
        productCodes = try c.decodeIfPresent(ProductCodeRules.self, forKey: .productCodes)
        numbering = try c.decode(NumberingRules.self, forKey: .numbering)
        foreignCurrency = try c.decode(ForeignCurrencyRules.self, forKey: .foreignCurrency)
        checks = try c.decode([TaxCheck].self, forKey: .checks)
        notesCatalog = try c.decode([String: NoteText].self, forKey: .notesCatalog)
    }

    // MARK: Lookups

    /// The config id stored on a business (`IN`, `GB`, `GENERIC`); also the file name in `spec/tax`.
    public var family: String { country == "ZZ" ? "GENERIC" : country }

    /// `<family>@<configVersion>`, e.g. `IN@2025-09-22`, stored on documents as `tax_config_ref`.
    public var ref: String { "\(family)@\(configVersion.iso)" }

    public func registration(_ id: String) -> TaxRegistration? {
        registrations.first { $0.id == id }
    }

    public func region(_ code: String) -> TaxRegion? {
        regions.first { $0.code == code }
    }

    /// Regions offered in pickers: active ones, sorted by name.
    public var activeRegionsByName: [TaxRegion] {
        regions.filter(\.isActive).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The tax ID format used for sellers and domestic buyers (the first entry), if the country has one.
    public var taxIDFormat: TaxIDFormat? { taxIdFormats.first }

    /// The rates a business can use: the config's own, or the business's custom rates when `ratesFrom = business`.
    public func availableRates(customRates: [TaxRate]?) -> [TaxRate] {
        ratesFrom == .business ? (customRates ?? []) : rates
    }

    /// Rates in force on `date` (`effectiveFrom ≤ date ≤ effectiveTo`), in config order (`spec/setup.md` §10).
    public func ratesInForce(on date: LocalDate, customRates: [TaxRate]?) -> [TaxRate] {
        availableRates(customRates: customRates).filter { $0.isInForce(on: date) }
    }

    public func rate(_ id: String, customRates: [TaxRate]?) -> TaxRate? {
        availableRates(customRates: customRates).first { $0.id == id }
    }

    public func numberingPattern(for docType: DocumentType) -> String {
        docType == .quote ? numbering.quotePattern : numbering.invoicePattern
    }
}

public enum RatesSource: String, Codable, Sendable {
    case config
    case business
}

public struct TaxLabels: Codable, Hashable, Sendable {
    public let taxName: String
    public let taxIdName: String
    public let productCodeName: String
    public let regionName: String?
    public let placeOfSupply: String?
}

public struct TaxIDFormat: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let pattern: String
    /// `gstinMod36` or `ukVatMod97` (`ENGINE.md` §8).
    public let checksum: String?
    /// The first N characters of a valid ID are a region code (GSTIN state code).
    public let regionFromPrefix: Int?
    /// Prepended to bare 9- or 12-digit input (`GB`).
    public let normalizePrefix: String?
}

public struct TaxRegion: Codable, Hashable, Sendable, Identifiable {
    public let code: String
    public let name: String
    /// `SGST` or `UTGST` for Indian states and union territories.
    public let localComponent: String?
    public let active: Bool?

    public var id: String { code }
    public var isActive: Bool { active ?? true }
}

public struct TaxRegistration: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let chargesTax: Bool
    public let requiresTaxId: Bool
    public let titles: DocumentTitles
    public let notes: [String]?
}

public struct DocumentTitles: Codable, Hashable, Sendable {
    public let invoice: String
    public let invoiceAllExempt: String?
    public let quote: String
}

/// A tax rate: from a config's `rates`, or a business's custom rate (GENERIC, with `components`).
public struct TaxRate: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var percent: String?
    public var category: TaxCategory
    public var label: String
    public var effectiveFrom: LocalDate
    public var effectiveTo: LocalDate?
    public var note: String?
    public var components: [RateComponent]?

    public init(id: String, percent: String? = nil, category: TaxCategory, label: String, effectiveFrom: LocalDate,
                effectiveTo: LocalDate? = nil, note: String? = nil, components: [RateComponent]? = nil) {
        self.id = id
        self.percent = percent
        self.category = category
        self.label = label
        self.effectiveFrom = effectiveFrom
        self.effectiveTo = effectiveTo
        self.note = note
        self.components = components
    }

    /// `effectiveFrom ≤ date ≤ effectiveTo`, both inclusive.
    public func isInForce(on date: LocalDate) -> Bool {
        effectiveFrom <= date && (effectiveTo.map { date <= $0 } ?? true)
    }
}

public struct RateComponent: Codable, Hashable, Sendable {
    public var code: String
    public var label: String
    public var percent: String
    public var compound: Bool?

    public init(code: String, label: String, percent: String, compound: Bool? = nil) {
        self.code = code
        self.label = label
        self.percent = percent
        self.compound = compound
    }
}

/// Tax category of a rate or component. An open set: values written by a newer app version are kept.
public struct TaxCategory: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let standard = TaxCategory(rawValue: "standard")
    public static let reduced = TaxCategory(rawValue: "reduced")
    public static let zero = TaxCategory(rawValue: "zero")
    public static let exempt = TaxCategory(rawValue: "exempt")
    public static let nilRated = TaxCategory(rawValue: "nil")
    public static let outsideScope = TaxCategory(rawValue: "outsideScope")
}

public struct SupplyType: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
}

public struct ComponentRule: Decodable, Hashable, Sendable {
    public let when: TaxCondition
    public let components: ComponentSource
    public let notes: [String]?
}

/// A rule's components: listed in the config, or taken from the rate itself (`"fromRate"`, GENERIC).
public enum ComponentSource: Decodable, Hashable, Sendable {
    case fromRate
    case list([ComponentRef])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            guard text == "fromRate" else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown components \(text)")
            }
            self = .fromRate
        } else {
            self = .list(try container.decode([ComponentRef].self))
        }
    }
}

public struct ComponentRef: Codable, Hashable, Sendable {
    /// A component code, or `$localComponent` for the place-of-supply region's local component.
    public let code: String
    public let share: String
    public let rateOverride: String?
    public let categoryOverride: TaxCategory?
}

/// Keys a rule or check matches on; every listed key must match (`ENGINE.md` Step 1, Step 12).
public struct TaxCondition: Codable, Hashable, Sendable {
    public let supplyType: [String]?
    public let sameRegion: Bool?
    public let sellerRegistration: [String]?
    public let buyerIsBusiness: Bool?
    public let buyerHasTaxId: Bool?
    public let reverseCharge: Bool?
    public let docType: [String]?
    public let foreignCurrency: Bool?
    public let totalAtLeastMinor: Int64?
}

public struct ReverseChargeRules: Codable, Hashable, Sendable {
    public let supported: Bool
    public let notes: [String]?
}

public enum RoundingMode: String, Codable, Sendable, CaseIterable {
    case halfAwayFromZero
    case halfEven
    case towardZero
}

public enum TaxLevel: String, Codable, Sendable {
    case line
    case invoice
}

public struct RoundingRules: Codable, Hashable, Sendable {
    public let amountMode: RoundingMode
    public let taxLevel: TaxLevel
    public let taxMode: RoundingMode
    public let grandTotal: GrandTotalRounding?
}

public struct GrandTotalRounding: Codable, Hashable, Sendable {
    public let roundToMinor: Int64
    public let mode: RoundingMode
    public let label: String
    public let defaultOn: Bool
}

public enum ShippingRule: String, Codable, Sendable {
    case principalSupplyRate
    case apportion
}

public struct ShippingRules: Codable, Hashable, Sendable {
    public let rule: ShippingRule
}

public struct ProductCodeRules: Codable, Hashable, Sendable {
    public let tiers: [ProductCodeTier]
}

public struct ProductCodeTier: Codable, Hashable, Sendable {
    public let maxTurnoverMinor: Int64?
    public let b2bDigits: Int
    public let b2cDigits: Int
}

public struct NumberingRules: Codable, Hashable, Sendable {
    public let maxLength: Int?
    public let allowedPattern: String?
    public let reset: NumberingReset
    public let invoicePattern: String
    public let quotePattern: String
}

public struct ForeignCurrencyRules: Codable, Hashable, Sendable {
    public let homeTotals: Bool
    public let taxInHomeCurrency: Bool
}

public struct TaxCheck: Codable, Hashable, Sendable {
    public let code: String
    public let severity: String
    public let type: String?
    public let require: [String]?
    public let when: TaxCondition?
}

public struct NoteText: Codable, Hashable, Sendable {
    public let text: String
    public let placement: String
}
