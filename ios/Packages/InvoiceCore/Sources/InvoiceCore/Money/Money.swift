/// An ISO 4217 currency code such as `INR` or `GBP`. Unknown codes are kept as they are, so data written by a newer
/// app version still round-trips.
public struct CurrencyCode: RawRepresentable, Codable, Hashable, Sendable, Comparable, CustomStringConvertible,
    ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    /// Three upper-case ASCII letters.
    public var isWellFormed: Bool {
        rawValue.utf8.count == 3 && rawValue.utf8.allSatisfy { $0 >= UInt8(ascii: "A") && $0 <= UInt8(ascii: "Z") }
    }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let inr: CurrencyCode = "INR"
    public static let gbp: CurrencyCode = "GBP"
}

/// An amount of money: integer minor units (paise, pence, …) plus its currency. Never a `Double`.
public struct Money: Codable, Hashable, Sendable {
    public var minorUnits: Int64
    public var currency: CurrencyCode

    public init(minorUnits: Int64, currency: CurrencyCode) {
        self.minorUnits = minorUnits
        self.currency = currency
    }
}
