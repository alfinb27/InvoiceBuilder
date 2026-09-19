/// When a numbering series starts again at 1. An open set, like every stored value list.
public struct NumberingReset: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let never = NumberingReset(rawValue: "never")
    public static let fiscalYear = NumberingReset(rawValue: "fiscalYear")
    public static let calendarYear = NumberingReset(rawValue: "calendarYear")
    public static let known: [NumberingReset] = [.never, .fiscalYear, .calendarYear]
}

public enum NumberingError: String, Error, Sendable {
    case numberTooLong = "number_too_long"
    case numberInvalidChars = "number_invalid_chars"
}

public struct NumberingResult: Equatable, Sendable {
    public let number: String
    public let periodKey: String
}

/// A problem with a series pattern that the settings screen reports (`spec/setup.md` §6).
public enum NumberingPatternIssue: Equatable, Sendable {
    /// No `{seq:N}` token, so every number would be the same.
    case missingSequence
    case multipleSequences
    /// A `{…}` group that is not an `ENGINE.md` §5 token (the engine would print it literally).
    case unknownToken(String)
    /// `{seq:N}` with N outside 1–9.
    case invalidSequenceWidth(String)
}

/// Invoice and quote number patterns and periods (`spec/tax/ENGINE.md` §5).
public enum Numbering {
    /// The calendar year in which the fiscal year containing `date` starts.
    public static func fiscalYearStartYear(of date: LocalDate, fiscalYearStart: MonthDay) -> Int {
        (date.month, date.day) >= (fiscalYearStart.month, fiscalYearStart.day) ? date.year : date.year - 1
    }

    /// Counter key: `all`, `FY<start year>` or `CY<year>`. A new key starts the sequence at 1.
    public static func periodKey(reset: NumberingReset, date: LocalDate, fiscalYearStart: MonthDay) -> String {
        switch reset {
        case .fiscalYear: "FY\(fiscalYearStartYear(of: date, fiscalYearStart: fiscalYearStart))"
        case .calendarYear: "CY\(date.year)"
        default: "all"
        }
    }

    /// Replaces the tokens of `pattern`; everything else is copied literally.
    public static func render(pattern: String, date: LocalDate, seq: Int, fiscalYearStart: MonthDay) -> String {
        let fy = fiscalYearStartYear(of: date, fiscalYearStart: fiscalYearStart)
        var output = ""
        for piece in tokenize(pattern) {
            switch piece {
            case .literal(let text):
                output += text
            case .token(let name, let raw):
                switch name {
                case "fy": output += twoDigits(fy) + "-" + twoDigits(fy + 1)
                case "fyLong": output += LocalDate.pad(fy, 4) + "-" + twoDigits(fy + 1)
                case "yyyy": output += LocalDate.pad(date.year, 4)
                case "yy": output += twoDigits(date.year)
                case "mm": output += LocalDate.pad(date.month, 2)
                default:
                    if let width = sequenceWidth(name) {
                        output += LocalDate.pad(seq, width) // padded to at least N digits, never truncated
                    } else {
                        output += raw
                    }
                }
            }
        }
        return output
    }

    /// Renders a number and applies the result checks: `maxLength`, then `allowedPattern`.
    public static func format(pattern: String, reset: NumberingReset, date: LocalDate, seq: Int,
                              fiscalYearStart: MonthDay, maxLength: Int?, allowedPattern: String?)
        -> Result<NumberingResult, NumberingError> {
        let number = render(pattern: pattern, date: date, seq: seq, fiscalYearStart: fiscalYearStart)
        if let maxLength, number.count > maxLength { return .failure(.numberTooLong) }
        if let allowedPattern, !SpecRegex.matches(allowedPattern, number) { return .failure(.numberInvalidChars) }
        return .success(NumberingResult(
            number: number,
            periodKey: periodKey(reset: reset, date: date, fiscalYearStart: fiscalYearStart)
        ))
    }

    /// Structural problems with a pattern (`spec/setup.md` §6); empty when the pattern is usable.
    public static func issues(inPattern pattern: String) -> [NumberingPatternIssue] {
        var issues: [NumberingPatternIssue] = []
        var sequences = 0
        for case let .token(name, raw) in tokenize(pattern) {
            if ["fy", "fyLong", "yyyy", "yy", "mm"].contains(name) { continue }
            if name.hasPrefix("seq:") {
                if let width = sequenceWidth(name), (1...9).contains(width) {
                    sequences += 1
                } else {
                    issues.append(.invalidSequenceWidth(raw))
                }
            } else {
                issues.append(.unknownToken(raw))
            }
        }
        if sequences == 0, !issues.contains(where: { if case .invalidSequenceWidth = $0 { true } else { false } }) {
            issues.insert(.missingSequence, at: 0)
        }
        if sequences > 1 { issues.append(.multipleSequences) }
        return issues
    }

    // MARK: Tokens

    enum Piece: Equatable {
        case literal(String)
        /// `name` is the text between the braces; `raw` includes them.
        case token(name: String, raw: String)
    }

    /// Splits a pattern into literal runs and `{…}` groups. A `{` without a closing `}` is literal.
    static func tokenize(_ pattern: String) -> [Piece] {
        var pieces: [Piece] = []
        var literal = ""
        var index = pattern.startIndex
        while index < pattern.endIndex {
            if pattern[index] == "{", let close = pattern[index...].firstIndex(of: "}") {
                if !literal.isEmpty { pieces.append(.literal(literal)); literal = "" }
                let name = String(pattern[pattern.index(after: index)..<close])
                pieces.append(.token(name: name, raw: String(pattern[index...close])))
                index = pattern.index(after: close)
            } else {
                literal.append(pattern[index])
                index = pattern.index(after: index)
            }
        }
        if !literal.isEmpty { pieces.append(.literal(literal)) }
        return pieces
    }

    /// `seq:4` → 4; nil unless the text after `seq:` is a plain number.
    static func sequenceWidth(_ name: String) -> Int? {
        guard name.hasPrefix("seq:") else { return nil }
        let digits = String(name.dropFirst(4))
        guard digits.isASCIIDigits, digits.count <= 2 else { return nil }
        return Int(digits)
    }

    private static func twoDigits(_ year: Int) -> String {
        LocalDate.pad(((year % 100) + 100) % 100, 2)
    }
}
