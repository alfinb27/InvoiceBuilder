import Foundation

/// Decimal strings as stored in JSON and SQLite (rates, quantities, exchange rates):
/// `^-?(0|[1-9][0-9]*)(\.[0-9]+)?$` (`spec/tax/ENGINE.md` §1).
///
/// Parse with these helpers, never with `Decimal(string:)` directly: it accepts partial input such as `"1.5abc"`.
public enum DecimalString {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// True when `text` is a spec decimal string.
    public static func isValid(_ text: String) -> Bool {
        var bytes = Substring(text).utf8[...]
        if bytes.first == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
        let integer = bytes.prefix { $0 != UInt8(ascii: ".") }
        guard !integer.isEmpty, integer.allSatisfy(isDigit) else { return false }
        if integer.count > 1, integer.first == UInt8(ascii: "0") { return false }
        let rest = bytes.dropFirst(integer.count)
        guard !rest.isEmpty else { return true }
        let fraction = rest.dropFirst() // drop "."
        return !fraction.isEmpty && fraction.allSatisfy(isDigit)
    }

    /// The value of a spec decimal string, or nil for anything else.
    public static func parse(_ text: String) -> Decimal? {
        guard isValid(text) else { return nil }
        return Decimal(string: text, locale: posix)
    }

    /// Canonical form (`ENGINE.md` §7.2): trailing fractional zeros and a trailing "." dropped
    /// (`"18.00"` → `"18"`, `"8.8750"` → `"8.875"`). Nil when `text` is not a spec decimal string.
    public static func canonical(_ text: String) -> String? {
        guard isValid(text) else { return nil }
        guard text.contains(".") else { return text == "-0" ? "0" : text }
        var result = Substring(text)
        while result.last == "0" { result = result.dropLast() }
        if result.last == "." { result = result.dropLast() }
        return result == "-0" ? "0" : String(result)
    }

    /// The canonical decimal string of a value (no exponent notation, no trailing zeros).
    public static func string(from value: Decimal) -> String {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 34, .plain) // Foundation prints at most 38 digits; keep it exact below that.
        let text = NSDecimalNumber(decimal: rounded).description(withLocale: posix)
        return canonical(text) ?? text
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }
}
