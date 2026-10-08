package app.invoicebuilder.core.domain.documents

import java.time.LocalDate

/** An invoice considered for a reminder (`spec/reminders.md` §2). iOS: `ReminderCandidate`. */
data class ReminderCandidate(
    val documentId: String,
    val dueDate: LocalDate?,
    /** `document.reminderDaysAfterDueOverride`; null defers to the business default. */
    val overrideDays: Int?,
    val status: DocumentStatus,
)

/** One local notification (Android: one notification from the daily worker). */
data class ScheduledReminder(val documentId: String, val remindOn: LocalDate)

/** `spec/reminders.md` §3, proven by `fixtures/reminders/<file>.json` (kind `reminder`). iOS: `ReminderScheduler`. */
object ReminderScheduler {
    /**
     * For each eligible candidate, `remindOn = dueDate + effectiveDays`. Eligible: one of the "still owed" statuses,
     * a due date, and a non-null effective days (`overrideDays ?: businessDefaultDays`). Sorted by `remindOn`
     * ascending (ties by `documentId`), truncated to the first [cap].
     */
    fun plan(businessDefaultDays: Int?, cap: Int, candidates: List<ReminderCandidate>): List<ScheduledReminder> =
        candidates.mapNotNull { candidate ->
            val dueDate = candidate.dueDate ?: return@mapNotNull null
            val days = candidate.overrideDays ?: businessDefaultDays ?: return@mapNotNull null
            if (!isEligible(candidate.status)) return@mapNotNull null
            ScheduledReminder(candidate.documentId, dueDate.plusDays(days.toLong()))
        }.sortedWith(compareBy<ScheduledReminder>({ it.remindOn }, { it.documentId })).take(maxOf(cap, 0))

    /** An invoice still owed: not a draft (never issued), not paid, not void. */
    fun isEligible(status: DocumentStatus): Boolean = when (status) {
        DocumentStatus.issued, DocumentStatus.sent, DocumentStatus.overdue, DocumentStatus.partiallyPaid -> true
        else -> false
    }
}
