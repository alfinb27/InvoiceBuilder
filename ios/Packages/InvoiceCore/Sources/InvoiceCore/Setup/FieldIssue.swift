/// Why a setup field cannot be saved as typed. Screens turn these into messages.
public enum FieldIssue: Error, Equatable, Sendable {
    case required
    /// A `spec/setup.md` §8 field rule failed.
    case invalid(FieldRule, FieldError)
    /// A GSTIN / VAT number failed `ENGINE.md` §8.
    case invalidTaxID(TaxIDError)
    /// Typed money or decimal text (`spec/setup.md` §11).
    case invalidNumber(InputError)
    case outOfRange(ClosedRange<Int>)
    case invalidPattern([NumberingPatternIssue])
    case invalidNumbering(NumberingError)
    /// A next number at or below the highest one already issued in the period (`spec/setup.md` §6).
    case alreadyIssued(highest: Int)
    /// A line discount larger than quantity × price.
    case exceedsLineAmount
}

/// An address being edited: plain text fields, normalised when saved.
public struct AddressDraft: Equatable, Sendable {
    public var line1 = ""
    public var line2 = ""
    public var city = ""
    public var postalCode = ""

    public init(line1: String = "", line2: String = "", city: String = "", postalCode: String = "") {
        self.line1 = line1
        self.line2 = line2
        self.city = city
        self.postalCode = postalCode
    }

    public init(_ address: Address?) {
        self.init(line1: address?.line1 ?? "", line2: address?.line2 ?? "", city: address?.city ?? "",
                  postalCode: address?.postalCode ?? "")
    }

    /// True when every field is blank.
    public var isBlank: Bool {
        [line1, line2, city, postalCode].allSatisfy { $0.trimmedOrNil == nil }
    }

    /// The postal code rule for addresses in `countryCode` (`spec/setup.md` §8), if any.
    public static func postalRule(countryCode: String) -> FieldRule? {
        switch countryCode {
        case "IN": .postalCodeIN
        case "GB": .postalCodeGB
        default: nil
        }
    }

    /// Issues for the address fields: `line1` once anything is filled, and the postal code rule.
    func issues(countryCode: String, lineRequired: Bool) -> (line1: FieldIssue?, postalCode: FieldIssue?) {
        let line1Issue: FieldIssue? = (lineRequired || !isBlank) && line1.trimmedOrNil == nil ? .required : nil
        var postalIssue: FieldIssue?
        if let rule = Self.postalRule(countryCode: countryCode), let postal = postalCode.trimmedOrNil {
            let result = rule.validate(postal)
            if let error = result.error { postalIssue = .invalid(rule, error) }
        }
        return (line1Issue, postalIssue)
    }

    /// The stored address, or nil when blank.
    func address(countryCode: String, regionCode: String?) -> Address? {
        guard let line1 = line1.trimmedOrNil else { return nil }
        let postal = postalCode.trimmedOrNil.map { text in
            Self.postalRule(countryCode: countryCode).map { $0.validate(text).normalized } ?? text
        }
        return Address(line1: line1, line2: line2.trimmedOrNil, city: city.trimmedOrNil, regionCode: regionCode,
                       postalCode: postal, countryCode: countryCode)
    }
}

extension Dictionary where Key: Hashable, Value == FieldIssue {
    /// Adds the rule's issue for `value` (blank values are skipped: every rule field is optional unless stated).
    mutating func check(_ key: Key, _ value: String, rule: FieldRule) {
        guard let text = value.trimmedOrNil else { return }
        let result = rule.validate(text)
        if let error = result.error { self[key] = .invalid(rule, error) }
    }
}

/// Normalised text of a field rule, or the trimmed text when it does not validate (never stored: saving is blocked).
func normalized(_ value: String, rule: FieldRule) -> String? {
    guard let text = value.trimmedOrNil else { return nil }
    return rule.validate(text).normalized
}
