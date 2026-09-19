import Foundation

/// Setup field rules (`spec/setup.md` §8): each normalises its input, then validates it.
/// Proven by `spec/fixtures/validation/fields.json`.
public enum FieldRule: String, CaseIterable, Sendable {
    case email
    case ifsc
    case upiVpa
    case sortCode
    case iban
    case bic
    case pan
    case postalCodeIN
    case postalCodeGB
    case companyNumberGB
    case hsnSac

    public func validate(_ value: String) -> FieldValidation {
        let normalized = normalize(value)
        guard SpecRegex.matches(pattern, normalized) else {
            return FieldValidation(valid: false, normalized: normalized, error: .format)
        }
        if self == .iban, !Self.ibanChecksumIsValid(normalized) {
            return FieldValidation(valid: false, normalized: normalized, error: .checksum)
        }
        return FieldValidation(valid: true, normalized: self == .sortCode ? Self.hyphenated(normalized) : normalized)
    }

    private func normalize(_ value: String) -> String {
        switch self {
        case .email:
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .upiVpa:
            value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        case .sortCode:
            value.removingWhitespace.replacingOccurrences(of: "-", with: "")
        case .ifsc, .iban, .bic, .pan:
            value.removingWhitespace.uppercased()
        case .postalCodeIN, .hsnSac:
            value.removingWhitespace
        case .postalCodeGB:
            Self.spacedPostcode(value.removingWhitespace.uppercased())
        case .companyNumberGB:
            Self.paddedCompanyNumber(value.removingWhitespace.uppercased())
        }
    }

    private var pattern: String {
        switch self {
        case .email: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        case .ifsc: "^[A-Z]{4}0[A-Z0-9]{6}$"
        case .upiVpa: "^[a-z0-9._-]{2,256}@[a-z][a-z0-9.-]{1,63}$"
        case .sortCode: "^[0-9]{6}$"
        case .iban: "^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$"
        case .bic: "^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$"
        case .pan: "^[A-Z]{5}[0-9]{4}[A-Z]$"
        case .postalCodeIN: "^[1-9][0-9]{5}$"
        case .postalCodeGB: "^[A-Z]{1,2}[0-9][A-Z0-9]? [0-9][A-Z]{2}$"
        case .companyNumberGB: "^([0-9]{8}|[A-Z]{2}[0-9]{6})$"
        case .hsnSac: "^[0-9]{2,8}$"
        }
    }

    /// `SW1A1AA` → `SW1A 1AA`: one space before the last 3 characters.
    private static func spacedPostcode(_ compact: String) -> String {
        guard compact.count > 3 else { return compact }
        return String(compact.dropLast(3)) + " " + String(compact.suffix(3))
    }

    /// Companies House numbers have 8 characters; 1–7 digits are left-padded with zeros.
    private static func paddedCompanyNumber(_ compact: String) -> String {
        guard compact.isASCIIDigits, compact.count < 8 else { return compact }
        return String(repeating: "0", count: 8 - compact.count) + compact
    }

    private static func hyphenated(_ sortCode: String) -> String {
        let digits = Array(sortCode)
        return String(digits[0..<2]) + "-" + String(digits[2..<4]) + "-" + String(digits[4..<6])
    }

    /// ISO 7064 mod 97-10: move the first 4 characters to the end, letters → 10–35, remainder must be 1.
    private static func ibanChecksumIsValid(_ iban: String) -> Bool {
        let rearranged = iban.dropFirst(4) + iban.prefix(4)
        var remainder = 0
        for character in rearranged {
            guard let ascii = character.asciiValue else { return false }
            switch ascii {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                remainder = (remainder * 10 + Int(ascii - UInt8(ascii: "0"))) % 97
            case UInt8(ascii: "A")...UInt8(ascii: "Z"): // two digits, 10–35
                remainder = (remainder * 100 + Int(ascii - UInt8(ascii: "A")) + 10) % 97
            default:
                return false
            }
        }
        return remainder == 1
    }
}

public struct FieldValidation: Equatable, Sendable {
    public var valid: Bool
    public var normalized: String
    public var error: FieldError?

    public init(valid: Bool, normalized: String, error: FieldError? = nil) {
        self.valid = valid
        self.normalized = normalized
        self.error = error
    }
}

public enum FieldError: String, Error, Sendable {
    case format
    case checksum
}
