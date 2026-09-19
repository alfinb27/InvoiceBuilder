/// Deterministic money, percent and quantity text (`spec/tax/ENGINE.md` §7.1–7.2), identical on every platform and
/// locale. PDFs and the UI use it instead of platform number formatters, whose ICU data differs between versions.
public struct SpecFormatter: Sendable {
    public let currencies: CurrencyCatalog

    public init(currencies: CurrencyCatalog) {
        self.currencies = currencies
    }

    /// `₹1,23,456.78` (home currency) or `USD 1,234.50` (any other currency); negatives as `-₹1,234.00`.
    public func money(_ minor: Int64, currency: CurrencyCode, homeCurrency: CurrencyCode) -> String {
        let info = currencies[currency]
        let exponent = info?.minorUnits ?? 2
        let grouping = info?.grouping ?? [3]

        var digits = String(minor.magnitude)
        if digits.count < exponent + 1 {
            digits = String(repeating: "0", count: exponent + 1 - digits.count) + digits
        }
        let split = digits.index(digits.endIndex, offsetBy: -exponent)
        var text = Self.group(String(digits[..<split]), sizes: grouping)
        if exponent > 0 { text += "." + String(digits[split...]) }

        let prefix = currency == homeCurrency ? (info?.symbol ?? currency.rawValue + " ") : currency.rawValue + " "
        return (minor < 0 ? "-" : "") + prefix + text
    }

    public func money(_ money: Money, homeCurrency: CurrencyCode) -> String {
        self.money(money.minorUnits, currency: money.currency, homeCurrency: homeCurrency)
    }

    /// `"18.00"` → `18%`. Text that is not a spec decimal string is shown as typed.
    public static func percent(_ value: String) -> String {
        (DecimalString.canonical(value) ?? value) + "%"
    }

    /// `"1.500"` → `1.5`. Text that is not a spec decimal string is shown as typed.
    public static func quantity(_ value: String) -> String {
        DecimalString.canonical(value) ?? value
    }

    /// Groups integer digits from the right: first group `sizes[0]`, then the last size repeatedly.
    static func group(_ integer: String, sizes: [Int]) -> String {
        guard let first = sizes.first, first > 0 else { return integer }
        let repeating = max(sizes.last ?? first, 1)
        var groups: [Substring] = []
        var end = integer.endIndex
        var size = first
        while integer.distance(from: integer.startIndex, to: end) > size {
            let start = integer.index(end, offsetBy: -size)
            groups.append(integer[start..<end])
            end = start
            size = repeating
        }
        groups.append(integer[integer.startIndex..<end])
        return groups.reversed().joined(separator: ",")
    }
}
