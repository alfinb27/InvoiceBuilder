package app.invoicebuilder.core.domain.documents

import app.invoicebuilder.core.domain.money.CurrencyCatalog
import app.invoicebuilder.core.domain.money.CurrencyCode

/**
 * Amounts in words for invoices (`spec/tax/ENGINE.md` §7.3):
 * `{wordsMajor} {words(major)}[ and {words(minor)} {wordsMinor}] Only`, Indian lakh/crore grouping for INR and
 * billion/million elsewhere. iOS: `AmountInWords`.
 */
object AmountInWords {
    fun text(minor: Long, currency: CurrencyCode, currencies: CurrencyCatalog): String {
        val info = currencies[currency]
        val exponent = info?.minorUnits ?: 2
        val magnitude = minor.toBigInteger().abs()
        val divisor = java.math.BigInteger.TEN.pow(exponent)
        val major = magnitude / divisor
        val fraction = magnitude % divisor
        val indian = currency == CurrencyCode.INR
        var text = (info?.wordsMajor ?: currency.rawValue) + " " + words(major.toLong(), indian)
        if (exponent > 0 && fraction.signum() > 0) {
            text += " and " + words(fraction.toLong(), indian)
            info?.wordsMinor?.let { text += " $it" }
        }
        return "$text Only"
    }

    /** Title Case words joined by single spaces, no "and" or hyphens inside numbers: `Twenty One`, `One Lakh`. */
    fun words(value: Long, indian: Boolean): String {
        if (value <= 0) return "Zero"
        val scales = if (indian) {
            listOf(10_000_000L to "Crore", 100_000L to "Lakh", 1000L to "Thousand", 100L to "Hundred")
        } else {
            listOf(1_000_000_000L to "Billion", 1_000_000L to "Million", 1000L to "Thousand", 100L to "Hundred")
        }
        val parts = mutableListOf<String>()
        var rest = value
        for ((size, name) in scales) {
            if (rest < size) continue
            // The count may itself be large (≥ 100 crore, ≥ 1000 billion): it recurses.
            parts += words(rest / size, indian) + " " + name
            rest %= size
        }
        if (rest > 0) parts += belowHundred(rest.toInt())
        return parts.joinToString(" ")
    }

    private val units = listOf(
        "", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve",
        "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen",
    )
    private val tens = listOf("", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety")

    private fun belowHundred(value: Int): String =
        if (value < 20) units[value] else if (value % 10 == 0) tens[value / 10] else tens[value / 10] + " " + units[value % 10]
}
