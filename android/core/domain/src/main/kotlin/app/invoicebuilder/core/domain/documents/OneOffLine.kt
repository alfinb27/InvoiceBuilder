package app.invoicebuilder.core.domain.documents

import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.ItemKind
import app.invoicebuilder.core.domain.money.CurrencyCatalog
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.support.SpecJson
import app.invoicebuilder.core.domain.support.SpecResources
import app.invoicebuilder.core.domain.tax.RoundingMode
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.tax.TaxRate
import kotlinx.serialization.Serializable
import java.time.LocalDate

/**
 * The "Add an item" sheet's rate chips (`spec/documents.md` §3.2, `spec/design/rate-chips.json`). iOS: `RateChips`.
 */
@Serializable
data class RateChips(val maxChips: Int, val families: Map<String, Family>) {
    @Serializable
    data class Family(val rates: List<String>, val hint: String)

    /** The chips, the "Other rates" list and the hint under the chips. */
    data class Choices(val chips: List<TaxRate>, val others: List<TaxRate>, val hint: String?)

    /** The chips and the other rates for [config], among the rates in force on [date]. */
    fun choices(config: TaxConfig, customRates: List<TaxRate>?, date: LocalDate): Choices {
        val inForce = config.ratesInForce(date, customRates)
        val family = families[config.family]
        val chips = family?.rates?.mapNotNull { id -> inForce.firstOrNull { it.id == id } } ?: inForce.take(maxChips)
        val chipIDs = chips.map { it.id }.toSet()
        return Choices(chips, inForce.filter { it.id !in chipIDs }, family?.hint)
    }

    companion object {
        /** `spec/design/rate-chips.json`. */
        fun bundled(): RateChips = SpecJson.decodeFromString(serializer(), SpecResources.text("design/rate-chips.json"))
    }
}

/** How the "Add an item" sheet reads a typed price, and the item "Save to my items" creates. iOS: `OneOffLine`. */
object OneOffLine {
    /** True when the includes-tax switch sets the document's own basis: no line other than [lineID] is on it. */
    fun setsDocumentBasis(document: Document, lineID: String?): Boolean = document.lines.all { it.id == lineID }

    /**
     * The line's `unitPriceMinor` for a price typed in the document currency and read with [includesTax]: as typed
     * when that is the document's basis, otherwise converted with the §3.1 basis factor and one rounding.
     */
    fun unitPrice(
        typedMinor: Long, includesTax: Boolean, rate: TaxRate?, document: Document, chargesTax: Boolean,
        currencies: CurrencyCatalog, mode: RoundingMode,
    ): Long {
        if (!chargesTax || includesTax == document.pricesIncludeTax) return typedMinor
        val item = CatalogItem(
            id = "", businessId = document.businessId, name = "", unit = "", unitPriceMinor = typedMinor,
            currency = document.currency, rateId = rate?.id ?: "", priceIncludesTax = includesTax,
        )
        val price = LinePricing.unitPrice(
            item, rate, chargesTax, homeCurrency = document.currency, documentCurrency = document.currency,
            exchangeRate = null, documentInclusive = document.pricesIncludeTax, currencies = currencies, mode = mode,
        )
        return (price as? Outcome.Success)?.value ?: typedMinor
    }

    /** "Save to my items": the catalogue item for a one-off line (`setup.md` §10 defaults for a service). */
    fun catalogItem(
        line: LineItem, typedMinor: Long, includesTax: Boolean, chargesTax: Boolean, businessID: String,
        currency: CurrencyCode, id: String, now: Long,
    ) = CatalogItem(
        id = id, createdAt = now, updatedAt = now, businessId = businessID, name = line.description,
        kind = ItemKind.service, unit = line.unit ?: ItemKind.service.defaultUnit, unitPriceMinor = typedMinor,
        currency = currency, rateId = line.rateId, productCode = line.productCode,
        priceIncludesTax = chargesTax && includesTax,
    )
}
