package app.invoicebuilder.core.domain.numbering

import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.models.NumberingSeries
import app.invoicebuilder.core.domain.tax.TaxConfig
import java.time.LocalDate

/** Allocates a document number at issue (`spec/documents.md` §6 steps 4–5, `ENGINE.md` §5). iOS: `NumberAllocator`. */
object NumberAllocator {
    data class Allocation(
        val number: String,
        val periodKey: String,
        val sequence: Int,
        /** The series with `counters[periodKey] = sequence + 1`, ready to be stored in the same transaction. */
        val series: NumberingSeries,
    )

    /** The series this device issues [docType] from: live, owned by [deviceID], earliest created, then lowest id. */
    fun series(docType: DocumentType, deviceID: String, candidates: List<NumberingSeries>): NumberingSeries? =
        candidates.filter { it.deletedAt == null && it.docType == docType && it.ownerDeviceId == deviceID }
            .minWithOrNull(compareBy<NumberingSeries>({ it.createdAt }, { it.id }))

    /** The next number of [series] for a document issued on [issueDate]. */
    fun allocate(series: NumberingSeries, issueDate: LocalDate, config: TaxConfig): Outcome<Allocation, NumberingError> {
        val periodKey = Numbering.periodKey(series.reset, issueDate, config.fiscalYearStart)
        val sequence = series.nextSequence(periodKey)
        return when (val formatted = Numbering.format(
            series.pattern, series.reset, issueDate, sequence, config.fiscalYearStart, config.numbering.maxLength,
            config.numbering.allowedPattern,
        )) {
            is Outcome.Failure -> formatted
            is Outcome.Success -> Outcome.Success(
                Allocation(formatted.value.number, formatted.value.periodKey, sequence,
                    series.copy(counters = series.counters + (periodKey to sequence + 1))),
            )
        }
    }
}
