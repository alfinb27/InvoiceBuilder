/// Allocates a document number at issue (`spec/documents.md` §6 steps 4–5, `ENGINE.md` §5).
public enum NumberAllocator {
    public struct Allocation: Equatable, Sendable {
        public let number: String
        public let periodKey: String
        public let sequence: Int
        /// The series with `counters[periodKey] = sequence + 1`, ready to be stored in the same transaction.
        public let series: NumberingSeries
    }

    /// The series this device issues `docType` from: live, owned by `deviceID`, earliest created, then lowest id
    /// (ADR-0015: only the owner device advances a series).
    public static func series(for docType: DocumentType, deviceID: String, among candidates: [NumberingSeries])
        -> NumberingSeries? {
        candidates
            .filter { $0.deletedAt == nil && $0.docType == docType && $0.ownerDeviceId == deviceID }
            .min { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// The next number of `series` for a document issued on `issueDate`.
    public static func allocate(from series: NumberingSeries, issueDate: LocalDate, config: TaxConfig)
        -> Result<Allocation, NumberingError> {
        let periodKey = Numbering.periodKey(reset: series.reset, date: issueDate,
                                            fiscalYearStart: config.fiscalYearStart)
        let sequence = series.nextSequence(periodKey: periodKey)
        let formatted = Numbering.format(pattern: series.pattern, reset: series.reset, date: issueDate, seq: sequence,
                                         fiscalYearStart: config.fiscalYearStart,
                                         maxLength: config.numbering.maxLength,
                                         allowedPattern: config.numbering.allowedPattern)
        return formatted.map { result in
            var updated = series
            updated.counters[periodKey] = sequence + 1
            return Allocation(number: result.number, periodKey: result.periodKey, sequence: sequence, series: updated)
        }
    }
}
