package app.invoicebuilder.core.domain.money

import kotlinx.serialization.Serializable

/**
 * An ISO 4217 currency code such as `INR` or `GBP`. Unknown codes are kept as they are, so data written by a newer
 * app version still round-trips. A value class ≈ Swift's `RawRepresentable` struct: serialized as its string.
 */
@Serializable
@JvmInline
value class CurrencyCode(val rawValue: String) : Comparable<CurrencyCode> {
    /** Three upper-case ASCII letters. */
    val isWellFormed: Boolean get() = rawValue.length == 3 && rawValue.all { it in 'A'..'Z' }

    override fun compareTo(other: CurrencyCode): Int = rawValue.compareTo(other.rawValue)
    override fun toString(): String = rawValue

    companion object {
        val INR = CurrencyCode("INR")
        val GBP = CurrencyCode("GBP")
    }
}

/** An amount of money: integer minor units (paise, pence, …) plus its currency. Never a `Double`. */
@Serializable
data class Money(val minorUnits: Long, val currency: CurrencyCode)

/** One entry of `spec/reference/currencies.json`. */
@Serializable
data class Currency(
    val code: CurrencyCode,
    val name: String,
    /** ISO 4217 exponent: INR/GBP 2, JPY 0, KWD 3. */
    val minorUnits: Int,
    /** Shown only when the currency is the business home currency; otherwise documents show the ISO code. */
    val symbol: String,
    /** Digit group sizes from the right: INR `[3, 2]` → `1,23,45,678`. */
    val grouping: List<Int>,
    val wordsMajor: String,
    val wordsMinor: String? = null,
)

/** The curated currency list, in file order, with lookup by code. */
class CurrencyCatalog(val all: List<Currency>) {
    private val byCode = all.reversed().associateBy { it.code } // the first entry wins, as on iOS

    operator fun get(code: CurrencyCode): Currency? = byCode[code]

    /** The exponent of [code]; 2 for a currency missing from the list. */
    fun exponent(code: CurrencyCode): Int = byCode[code]?.minorUnits ?: 2
}
