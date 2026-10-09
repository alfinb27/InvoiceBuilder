package app.invoicebuilder.core.domain.numbering

import app.invoicebuilder.core.domain.dates.MonthDay
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.support.SpecRegex
import app.invoicebuilder.core.domain.support.isAsciiDigits
import kotlinx.serialization.Serializable
import java.time.LocalDate

/** When a numbering series starts again at 1. An open set, like every stored value list. */
@Serializable
@JvmInline
value class NumberingReset(val rawValue: String) {
    companion object {
        val never = NumberingReset("never")
        val fiscalYear = NumberingReset("fiscalYear")
        val calendarYear = NumberingReset("calendarYear")
        val known = listOf(never, fiscalYear, calendarYear)
    }
}

enum class NumberingError(val rawValue: String) {
    NumberTooLong("number_too_long"), NumberInvalidChars("number_invalid_chars")
}

data class NumberingResult(val number: String, val periodKey: String)

/** A problem with a series pattern that the settings screen reports (`spec/setup.md` §6). */
sealed interface NumberingPatternIssue {
    data object MissingSequence : NumberingPatternIssue
    data object MultipleSequences : NumberingPatternIssue
    data class UnknownToken(val raw: String) : NumberingPatternIssue
    data class InvalidSequenceWidth(val raw: String) : NumberingPatternIssue
}

/** Invoice and quote number patterns and periods (`spec/tax/ENGINE.md` §5). iOS: `Numbering`. */
object Numbering {
    /** The calendar year in which the fiscal year containing [date] starts. */
    fun fiscalYearStartYear(date: LocalDate, fiscalYearStart: MonthDay): Int =
        if (MonthDay(date.monthValue, date.dayOfMonth) >= fiscalYearStart) date.year else date.year - 1

    /** Counter key: `all`, `FY<start year>` or `CY<year>`. A new key starts the sequence at 1. */
    fun periodKey(reset: NumberingReset, date: LocalDate, fiscalYearStart: MonthDay): String = when (reset) {
        NumberingReset.fiscalYear -> "FY${fiscalYearStartYear(date, fiscalYearStart)}"
        NumberingReset.calendarYear -> "CY${date.year}"
        else -> "all"
    }

    /** Replaces the tokens of [pattern]; everything else is copied literally. */
    fun render(pattern: String, date: LocalDate, seq: Int, fiscalYearStart: MonthDay): String {
        val fy = fiscalYearStartYear(date, fiscalYearStart)
        val output = StringBuilder()
        for (piece in tokenize(pattern)) {
            when (piece) {
                is Piece.Literal -> output.append(piece.text)
                is Piece.Token -> when (piece.name) {
                    "fy" -> output.append(twoDigits(fy)).append('-').append(twoDigits(fy + 1))
                    "fyLong" -> output.append(pad(fy, 4)).append('-').append(twoDigits(fy + 1))
                    "yyyy" -> output.append(pad(date.year, 4))
                    "yy" -> output.append(twoDigits(date.year))
                    "mm" -> output.append(pad(date.monthValue, 2))
                    else -> {
                        val width = sequenceWidth(piece.name)
                        // padded to at least N digits, never truncated
                        if (width != null) output.append(pad(seq, width)) else output.append(piece.raw)
                    }
                }
            }
        }
        return output.toString()
    }

    /** Renders a number and applies the result checks: `maxLength`, then `allowedPattern`. */
    fun format(
        pattern: String, reset: NumberingReset, date: LocalDate, seq: Int, fiscalYearStart: MonthDay,
        maxLength: Int?, allowedPattern: String?,
    ): Outcome<NumberingResult, NumberingError> {
        val number = render(pattern, date, seq, fiscalYearStart)
        if (maxLength != null && number.codePointCount(0, number.length) > maxLength) {
            return Outcome.Failure(NumberingError.NumberTooLong)
        }
        if (allowedPattern != null && !SpecRegex.matches(allowedPattern, number)) {
            return Outcome.Failure(NumberingError.NumberInvalidChars)
        }
        return Outcome.Success(NumberingResult(number, periodKey(reset, date, fiscalYearStart)))
    }

    /** Structural problems with a pattern (`spec/setup.md` §6); empty when the pattern is usable. */
    fun issues(pattern: String): List<NumberingPatternIssue> {
        val issues = mutableListOf<NumberingPatternIssue>()
        var sequences = 0
        for (piece in tokenize(pattern)) {
            if (piece !is Piece.Token) continue
            if (piece.name in listOf("fy", "fyLong", "yyyy", "yy", "mm")) continue
            if (piece.name.startsWith("seq:")) {
                val width = sequenceWidth(piece.name)
                if (width != null && width in 1..9) sequences++ else issues += NumberingPatternIssue.InvalidSequenceWidth(piece.raw)
            } else {
                issues += NumberingPatternIssue.UnknownToken(piece.raw)
            }
        }
        if (sequences == 0 && issues.none { it is NumberingPatternIssue.InvalidSequenceWidth }) {
            issues.add(0, NumberingPatternIssue.MissingSequence)
        }
        if (sequences > 1) issues += NumberingPatternIssue.MultipleSequences
        return issues
    }

    sealed interface Piece {
        data class Literal(val text: String) : Piece
        /** [name] is the text between the braces; [raw] includes them. */
        data class Token(val name: String, val raw: String) : Piece
    }

    /** Splits a pattern into literal runs and `{…}` groups. A `{` without a closing `}` is literal. */
    fun tokenize(pattern: String): List<Piece> {
        val pieces = mutableListOf<Piece>()
        val literal = StringBuilder()
        var index = 0
        while (index < pattern.length) {
            val close = if (pattern[index] == '{') pattern.indexOf('}', index) else -1
            if (close >= 0) {
                if (literal.isNotEmpty()) { pieces += Piece.Literal(literal.toString()); literal.clear() }
                pieces += Piece.Token(pattern.substring(index + 1, close), pattern.substring(index, close + 1))
                index = close + 1
            } else {
                literal.append(pattern[index])
                index++
            }
        }
        if (literal.isNotEmpty()) pieces += Piece.Literal(literal.toString())
        return pieces
    }

    /** `seq:4` → 4; null unless the text after `seq:` is a plain number. */
    fun sequenceWidth(name: String): Int? {
        if (!name.startsWith("seq:")) return null
        val digits = name.substring(4)
        if (!digits.isAsciiDigits || digits.length > 2) return null
        return digits.toInt()
    }

    fun pad(value: Int, width: Int): String {
        val text = value.toString()
        return if (text.length >= width) text else "0".repeat(width - text.length) + text
    }

    private fun twoDigits(year: Int): String = pad(((year % 100) + 100) % 100, 2)
}
