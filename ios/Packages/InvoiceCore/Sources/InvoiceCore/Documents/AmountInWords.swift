/// Amounts in words for invoices (`spec/tax/ENGINE.md` §7.3):
/// `{wordsMajor} {words(major)}[ and {words(minor)} {wordsMinor}] Only`, Indian lakh/crore grouping for INR and
/// billion/million elsewhere.
public enum AmountInWords {
    public static func text(minor: Int64, currency: CurrencyCode, currencies: CurrencyCatalog) -> String {
        let info = currencies[currency]
        let exponent = info?.minorUnits ?? 2
        let magnitude = minor.magnitude
        let divisor = UInt64(SpecMath.int64(SpecMath.powerOfTen(exponent)))
        let major = magnitude / divisor, fraction = magnitude % divisor
        let indian = currency == .inr
        var text = (info?.wordsMajor ?? currency.rawValue) + " " + words(major, indian: indian)
        if exponent > 0, fraction > 0 {
            text += " and " + words(fraction, indian: indian)
            if let wordsMinor = info?.wordsMinor { text += " " + wordsMinor }
        }
        return text + " Only"
    }

    /// Title Case words joined by single spaces, no "and" or hyphens inside numbers: `Twenty One`, `One Lakh`.
    public static func words(_ value: UInt64, indian: Bool) -> String {
        guard value > 0 else { return "Zero" }
        let scales: [(UInt64, String)] = indian
            ? [(10_000_000, "Crore"), (100_000, "Lakh"), (1000, "Thousand"), (100, "Hundred")]
            : [(1_000_000_000, "Billion"), (1_000_000, "Million"), (1000, "Thousand"), (100, "Hundred")]
        var parts: [String] = []
        var rest = value
        for (size, name) in scales where rest >= size {
            // The count may itself be large (≥ 100 crore, ≥ 1000 billion): it recurses.
            parts.append(words(rest / size, indian: indian) + " " + name)
            rest %= size
        }
        if rest > 0 { parts.append(belowHundred(Int(rest))) }
        return parts.joined(separator: " ")
    }

    private static let units = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
                                "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen",
                                "Eighteen", "Nineteen"]
    private static let tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]

    private static func belowHundred(_ value: Int) -> String {
        if value < 20 { return units[value] }
        return value % 10 == 0 ? tens[value / 10] : tens[value / 10] + " " + units[value % 10]
    }
}
