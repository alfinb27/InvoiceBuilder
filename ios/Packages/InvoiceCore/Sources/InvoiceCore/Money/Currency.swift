/// One entry of `spec/reference/currencies.json`.
public struct Currency: Codable, Hashable, Sendable, Identifiable {
    public let code: CurrencyCode
    public let name: String
    /// ISO 4217 exponent: INR/GBP 2, JPY 0, KWD 3.
    public let minorUnits: Int
    /// Shown only when the currency is the business home currency; otherwise documents show the ISO code.
    public let symbol: String
    /// Digit group sizes from the right: INR `[3, 2]` → `1,23,45,678`.
    public let grouping: [Int]
    public let wordsMajor: String
    public let wordsMinor: String?

    public var id: CurrencyCode { code }

    public init(code: CurrencyCode, name: String, minorUnits: Int, symbol: String, grouping: [Int],
                wordsMajor: String, wordsMinor: String?) {
        self.code = code
        self.name = name
        self.minorUnits = minorUnits
        self.symbol = symbol
        self.grouping = grouping
        self.wordsMajor = wordsMajor
        self.wordsMinor = wordsMinor
    }
}

/// The curated currency list, in file order, with lookup by code.
public struct CurrencyCatalog: Sendable {
    public let all: [Currency]
    private let byCode: [CurrencyCode: Currency]

    public init(_ currencies: [Currency]) {
        all = currencies
        byCode = Dictionary(currencies.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public subscript(code: CurrencyCode) -> Currency? { byCode[code] }

    /// The exponent of `code`; 2 for a currency missing from the list.
    public func exponent(of code: CurrencyCode) -> Int { byCode[code]?.minorUnits ?? 2 }
}
