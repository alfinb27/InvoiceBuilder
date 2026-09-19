import Foundation

/// Why typed text could not be read as an amount or a decimal (`spec/setup.md` §11).
public enum InputError: String, Error, Sendable, Equatable {
    case empty
    case invalid
    case tooManyDecimals
    case tooLarge
}

/// Money typed by the user, read into minor units (`spec/setup.md` §11). Never goes through `Double`.
public enum MoneyInput {
    /// The largest amount accepted: 10^15 minor units.
    public static let maxMinorUnits: Int64 = 1_000_000_000_000_000

    /// Reads `text` as an amount with `exponent` fraction digits (the currency's `minorUnits`).
    public static func parse(_ text: String, exponent: Int) -> Result<Int64, InputError> {
        let cleaned = String(text.unicodeScalars.filter { $0 != "," && !$0.properties.isWhitespace })
        guard !cleaned.isEmpty else { return .failure(.empty) }
        guard let parts = TypedNumber(cleaned) else { return .failure(.invalid) }
        guard parts.fraction.count <= exponent else { return .failure(.tooManyDecimals) }

        let integerDigits = parts.integer.drop { $0 == "0" }
        // 10^15 minor units has at most 16 integer digits (exponent 0); anything longer is too large.
        guard integerDigits.count <= 16 else { return .failure(.tooLarge) }
        let digits = String(integerDigits) + parts.fraction + String(repeating: "0", count: exponent - parts.fraction.count)
        guard let minor = Int64(digits.isEmpty ? "0" : digits) else { return .failure(.tooLarge) }
        return minor > maxMinorUnits ? .failure(.tooLarge) : .success(minor)
    }

    /// Plain text for editing an amount: no grouping, all fraction digits (`123450`, exponent 2 → `"1234.50"`).
    public static func editingText(minor: Int64, exponent: Int) -> String {
        let sign = minor < 0 ? "-" : ""
        var digits = String(minor.magnitude)
        guard exponent > 0 else { return sign + digits }
        if digits.count <= exponent {
            digits = String(repeating: "0", count: exponent + 1 - digits.count) + digits
        }
        let split = digits.index(digits.endIndex, offsetBy: -exponent)
        return sign + digits[..<split] + "." + digits[split...]
    }
}

/// A quantity or percent typed by the user, read into a canonical decimal string (`spec/setup.md` §11).
public enum DecimalInput {
    public static func parse(_ text: String) -> Result<String, InputError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let parts = TypedNumber(trimmed) else { return .failure(.invalid) }
        let integer = parts.integer.drop { $0 == "0" }
        var fraction = Substring(parts.fraction)
        while fraction.last == "0" { fraction = fraction.dropLast() }
        let whole = integer.isEmpty ? "0" : String(integer)
        return .success(fraction.isEmpty ? whole : whole + "." + fraction)
    }
}

/// `^[0-9]+(\.[0-9]*)?$` or `^\.[0-9]+$`, split into its digit runs.
private struct TypedNumber {
    let integer: String
    let fraction: String

    init?(_ text: String) {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2 else { return nil }
        let integer = String(pieces[0])
        let fraction = pieces.count == 2 ? String(pieces[1]) : ""
        guard integer.isEmpty || integer.isASCIIDigits, fraction.isEmpty || fraction.isASCIIDigits else { return nil }
        guard !integer.isEmpty || !fraction.isEmpty else { return nil } // "." alone
        self.integer = integer
        self.fraction = fraction
    }
}
