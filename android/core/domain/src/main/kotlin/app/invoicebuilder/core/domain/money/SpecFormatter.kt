package app.invoicebuilder.core.domain.money

import app.invoicebuilder.core.domain.decimal.DecimalString
import java.time.LocalDate

/**
 * Deterministic money, percent and quantity text (`spec/tax/ENGINE.md` §7.1–7.2), identical on every platform and
 * locale. PDFs and the UI use it instead of platform number formatters. iOS: `SpecFormatter`.
 */
class SpecFormatter(val currencies: CurrencyCatalog) {
    /** `₹1,23,456.78` (home currency) or `USD 1,234.50` (any other currency); negatives as `-₹1,234.00`. */
    fun money(minor: Long, currency: CurrencyCode, homeCurrency: CurrencyCode): String {
        val info = currencies[currency]
        val exponent = info?.minorUnits ?: 2
        val grouping = info?.grouping ?: listOf(3)
        var digits = minor.toBigInteger().abs().toString()
        if (digits.length < exponent + 1) digits = "0".repeat(exponent + 1 - digits.length) + digits
        val split = digits.length - exponent
        var text = group(digits.substring(0, split), grouping)
        if (exponent > 0) text += "." + digits.substring(split)
        val prefix = if (currency == homeCurrency) (info?.symbol ?: "${currency.rawValue} ") else "${currency.rawValue} "
        return (if (minor < 0) "-" else "") + prefix + text
    }

    fun money(money: Money, homeCurrency: CurrencyCode): String = money(money.minorUnits, money.currency, homeCurrency)

    companion object {
        /** `"18.00"` → `18%`. Text that is not a spec decimal string is shown as typed. */
        fun percent(value: String): String = (DecimalString.canonical(value) ?: value) + "%"

        /** `"1.500"` → `1.5`. Text that is not a spec decimal string is shown as typed. */
        fun quantity(value: String): String = DecimalString.canonical(value) ?: value

        private val months = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

        /** `19 Sep 2026` (`spec/pdf/RENDERING.md` §1.4). */
        fun date(date: LocalDate): String = "${date.dayOfMonth} ${months[date.monthValue - 1]} ${date.year}"

        /** Groups integer digits from the right: first group `sizes[0]`, then the last size repeatedly. */
        fun group(integer: String, sizes: List<Int>): String {
            val first = sizes.firstOrNull() ?: return integer
            if (first <= 0) return integer
            val repeating = maxOf(sizes.lastOrNull() ?: first, 1)
            val groups = mutableListOf<String>()
            var end = integer.length
            var size = first
            while (end > size) {
                groups += integer.substring(end - size, end)
                end -= size
                size = repeating
            }
            groups += integer.substring(0, end)
            return groups.reversed().joinToString(",")
        }
    }
}
