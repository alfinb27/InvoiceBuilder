import Foundation

public enum NumberingSeriesField: Hashable, Sendable {
    case label, pattern, nextNumber
}

/// A numbering series being edited in Settings (`spec/setup.md` §6).
public struct NumberingSeriesDraft: Equatable, Sendable {
    public var label: String
    public var pattern: String
    public var reset: NumberingReset
    public var nextNumberText: String

    public init(series: NumberingSeries, periodKey: String) {
        label = series.label
        pattern = series.pattern
        reset = series.reset
        nextNumberText = String(series.nextSequence(periodKey: periodKey))
    }
}

public struct NumberingSeriesRules: Sendable {
    public let config: TaxConfig
    public let today: LocalDate
    public let deviceID: String

    public init(config: TaxConfig, today: LocalDate, deviceID: String) {
        self.config = config
        self.today = today
        self.deviceID = deviceID
    }

    /// Only the owner device edits a series (ADR-0015).
    public func isEditable(_ series: NumberingSeries) -> Bool { series.ownerDeviceId == deviceID }

    public func periodKey(reset: NumberingReset) -> String {
        Numbering.periodKey(reset: reset, date: today, fiscalYearStart: config.fiscalYearStart)
    }

    /// The next number for today, as it would be issued.
    public func nextNumber(_ series: NumberingSeries) -> Result<NumberingResult, NumberingError> {
        preview(pattern: series.pattern, reset: series.reset,
                seq: series.nextSequence(periodKey: periodKey(reset: series.reset)))
    }

    public func preview(_ draft: NumberingSeriesDraft) -> Result<NumberingResult, NumberingError>? {
        guard let seq = Int(draft.nextNumberText.trimmingCharacters(in: .whitespaces)), seq >= 1 else { return nil }
        return preview(pattern: draft.pattern, reset: draft.reset, seq: seq)
    }

    /// `highestIssued`: the highest sequence already issued from the series in the draft's current period.
    public func issues(_ draft: NumberingSeriesDraft, highestIssued: Int? = nil) -> [NumberingSeriesField: FieldIssue] {
        var issues: [NumberingSeriesField: FieldIssue] = [:]
        if draft.label.trimmedOrNil == nil { issues[.label] = .required }
        let patternIssues = Numbering.issues(inPattern: draft.pattern)
        if !patternIssues.isEmpty {
            issues[.pattern] = .invalidPattern(patternIssues)
        } else if case .failure(let error)? = preview(draft) {
            issues[.pattern] = .invalidNumbering(error)
        }
        let next = draft.nextNumberText.trimmingCharacters(in: .whitespaces)
        if next.isEmpty {
            issues[.nextNumber] = .required
        } else if !next.isASCIIDigits || (Int(next) ?? 0) < 1 || next.count > 9 {
            issues[.nextNumber] = .invalidNumber(.invalid)
        } else if let highestIssued, let value = Int(next), value <= highestIssued {
            issues[.nextNumber] = .alreadyIssued(highest: highestIssued)
        }
        return issues
    }

    /// The series with the draft applied; the next number is written to the counter of today's period.
    public func updating(_ series: NumberingSeries, from draft: NumberingSeriesDraft) -> NumberingSeries {
        var updated = series
        updated.label = draft.label.trimmedOrNil ?? series.label
        updated.pattern = draft.pattern
        updated.reset = draft.reset
        if let next = Int(draft.nextNumberText.trimmingCharacters(in: .whitespaces)), next >= 1 {
            updated.counters[periodKey(reset: draft.reset)] = next
        }
        return updated
    }

    private func preview(pattern: String, reset: NumberingReset, seq: Int) -> Result<NumberingResult, NumberingError> {
        Numbering.format(pattern: pattern, reset: reset, date: today, seq: seq,
                         fiscalYearStart: config.fiscalYearStart, maxLength: config.numbering.maxLength,
                         allowedPattern: config.numbering.allowedPattern)
    }
}
