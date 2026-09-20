/// A document's stored lifecycle. Display status is derived from it (`DocumentStatus`), never stored.
/// An open set, like every stored value list.
public struct DocumentLifecycle: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let draft = DocumentLifecycle(rawValue: "draft")
    public static let issued = DocumentLifecycle(rawValue: "issued")
    public static let void = DocumentLifecycle(rawValue: "void")
}

/// What the customer decided about a quote. An open set.
public struct QuoteOutcome: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let accepted = QuoteOutcome(rawValue: "accepted")
    public static let declined = QuoteOutcome(rawValue: "declined")
    public static let converted = QuoteOutcome(rawValue: "converted")
}

/// Derived display status (`spec/tax/ENGINE.md` §6). No background job ever flips a stored status.
public enum DocumentStatus: String, Sendable, CaseIterable {
    case draft, issued, sent, partiallyPaid, paid, overdue, void
    case open, accepted, declined, expired, converted

    public struct Input: Sendable {
        public var docType: DocumentType
        public var lifecycle: DocumentLifecycle
        public var total: Int64
        public var paid: Int64
        public var dueDate: LocalDate?
        public var validUntil: LocalDate?
        public var sentAt: Int64?
        public var outcome: QuoteOutcome?
        public var today: LocalDate

        public init(docType: DocumentType, lifecycle: DocumentLifecycle, total: Int64, paid: Int64 = 0,
                    dueDate: LocalDate? = nil, validUntil: LocalDate? = nil, sentAt: Int64? = nil,
                    outcome: QuoteOutcome? = nil, today: LocalDate) {
            self.docType = docType
            self.lifecycle = lifecycle
            self.total = total
            self.paid = paid
            self.dueDate = dueDate
            self.validUntil = validUntil
            self.sentAt = sentAt
            self.outcome = outcome
            self.today = today
        }
    }

    /// First match wins. Invoice: void · draft · paid · overdue · partiallyPaid · sent · issued.
    /// Quote: void · draft · converted/accepted/declined · expired · sent · open.
    public static func derive(_ input: Input) -> DocumentStatus {
        if input.lifecycle == .void { return .void }
        if input.lifecycle == .draft { return .draft }
        if input.docType == .quote {
            switch input.outcome {
            case .converted?: return .converted
            case .accepted?: return .accepted
            case .declined?: return .declined
            default: break
            }
            if let validUntil = input.validUntil, input.today > validUntil { return .expired }
            return input.sentAt != nil ? .sent : .open
        }
        if input.paid >= input.total { return .paid }
        if let dueDate = input.dueDate, input.today > dueDate { return .overdue }
        if input.paid > 0 { return .partiallyPaid }
        return input.sentAt != nil ? .sent : .issued
    }

    /// `max(total − paid, 0)` for invoices; nil for quotes.
    public static func outstanding(_ input: Input) -> Int64? {
        input.docType == .quote ? nil : max(input.total - input.paid, 0)
    }
}
