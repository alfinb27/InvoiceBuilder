/// An invoice considered for a reminder (`spec/reminders.md` §2): callers pass only live, issued invoices; `status`
/// is defensive (never scheduled unless it is one of the "still owed" statuses below).
public struct ReminderCandidate: Hashable, Sendable {
    public var documentId: String
    public var dueDate: LocalDate?
    /// `document.reminderDaysAfterDueOverride`; nil defers to the business default.
    public var overrideDays: Int?
    public var status: DocumentStatus

    public init(documentId: String, dueDate: LocalDate?, overrideDays: Int?, status: DocumentStatus) {
        self.documentId = documentId
        self.dueDate = dueDate
        self.overrideDays = overrideDays
        self.status = status
    }
}

/// One local notification to schedule.
public struct ScheduledReminder: Hashable, Sendable {
    public var documentId: String
    public var remindOn: LocalDate

    public init(documentId: String, remindOn: LocalDate) {
        self.documentId = documentId
        self.remindOn = remindOn
    }
}

/// `spec/reminders.md` §3, proven by `fixtures/reminders/*.json` (kind `reminder`).
public enum ReminderScheduler {
    /// For each eligible candidate, `remindOn = dueDate + effectiveDays` (plain calendar-day addition). Eligible:
    /// one of the "still owed" statuses, a due date, and a non-nil effective days (`overrideDays ?? businessDefaultDays`).
    /// Dates before `from` are dropped, then the rest are sorted by `remindOn` ascending (ties by `documentId`) and
    /// truncated to the first `cap`, so a date that has already passed never takes one of the `cap` places.
    public static func plan(businessDefaultDays: Int?, cap: Int, candidates: [ReminderCandidate],
                            from: LocalDate) -> [ScheduledReminder] {
        let scheduled = candidates.compactMap { candidate -> ScheduledReminder? in
            guard isEligible(candidate.status), let dueDate = candidate.dueDate,
                  let days = candidate.overrideDays ?? businessDefaultDays else { return nil }
            let remindOn = dueDate.adding(days: days)
            guard remindOn >= from else { return nil }
            return ScheduledReminder(documentId: candidate.documentId, remindOn: remindOn)
        }
        return scheduled.sorted { lhs, rhs in
            lhs.remindOn == rhs.remindOn ? lhs.documentId < rhs.documentId : lhs.remindOn < rhs.remindOn
        }.prefix(max(cap, 0)).map { $0 }
    }

    /// An invoice still owed: not a draft (never issued), not paid, not void.
    static func isEligible(_ status: DocumentStatus) -> Bool {
        switch status {
        case .issued, .sent, .overdue, .partiallyPaid: true
        case .draft, .paid, .void, .open, .accepted, .declined, .expired, .converted: false
        }
    }
}
