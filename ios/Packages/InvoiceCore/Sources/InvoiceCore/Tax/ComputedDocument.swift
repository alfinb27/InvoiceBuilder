/// The result of `TaxEngine.compute` (`spec/tax/ENGINE.md` §4). Issued documents store it as JSON (`computed`), so a
/// document never changes after the fact; the PDF renders only this.
public struct ComputedDocument: Codable, Hashable, Sendable {
    public var title: String
    public var chargesTax: Bool
    /// Region codes (India); nil for configs without regions.
    public var placeOfSupply: String?
    public var sameRegion: Bool?
    public var reverseCharge: Bool
    public var inclusive: Bool
    public var lines: [ComputedLine]
    public var shipping: ComputedShipping?
    public var taxLines: [ComputedTaxLine]
    public var totals: ComputedTotals
    public var home: HomeTotals?
    public var notes: [ComputedNote]
    public var issues: [EngineIssue]

    /// True when an issue of severity `error` blocks issuing.
    public var hasBlockingIssues: Bool { issues.contains { $0.severity == .error } }
}

public struct ComputedLine: Codable, Hashable, Sendable {
    /// Quantity × price less the line discount, rounded.
    public var amount: Int64
    /// This line's share of the invoice discount.
    public var discount: Int64
    public var taxable: Int64
    public var rateId: String
    /// Sum of the line's component percents ("0" when no tax applies).
    public var rate: String
    public var category: TaxCategory
    /// Per-component tax, only when tax is rounded per line (`taxLevel = line`).
    public var taxes: [LineTax]?

    /// Tax on this line (0 when tax is rounded per invoice).
    public var tax: Int64 { taxes?.reduce(0) { $0 + $1.amount } ?? 0 }
}

public struct LineTax: Codable, Hashable, Sendable {
    /// Nil for a non-tax group (exempt, nil-rated, outside scope).
    public var component: String?
    public var rate: String
    public var amount: Int64
}

public struct ComputedShipping: Codable, Hashable, Sendable {
    public var amount: Int64
    public var taxable: Int64
    public var parts: [ShippingPart]
}

public struct ShippingPart: Codable, Hashable, Sendable {
    public var rateId: String
    public var amount: Int64
    public var taxable: Int64
}

public struct ComputedTaxLine: Codable, Hashable, Sendable {
    /// Nil for a non-tax group.
    public var component: String?
    public var rate: String
    public var category: TaxCategory
    public var taxable: Int64
    public var tax: Int64
    /// False under reverse charge: shown, but not part of the total.
    public var charged: Bool
    /// The tax in home currency, when the config shows tax in home currency (UK VAT).
    public var homeTax: Int64?
}

public struct ComputedTotals: Codable, Hashable, Sendable {
    public var subtotal: Int64
    public var discount: Int64
    public var shipping: Int64
    public var taxable: Int64
    public var tax: Int64
    public var taxNotCharged: Int64
    public var roundOff: Int64
    public var total: Int64
}

public struct HomeTotals: Codable, Hashable, Sendable {
    public var currency: CurrencyCode
    /// The exchange rate as typed (decimal string).
    public var rate: String
    public var taxable: Int64
    public var tax: Int64
    public var total: Int64
}

public struct ComputedNote: Codable, Hashable, Sendable {
    public var id: String
    public var text: String
    /// `top` or `bottom` of the document.
    public var placement: String
}

/// A problem found while computing: compliance checks and rates not in force (`ENGINE.md` Step 12).
public struct EngineIssue: Codable, Hashable, Sendable {
    public var code: String
    public var severity: Severity
    /// 0-based line indexes the issue is about.
    public var lines: [Int]?

    public init(code: String, severity: Severity, lines: [Int]? = nil) {
        self.code = code
        self.severity = severity
        self.lines = lines
    }

    /// `error` blocks issuing; `warning` does not. An open set, like every value list.
    public struct Severity: RawRepresentable, Codable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let error = Severity(rawValue: "error")
        public static let warning = Severity(rawValue: "warning")
    }
}

/// Why no `ComputedDocument` could be produced (`ENGINE.md` §3, "Errors vs issues").
public struct TaxEngineError: Error, Equatable, Sendable {
    public enum Code: String, Sendable {
        case noComponentRule = "no_component_rule"
        case unknownRate = "unknown_rate"
        case unknownRegion = "unknown_region"
        case discountExceedsSubtotal = "discount_exceeds_subtotal"
        case lineDiscountExceedsAmount = "line_discount_exceeds_amount"
        case inclusiveCompoundUnsupported = "inclusive_compound_unsupported"
        case invalidInput = "invalid_input"
    }

    public let code: Code
    /// The 0-based line the error is about, if any.
    public let line: Int?

    public init(_ code: Code, line: Int? = nil) {
        self.code = code
        self.line = line
    }
}
