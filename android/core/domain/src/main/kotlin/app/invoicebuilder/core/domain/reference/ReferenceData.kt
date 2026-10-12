package app.invoicebuilder.core.domain.reference

import app.invoicebuilder.core.domain.money.Currency
import app.invoicebuilder.core.domain.money.CurrencyCatalog
import app.invoicebuilder.core.domain.support.SpecJson
import app.invoicebuilder.core.domain.support.SpecResources
import kotlinx.serialization.Serializable

/** One entry of `spec/reference/countries.json` (ISO 3166-1 alpha-2). */
@Serializable
data class Country(val code: String, val name: String)

/** One entry of `spec/reference/units.json`: a catalogue unit and its GST Unique Quantity Code. */
@Serializable
data class QuantityUnit(val id: String, val label: String, val uqc: String)

/** Countries, currencies and units from `spec/reference/`. iOS: `ReferenceData`. */
class ReferenceData(val countries: List<Country>, currencies: List<Currency>, val units: List<QuantityUnit>) {
    val currencies = CurrencyCatalog(currencies)
    private val countriesByCode = countries.reversed().associateBy { it.code }

    fun country(code: String): Country? = countriesByCode[code]

    fun unit(id: String): QuantityUnit? = units.firstOrNull { it.id == id }

    /** Countries sorted by English name, for pickers. */
    val countriesByName: List<Country> get() = countries.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })

    @Serializable private class Countries(val countries: List<Country>)
    @Serializable private class Currencies(val currencies: List<Currency>)
    @Serializable private class Units(val units: List<QuantityUnit>)

    companion object {
        fun bundled(): ReferenceData = ReferenceData(
            countries = SpecJson.decodeFromString(Countries.serializer(), SpecResources.text("reference/countries.json")).countries,
            currencies = SpecJson.decodeFromString(Currencies.serializer(), SpecResources.text("reference/currencies.json")).currencies,
            units = SpecJson.decodeFromString(Units.serializer(), SpecResources.text("reference/units.json")).units,
        )
    }
}
