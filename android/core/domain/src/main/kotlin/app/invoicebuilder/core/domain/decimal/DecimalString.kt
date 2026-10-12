package app.invoicebuilder.core.domain.decimal

import java.math.BigDecimal

/**
 * Decimal strings as stored in JSON and SQLite (rates, quantities, exchange rates):
 * `^-?(0|[1-9][0-9]*)(\.[0-9]+)?$` (`spec/tax/ENGINE.md` §1). iOS: `DecimalString`.
 *
 * Parse with these helpers, never with `BigDecimal(String)` directly: it accepts exponents such as `"1E+3"`.
 */
object DecimalString {
    private val pattern = Regex("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?$")

    /** True when [text] is a spec decimal string. */
    fun isValid(text: String): Boolean = pattern.matches(text)

    /** The value of a spec decimal string, or null for anything else. */
    fun parse(text: String): BigDecimal? = if (isValid(text)) BigDecimal(text) else null

    /**
     * Canonical form (`ENGINE.md` §7.2): trailing fractional zeros and a trailing "." dropped
     * (`"18.00"` → `"18"`, `"8.8750"` → `"8.875"`). Null when [text] is not a spec decimal string.
     */
    fun canonical(text: String): String? {
        if (!isValid(text)) return null
        if (!text.contains('.')) return if (text == "-0") "0" else text
        val trimmed = text.trimEnd('0').trimEnd('.')
        return if (trimmed == "-0") "0" else trimmed
    }

    /** The canonical decimal string of a value (no exponent notation, no trailing zeros). */
    fun string(value: BigDecimal): String {
        val plain = value.stripTrailingZeros().toPlainString()
        return canonical(plain) ?: plain
    }
}
