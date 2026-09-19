import Foundation

/// A calendar date with no time or time zone (`YYYY-MM-DD`), mirroring `java.time.LocalDate` on Android.
/// Invoice, supply and due dates, rate effective dates and config versions are all `LocalDate`s.
public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Nil unless the date exists in the proleptic Gregorian calendar (years 1–9999).
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...Self.daysInMonth(year: year, month: month)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Strict `YYYY-MM-DD`.
    public init?(iso: String) {
        let bytes = Array(iso.utf8)
        guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"),
              let year = Self.number(bytes[0..<4]), let month = Self.number(bytes[5..<7]),
              let day = Self.number(bytes[8..<10]) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// `YYYY-MM-DD`.
    public var iso: String {
        Self.pad(year, 4) + "-" + Self.pad(month, 2) + "-" + Self.pad(day, 2)
    }

    public var description: String { iso }

    /// Today in `timeZone` (the device's by default).
    public static func today(in timeZone: TimeZone = .current, at instant: Date = Date()) -> LocalDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return LocalDate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
            ?? LocalDate(daysSinceEpoch: 0)
    }

    // MARK: Arithmetic (days since 1970-01-01, Howard Hinnant's civil-date algorithms)

    public var daysSinceEpoch: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    public init(daysSinceEpoch days: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        day = dayOfYear - (153 * mp + 2) / 5 + 1
        month = mp < 10 ? mp + 3 : mp - 9
        year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(daysSinceEpoch: daysSinceEpoch + days)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    // MARK: Codable as the ISO string

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = LocalDate(iso: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a YYYY-MM-DD date: \(text)")
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }

    private static func number(_ bytes: ArraySlice<UInt8>) -> Int? {
        var value = 0
        for byte in bytes {
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
        }
        return value
    }

    static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return text.count >= width ? text : String(repeating: "0", count: width - text.count) + text
    }
}

/// A month and day without a year (`MM-DD`), e.g. a fiscal year start (`04-01` in India, `04-06` in the UK).
public struct MonthDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let month: Int
    public let day: Int

    public init?(month: Int, day: Int) {
        guard (1...12).contains(month), (1...LocalDate.daysInMonth(year: 2000, month: month)).contains(day) else {
            return nil
        }
        self.month = month
        self.day = day
    }

    /// Strict `MM-DD`.
    public init?(text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].utf8.count == 2, parts[1].utf8.count == 2,
              let month = Int(parts[0]), let day = Int(parts[1]) else { return nil }
        self.init(month: month, day: day)
    }

    public var description: String { LocalDate.pad(month, 2) + "-" + LocalDate.pad(day, 2) }

    public static func < (lhs: MonthDay, rhs: MonthDay) -> Bool { (lhs.month, lhs.day) < (rhs.month, rhs.day) }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = MonthDay(text: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an MM-DD value: \(text)")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
