package app.invoicebuilder.core.domain.documents

import app.invoicebuilder.core.domain.decimal.DecimalString
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.money.CurrencyCatalog
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.RoundingMode
import app.invoicebuilder.core.domain.tax.SpecMath
import app.invoicebuilder.core.domain.tax.TaxRate
import java.math.BigDecimal

/** A catalogue price in a document's currency and price basis (`spec/documents.md` §3.1). iOS: `LinePricing`. */
object LinePricing {
    enum class Failure(val rawValue: String) {
        /** A foreign-currency document without an exchange rate cannot convert a home-currency price. */
        ExchangeRateMissing("exchange_rate_missing"),
    }

    /** `round(price × b × c, amountMode)` with one division, so the only rounding is the final one. */
    fun unitPrice(
        item: CatalogItem, rate: TaxRate?, chargesTax: Boolean, homeCurrency: CurrencyCode, documentCurrency: CurrencyCode,
        exchangeRate: String?, documentInclusive: Boolean, currencies: CurrencyCatalog, mode: RoundingMode,
    ): Outcome<Long, Failure> {
        var numerator = BigDecimal.ONE
        var denominator = BigDecimal.ONE
        val hundred = BigDecimal(100)
        if (chargesTax && item.priceIncludesTax != documentInclusive) {
            val percent = rate?.let(::effectivePercent) ?: BigDecimal.ZERO
            if (item.priceIncludesTax) {
                numerator = hundred
                denominator = hundred + percent
            } else {
                numerator = hundred + percent
                denominator = hundred
            }
        }
        if (item.currency != documentCurrency) {
            val rateValue = exchangeRate?.trimmedOrNull?.let(DecimalString::parse)
            if (item.currency != homeCurrency || rateValue == null || rateValue.signum() <= 0) {
                return Outcome.Failure(Failure.ExchangeRateMissing)
            }
            numerator *= SpecMath.powerOfTen(currencies.exponent(documentCurrency) - currencies.exponent(homeCurrency))
            denominator *= rateValue
        }
        val exact = (BigDecimal.valueOf(item.unitPriceMinor) * numerator).divide(denominator, SpecMath.context)
        return Outcome.Success(SpecMath.round(exact, mode))
    }

    /**
     * `R`: a config rate's `percent`; a custom rate's components applied in order to 100, a compound component
     * also taxing the earlier components' tax (5% + compound 10% → 15.5).
     */
    fun effectivePercent(rate: TaxRate): BigDecimal {
        val components = rate.components
        if (components.isNullOrEmpty()) return rate.percent?.let(DecimalString::parse) ?: BigDecimal.ZERO
        var accumulated = BigDecimal.ZERO
        val hundred = BigDecimal(100)
        for (component in components) {
            val percent = DecimalString.parse(component.percent) ?: BigDecimal.ZERO
            val base = hundred + (if (component.compound == true) accumulated else BigDecimal.ZERO)
            accumulated += (base * percent).divide(hundred, SpecMath.context)
        }
        return accumulated
    }
}
