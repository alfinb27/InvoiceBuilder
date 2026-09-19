/// Result of validating a GSTIN or UK VAT number (`spec/tax/ENGINE.md` §8).
public struct TaxIDValidation: Equatable, Sendable {
    public var valid: Bool
    /// Trimmed, whitespace removed, upper-cased (and `GB`-prefixed for bare UK numbers). Reported even when invalid.
    public var normalized: String
    /// GSTIN state code (first 2 characters) of a valid GSTIN.
    public var region: String?
    public var error: TaxIDError?

    public init(valid: Bool, normalized: String, region: String? = nil, error: TaxIDError? = nil) {
        self.valid = valid
        self.normalized = normalized
        self.region = region
        self.error = error
    }
}

public enum TaxIDError: String, Error, Sendable {
    case format
    case checksum
    case unknownRegion = "unknown_region"
}

public enum TaxIDValidator {
    /// Validates `value` with the config's tax ID format; nil when the config has none (GENERIC).
    public static func validate(_ value: String, config: TaxConfig) -> TaxIDValidation? {
        config.taxIDFormat.map { validate(value, format: $0, regions: config.regions) }
    }

    /// Normalise, then check the format, the checksum and (GSTIN) the region, in that order.
    public static func validate(_ value: String, format: TaxIDFormat, regions: [TaxRegion]) -> TaxIDValidation {
        var normalized = value.removingWhitespace.uppercased()
        if let prefix = format.normalizePrefix, normalized.isASCIIDigits, [9, 12].contains(normalized.count) {
            normalized = prefix + normalized
        }
        guard SpecRegex.matches(format.pattern, normalized) else {
            return TaxIDValidation(valid: false, normalized: normalized, error: .format)
        }
        switch format.checksum {
        case "gstinMod36":
            guard gstinChecksumIsValid(normalized) else {
                return TaxIDValidation(valid: false, normalized: normalized, error: .checksum)
            }
        case "ukVatMod97":
            guard ukVatChecksumIsValid(normalized) else {
                return TaxIDValidation(valid: false, normalized: normalized, error: .checksum)
            }
        default:
            break
        }
        guard let prefixLength = format.regionFromPrefix else {
            return TaxIDValidation(valid: true, normalized: normalized)
        }
        let region = String(normalized.prefix(prefixLength))
        guard regions.contains(where: { $0.code == region }) else {
            return TaxIDValidation(valid: false, normalized: normalized, error: .unknownRegion)
        }
        return TaxIDValidation(valid: true, normalized: normalized, region: region)
    }

    /// `0-9A-Z` → 0–35; weights 1, 2, 1, 2, … over the first 14 characters; `p = value × weight`;
    /// `sum += p / 36 + p % 36`; the check character is `(36 − sum % 36) % 36`.
    static func gstinChecksumIsValid(_ gstin: String) -> Bool {
        let values = gstin.compactMap(base36Value)
        guard values.count == 15 else { return false }
        var sum = 0
        for (index, value) in values.prefix(14).enumerated() {
            let product = value * (index % 2 == 0 ? 1 : 2)
            sum += product / 36 + product % 36
        }
        return (36 - sum % 36) % 36 == values[14]
    }

    /// Numeric forms: the 9 digits after `GB`; `w = Σ d_i × (8, 7, 6, 5, 4, 3, 2)` over d0…d6 and
    /// `chk = 10 × d7 + d8`; valid if `(w + chk) % 97 == 0` or `(w + 55 + chk) % 97 == 0`.
    /// `GD`/`HA` (government departments, health authorities) are format-checked only.
    static func ukVatChecksumIsValid(_ vat: String) -> Bool {
        let body = vat.dropFirst(2)
        guard body.first?.isNumber == true else { return true }
        let digits = body.prefix(9).compactMap(\.wholeNumberValue)
        guard digits.count == 9 else { return false }
        let weights = [8, 7, 6, 5, 4, 3, 2]
        let weighted = zip(digits.prefix(7), weights).reduce(0) { $0 + $1.0 * $1.1 }
        let check = 10 * digits[7] + digits[8]
        return (weighted + check) % 97 == 0 || (weighted + 55 + check) % 97 == 0
    }

    /// `0-9` → 0–9, `A-Z` → 10–35.
    private static func base36Value(_ character: Character) -> Int? {
        guard let ascii = character.asciiValue else { return nil }
        switch ascii {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(ascii - UInt8(ascii: "0"))
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): return Int(ascii - UInt8(ascii: "A")) + 10
        default: return nil
        }
    }
}
