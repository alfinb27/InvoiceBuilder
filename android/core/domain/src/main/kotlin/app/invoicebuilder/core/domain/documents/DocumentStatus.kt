package app.invoicebuilder.core.domain.documents

import app.invoicebuilder.core.domain.models.DocumentType
import kotlinx.serialization.Serializable
import java.time.LocalDate

/** A document's stored lifecycle. Display status is derived from it ([DocumentStatus]), never stored. */
@Serializable
@JvmInline
value class DocumentLifecycle(val rawValue: String) {
    companion object {
        val draft = DocumentLifecycle("draft")
        val issued = DocumentLifecycle("issued")
        val void = DocumentLifecycle("void")
    }
}

/** What the customer decided about a quote. An open set. */
@Serializable
@JvmInline
value class QuoteOutcome(val rawValue: String) {
    companion object {
        val accepted = QuoteOutcome("accepted")
        val declined = QuoteOutcome("declined")
        val converted = QuoteOutcome("converted")
    }
}

/** Derived display status (`spec/tax/ENGINE.md` §6). No background job ever flips a stored status. */
enum class DocumentStatus {
    draft, issued, sent, partiallyPaid, paid, overdue, void, open, accepted, declined, expired, converted;

    val rawValue: String get() = name

    data class Input(
        val docType: DocumentType,
        val lifecycle: DocumentLifecycle,
        val total: Long,
        val paid: Long = 0,
        val dueDate: LocalDate? = null,
        val validUntil: LocalDate? = null,
        val sentAt: Long? = null,
        val outcome: QuoteOutcome? = null,
        val today: LocalDate,
    )

    companion object {
        fun of(rawValue: String): DocumentStatus? = entries.firstOrNull { it.name == rawValue }

        /**
         * First match wins. Invoice: void · draft · paid · overdue · partiallyPaid · sent · issued.
         * Quote: void · draft · converted/accepted/declined · expired · sent · open.
         */
        fun derive(input: Input): DocumentStatus {
            if (input.lifecycle == DocumentLifecycle.void) return void
            if (input.lifecycle == DocumentLifecycle.draft) return draft
            if (input.docType == DocumentType.quote) {
                when (input.outcome) {
                    QuoteOutcome.converted -> return converted
                    QuoteOutcome.accepted -> return accepted
                    QuoteOutcome.declined -> return declined
                    else -> {}
                }
                if (input.validUntil != null && input.today > input.validUntil) return expired
                return if (input.sentAt != null) sent else open
            }
            if (input.paid >= input.total) return paid
            if (input.dueDate != null && input.today > input.dueDate) return overdue
            if (input.paid > 0) return partiallyPaid
            return if (input.sentAt != null) sent else issued
        }

        /** `max(total − paid, 0)` for invoices; null for quotes. */
        fun outstanding(input: Input): Long? =
            if (input.docType == DocumentType.quote) null else maxOf(input.total - input.paid, 0)
    }
}
