import Foundation

public enum LineItemField: Hashable, Sendable {
    case description, quantity, price, discount, rate, productCode
}

/// A line being edited in the builder's line editor: plain text fields, validated live and applied on Done
/// (`spec/documents.md` §3, typed input per `spec/setup.md` §11).
public struct LineItemDraft: Equatable, Sendable {
    public var description = ""
    public var productCode = ""
    public var unit: String?
    public var quantityText = "1"
    /// In the document's currency and price basis.
    public var priceText = ""
    public var discountText = ""
    public var discountIsPercent = true
    public var rateId = ""

    public init() {}

    public init(line: LineItem, exponent: Int) {
        description = line.description
        productCode = line.productCode ?? ""
        unit = line.unit
        quantityText = SpecFormatter.quantity(line.quantity)
        priceText = MoneyInput.editingText(minor: line.unitPriceMinor, exponent: exponent)
        switch line.discount {
        case .percent(let value)?:
            discountText = SpecFormatter.quantity(value)
            discountIsPercent = true
        case .amount(let minor)?:
            discountText = MoneyInput.editingText(minor: minor, exponent: exponent)
            discountIsPercent = false
        case nil:
            break
        }
        rateId = line.rateId
    }
}

/// Validation and normalisation for the line editor.
public struct LineItemRules: Sendable {
    public let config: TaxConfig
    public let chargesTax: Bool
    /// Fraction digits of the document currency.
    public let exponent: Int

    public init(config: TaxConfig, chargesTax: Bool, exponent: Int) {
        self.config = config
        self.chargesTax = chargesTax
        self.exponent = exponent
    }

    /// India: HSN/SAC digits only.
    public var productCodeRule: FieldRule? { config.family == "IN" ? .hsnSac : nil }

    public func issues(_ draft: LineItemDraft) -> [LineItemField: FieldIssue] {
        var issues: [LineItemField: FieldIssue] = [:]
        if draft.description.trimmedOrNil == nil { issues[.description] = .required }
        let quantity = DecimalInput.parse(draft.quantityText)
        if case .failure(let error) = quantity {
            issues[.quantity] = error == .empty ? .required : .invalidNumber(error)
        }
        let price = MoneyInput.parse(draft.priceText, exponent: exponent)
        if case .failure(let error) = price {
            issues[.price] = error == .empty ? .required : .invalidNumber(error)
        }
        switch DocumentInput.discount(draft.discountText, isPercent: draft.discountIsPercent, exponent: exponent) {
        case .failure(let issue):
            issues[.discount] = issue
        case .success(let discount?):
            if case .success(let quantity) = quantity, case .success(let price) = price,
               let gross = DecimalString.parse(quantity).map({ $0 * Decimal(price) }),
               case .amount(let value) = discount, Decimal(value) > gross {
                issues[.discount] = .exceedsLineAmount
            }
        case .success(nil):
            break
        }
        if chargesTax, draft.rateId.trimmedOrNil == nil { issues[.rate] = .required }
        if let rule = productCodeRule { issues.check(.productCode, draft.productCode, rule: rule) }
        return issues
    }

    /// Copies the draft's valid values onto `line` (invalid text leaves the old value in place).
    public func apply(_ draft: LineItemDraft, to line: inout LineItem) {
        line.description = draft.description.trimmedOrNil ?? line.description
        line.productCode = productCodeRule.map { normalized(draft.productCode, rule: $0) }
            ?? draft.productCode.trimmedOrNil
        line.unit = draft.unit
        if case .success(let quantity) = DecimalInput.parse(draft.quantityText) { line.quantity = quantity }
        if case .success(let price) = MoneyInput.parse(draft.priceText, exponent: exponent) {
            line.unitPriceMinor = price
        }
        if case .success(let discount) = DocumentInput.discount(draft.discountText, isPercent: draft.discountIsPercent,
                                                                  exponent: exponent) {
            line.discount = discount
        }
        if draft.rateId.trimmedOrNil != nil { line.rateId = draft.rateId }
    }
}

/// The builder's typed document fields (`spec/setup.md` §11 parsers).
public enum DocumentInput {
    /// A line or invoice discount: empty → none; a percent must be at most 100.
    public static func discount(_ text: String, isPercent: Bool, exponent: Int) -> Result<Discount?, FieldIssue> {
        guard text.trimmedOrNil != nil else { return .success(nil) }
        if isPercent {
            switch DecimalInput.parse(text) {
            case .success(let value):
                guard let percent = DecimalString.parse(value), percent <= 100 else {
                    return .failure(.outOfRange(0...100))
                }
                return .success(percent == 0 ? nil : .percent(value))
            case .failure(let error):
                return .failure(.invalidNumber(error))
            }
        }
        switch MoneyInput.parse(text, exponent: exponent) {
        case .success(let minor): return .success(minor == 0 ? nil : .amount(minor))
        case .failure(let error): return .failure(.invalidNumber(error))
        }
    }

    /// Shipping: empty → 0.
    public static func shipping(_ text: String, exponent: Int) -> Result<Int64, FieldIssue> {
        guard text.trimmedOrNil != nil else { return .success(0) }
        return MoneyInput.parse(text, exponent: exponent).mapError { .invalidNumber($0) }
    }

    /// Units of home currency per 1 unit of the document currency: empty → none; otherwise a positive decimal.
    public static func exchangeRate(_ text: String) -> Result<String?, FieldIssue> {
        guard text.trimmedOrNil != nil else { return .success(nil) }
        switch DecimalInput.parse(text) {
        case .success(let value):
            guard let rate = DecimalString.parse(value), rate > 0 else { return .failure(.invalidNumber(.invalid)) }
            return .success(value)
        case .failure(let error):
            return .failure(.invalidNumber(error))
        }
    }

    /// Editing text for a discount: `("10", true)`, `("250.00", false)` or `("", true)`.
    public static func editingText(_ discount: Discount?, exponent: Int) -> (text: String, isPercent: Bool) {
        switch discount {
        case .percent(let value)?: (SpecFormatter.quantity(value), true)
        case .amount(let minor)?: (MoneyInput.editingText(minor: minor, exponent: exponent), false)
        case nil: ("", true)
        }
    }

    /// Editing text for an amount that may be 0 (shown empty).
    public static func editingText(minor: Int64, exponent: Int) -> String {
        minor == 0 ? "" : MoneyInput.editingText(minor: minor, exponent: exponent)
    }
}
