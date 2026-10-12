package app.invoicebuilder.core.domain.setup

import app.invoicebuilder.core.domain.decimal.InputError
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.models.NumberingSeries
import app.invoicebuilder.core.domain.numbering.Numbering
import app.invoicebuilder.core.domain.numbering.NumberingError
import app.invoicebuilder.core.domain.numbering.NumberingReset
import app.invoicebuilder.core.domain.numbering.NumberingResult
import app.invoicebuilder.core.domain.support.isAsciiDigits
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.TaxConfig
import java.time.LocalDate

enum class NumberingSeriesField { Label, Pattern, NextNumber }

/** A numbering series being edited in Settings (`spec/setup.md` §6). iOS: `NumberingSeriesDraft`. */
data class NumberingSeriesDraft(val label: String, val pattern: String, val reset: NumberingReset, val nextNumberText: String) {
    companion object {
        fun of(series: NumberingSeries, periodKey: String) =
            NumberingSeriesDraft(series.label, series.pattern, series.reset, series.nextSequence(periodKey).toString())
    }
}

/** iOS: `NumberingSeriesRules`. */
class NumberingSeriesRules(val config: TaxConfig, val today: LocalDate, val deviceID: String) {
    /** Only the owner device edits a series (ADR-0015). */
    fun isEditable(series: NumberingSeries): Boolean = series.ownerDeviceId == deviceID

    fun periodKey(reset: NumberingReset): String = Numbering.periodKey(reset, today, config.fiscalYearStart)

    /** The next number for today, as it would be issued. */
    fun nextNumber(series: NumberingSeries): Outcome<NumberingResult, NumberingError> =
        preview(series.pattern, series.reset, series.nextSequence(periodKey(series.reset)))

    fun preview(draft: NumberingSeriesDraft): Outcome<NumberingResult, NumberingError>? {
        val seq = draft.nextNumberText.trim().toIntOrNull()?.takeIf { it >= 1 } ?: return null
        return preview(draft.pattern, draft.reset, seq)
    }

    /** [highestIssued]: the highest sequence already issued from the series in the draft's current period. */
    fun issues(draft: NumberingSeriesDraft, highestIssued: Int? = null): Map<NumberingSeriesField, FieldIssue> {
        val issues = mutableMapOf<NumberingSeriesField, FieldIssue>()
        if (draft.label.trimmedOrNull == null) issues[NumberingSeriesField.Label] = FieldIssue.Required
        val patternIssues = Numbering.issues(draft.pattern)
        if (patternIssues.isNotEmpty()) {
            issues[NumberingSeriesField.Pattern] = FieldIssue.InvalidPattern(patternIssues)
        } else {
            (preview(draft) as? Outcome.Failure)?.let { issues[NumberingSeriesField.Pattern] = FieldIssue.InvalidNumbering(it.error) }
        }
        val next = draft.nextNumberText.trim()
        when {
            next.isEmpty() -> issues[NumberingSeriesField.NextNumber] = FieldIssue.Required
            !next.isAsciiDigits || (next.toIntOrNull() ?: 0) < 1 || next.length > 9 ->
                issues[NumberingSeriesField.NextNumber] = FieldIssue.InvalidNumber(InputError.Invalid)
            highestIssued != null && next.toInt() <= highestIssued ->
                issues[NumberingSeriesField.NextNumber] = FieldIssue.AlreadyIssued(highestIssued)
        }
        return issues
    }

    /** The series with the draft applied; the next number is written to the counter of today's period. */
    fun updating(series: NumberingSeries, draft: NumberingSeriesDraft): NumberingSeries {
        val next = draft.nextNumberText.trim().toIntOrNull()?.takeIf { it >= 1 }
        return series.copy(
            label = draft.label.trimmedOrNull ?: series.label, pattern = draft.pattern, reset = draft.reset,
            counters = if (next != null) series.counters + (periodKey(draft.reset) to next) else series.counters,
        )
    }

    fun preview(pattern: String, reset: NumberingReset, seq: Int): Outcome<NumberingResult, NumberingError> =
        Numbering.format(pattern, reset, today, seq, config.fiscalYearStart, config.numbering.maxLength, config.numbering.allowedPattern)
}
