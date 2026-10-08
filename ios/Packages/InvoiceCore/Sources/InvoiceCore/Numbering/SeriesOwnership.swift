import Foundation

/// Numbering on several devices (`spec/sync.md` §3): a device that owns no series of a type either starts one of its
/// own (a device letter before the sequence) or takes over an existing one.
public enum SeriesOwnership {
    public enum Failure: String, Error, Sendable {
        case noDeviceLetter = "no_device_letter"
    }

    /// §3.1: the pattern and label for a new series on this device.
    public static func deviceSeriesPattern(defaultPattern: String, docType: DocumentType,
                                           existingPatterns: [String]) -> Result<(pattern: String, label: String),
                                                                                 Failure> {
        let taken = Set(existingPatterns.compactMap(letterBeforeSequence))
        guard let letter = "BCDEFGHIJKLMNOPQRSTUVWXYZ".first(where: { !taken.contains($0) }),
              let token = defaultPattern.range(of: "{seq") else {
            return .failure(.noDeviceLetter)
        }
        var pattern = defaultPattern
        pattern.insert(letter, at: token.lowerBound)
        return .success((pattern, "\(baseLabel(docType)) (\(letter))"))
    }

    /// §3.1: the new series itself.
    public static func deviceSeries(id: String, businessID: String, docType: DocumentType, config: TaxConfig,
                                    existing: [NumberingSeries], deviceID: String, now: Int64)
        -> Result<NumberingSeries, Failure> {
        let defaultPattern = docType == .quote ? config.numbering.quotePattern : config.numbering.invoicePattern
        let live = existing.filter { $0.deletedAt == nil && $0.businessId == businessID && $0.docType == docType }
        return deviceSeriesPattern(defaultPattern: defaultPattern, docType: docType,
                                   existingPatterns: live.map(\.pattern)).map { result in
            NumberingSeries(id: id, createdAt: now, updatedAt: now, businessId: businessID, docType: docType,
                            label: result.label, pattern: result.pattern, reset: config.numbering.reset,
                            ownerDeviceId: deviceID, counters: [:])
        }
    }

    /// §3.2: counters after a takeover, given the highest issued sequence per period.
    public static func takeOverCounters(_ counters: [String: Int], highest: [String: Int]) -> [String: Int] {
        var result = counters
        for (period, sequence) in highest {
            result[period] = max(counters[period] ?? 1, sequence + 1)
        }
        return result
    }

    /// §3.2: the series owned by this device, continuing after every number already issued from it.
    public static func takeOver(_ series: NumberingSeries, deviceID: String, highest: [String: Int], now: Int64)
        -> NumberingSeries {
        var taken = series
        taken.ownerDeviceId = deviceID
        taken.counters = takeOverCounters(series.counters, highest: highest)
        taken.updatedAt = now
        return taken
    }

    /// The character right before the `{seq` token when it is an uppercase letter B–Z (the original counts as A).
    static func letterBeforeSequence(_ pattern: String) -> Character? {
        guard let token = pattern.range(of: "{seq"), token.lowerBound > pattern.startIndex else { return nil }
        let before = pattern[pattern.index(before: token.lowerBound)]
        return ("B"..."Z").contains(before) ? before : nil
    }

    static func baseLabel(_ docType: DocumentType) -> String {
        docType == .quote ? "Quotes" : "Invoices"
    }
}

/// `spec/sync.md` §4: issued or void documents that share a number.
public enum DuplicateNumbers {
    public struct Row: Hashable, Sendable {
        public var id: String
        public var docType: DocumentType
        public var lifecycle: DocumentLifecycle
        public var number: String?

        public init(id: String, docType: DocumentType, lifecycle: DocumentLifecycle, number: String?) {
            self.id = id
            self.docType = docType
            self.lifecycle = lifecycle
            self.number = number
        }
    }

    public struct Group: Hashable, Sendable {
        public var docType: DocumentType
        public var number: String
        /// Sorted.
        public var ids: [String]
    }

    /// Groups of two or more, by number then type; ids sorted.
    public static func find(_ rows: [Row]) -> [Group] {
        let numbered = rows.filter { $0.lifecycle != .draft && $0.number != nil }
        let groups = Dictionary(grouping: numbered) { "\($0.docType.rawValue)\u{0}\($0.number!)" }
        return groups.values.filter { $0.count > 1 }
            .map { rows in Group(docType: rows[0].docType, number: rows[0].number!, ids: rows.map(\.id).sorted()) }
            .sorted { ($0.number, $0.docType.rawValue) < ($1.number, $1.docType.rawValue) }
    }
}
