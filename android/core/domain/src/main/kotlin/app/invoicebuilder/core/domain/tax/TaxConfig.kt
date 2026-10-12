package app.invoicebuilder.core.domain.tax

import app.invoicebuilder.core.domain.dates.IsoDate
import app.invoicebuilder.core.domain.dates.MonthDay
import app.invoicebuilder.core.domain.dates.iso
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.numbering.NumberingReset
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import java.time.LocalDate

/**
 * A country tax configuration (`spec/schema/tax-config.schema.json`): data-driven rules that the tax engine
 * interprets (`spec/tax/ENGINE.md`). Adding a country is a new JSON file plus fixtures, not code. iOS: `TaxConfig`.
 */
@Serializable
data class TaxConfig(
    val schemaVersion: Int,
    /** ISO 3166-1 alpha-2; `ZZ` is the generic config. */
    val country: String,
    /** The date the rules in this file take effect. */
    val configVersion: IsoDate,
    val reviewStatus: String,
    val currency: CurrencyCode? = null,
    val paperSize: String,
    val fiscalYearStart: MonthDay,
    val amountInWords: Boolean = false,
    val labels: TaxLabels,
    val taxIdFormats: List<TaxIDFormat> = emptyList(),
    val regions: List<TaxRegion> = emptyList(),
    val foreignRegion: String? = null,
    val registrations: List<TaxRegistration>,
    val ratesFrom: RatesSource = RatesSource.config,
    val rates: List<TaxRate>,
    val supplyTypes: List<SupplyType>,
    /** The supply type a new draft starts with (`spec/documents.md` §2.1). */
    val supplyTypeDefaults: List<SupplyTypeDefault> = emptyList(),
    val componentRules: List<ComponentRule>,
    val reverseCharge: ReverseChargeRules,
    val rounding: RoundingRules,
    val shipping: ShippingRules,
    val productCodes: ProductCodeRules? = null,
    val numbering: NumberingRules,
    val foreignCurrency: ForeignCurrencyRules,
    val checks: List<TaxCheck>,
    val notesCatalog: Map<String, NoteText>,
) {
    /** The config id stored on a business (`IN`, `GB`, `GENERIC`); also the file name in `spec/tax`. */
    val family: String get() = if (country == "ZZ") "GENERIC" else country

    /** `<family>@<configVersion>`, e.g. `IN@2025-09-22`, stored on documents as `tax_config_ref`. */
    val ref: String get() = "$family@${configVersion.iso}"

    fun registration(id: String): TaxRegistration? = registrations.firstOrNull { it.id == id }

    fun region(code: String): TaxRegion? = regions.firstOrNull { it.code == code }

    /** Regions offered in pickers: active ones, sorted by name. */
    val activeRegionsByName: List<TaxRegion>
        get() = regions.filter { it.isActive }.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })

    /** The tax ID format used for sellers and domestic buyers (the first entry), if the country has one. */
    val taxIDFormat: TaxIDFormat? get() = taxIdFormats.firstOrNull()

    /** The rates a business can use: the config's own, or the business's custom rates when `ratesFrom = business`. */
    fun availableRates(customRates: List<TaxRate>?): List<TaxRate> =
        if (ratesFrom == RatesSource.business) customRates ?: emptyList() else rates

    /** Rates in force on [date], in config order (`spec/setup.md` §10). */
    fun ratesInForce(date: LocalDate, customRates: List<TaxRate>?): List<TaxRate> =
        availableRates(customRates).filter { it.isInForce(date) }

    fun rate(id: String, customRates: List<TaxRate>?): TaxRate? = availableRates(customRates).firstOrNull { it.id == id }

    fun numberingPattern(docType: DocumentType): String =
        if (docType == DocumentType.quote) numbering.quotePattern else numbering.invoicePattern
}

@Serializable
enum class RatesSource { config, business }

@Serializable
data class TaxLabels(
    val taxName: String,
    val taxIdName: String,
    val productCodeName: String,
    val regionName: String? = null,
    val placeOfSupply: String? = null,
)

@Serializable
data class TaxIDFormat(
    val id: String,
    val pattern: String,
    /** `gstinMod36` or `ukVatMod97` (`ENGINE.md` §8). */
    val checksum: String? = null,
    /** The first N characters of a valid ID are a region code (GSTIN state code). */
    val regionFromPrefix: Int? = null,
    /** Prepended to bare 9- or 12-digit input (`GB`). */
    val normalizePrefix: String? = null,
)

@Serializable
data class TaxRegion(
    val code: String,
    val name: String,
    /** `SGST` or `UTGST` for Indian states and union territories. */
    val localComponent: String? = null,
    val active: Boolean? = null,
) {
    val isActive: Boolean get() = active ?: true
}

@Serializable
data class TaxRegistration(
    val id: String,
    val label: String,
    val chargesTax: Boolean,
    val requiresTaxId: Boolean,
    val titles: DocumentTitles,
    val notes: List<String>? = null,
)

@Serializable
data class DocumentTitles(val invoice: String, val invoiceAllExempt: String? = null, val quote: String)

/** A tax rate: from a config's `rates`, or a business's custom rate (GENERIC, with `components`). */
@Serializable
data class TaxRate(
    val id: String,
    val percent: String? = null,
    val category: TaxCategory,
    val label: String,
    val effectiveFrom: IsoDate,
    val effectiveTo: IsoDate? = null,
    val note: String? = null,
    val components: List<RateComponent>? = null,
) {
    /** `effectiveFrom ≤ date ≤ effectiveTo`, both inclusive. */
    fun isInForce(date: LocalDate): Boolean = effectiveFrom <= date && (effectiveTo?.let { date <= it } ?: true)
}

@Serializable
data class RateComponent(val code: String, val label: String, val percent: String, val compound: Boolean? = null)

/** Tax category of a rate or component. An open set: values written by a newer app version are kept. */
@Serializable
@JvmInline
value class TaxCategory(val rawValue: String) {
    companion object {
        val standard = TaxCategory("standard")
        val reduced = TaxCategory("reduced")
        val zero = TaxCategory("zero")
        val exempt = TaxCategory("exempt")
        val nilRated = TaxCategory("nil")
        val outsideScope = TaxCategory("outsideScope")
    }
}

@Serializable
data class SupplyType(val id: String, val label: String)

/** `supplyTypeDefaults` entry: every key `when` lists must match (`spec/documents.md` §2.1). */
@Serializable
data class SupplyTypeDefault(@SerialName("when") val condition: Condition, val supplyType: String) {
    @Serializable
    data class Condition(
        val buyerForeign: Boolean? = null,
        val buyerIsBusiness: Boolean? = null,
        val sellerHasLutReference: Boolean? = null,
    )
}

@Serializable
data class ComponentRule(
    @SerialName("when") val condition: TaxCondition,
    val components: ComponentSource,
    val notes: List<String>? = null,
)

/** A rule's components: listed in the config, or taken from the rate itself (`"fromRate"`, GENERIC). */
@Serializable(with = ComponentSourceSerializer::class)
sealed interface ComponentSource {
    data object FromRate : ComponentSource
    data class Listed(val references: List<ComponentRef>) : ComponentSource
}

object ComponentSourceSerializer : KSerializer<ComponentSource> {
    private val list = ListSerializer(ComponentRef.serializer())
    override val descriptor: SerialDescriptor = list.descriptor

    override fun deserialize(decoder: kotlinx.serialization.encoding.Decoder): ComponentSource {
        val json = decoder as JsonDecoder
        return when (val element = json.decodeJsonElement()) {
            is JsonPrimitive -> if (element.contentOrNull == "fromRate") ComponentSource.FromRate
            else throw SerializationException("Unknown components $element")
            is JsonArray -> ComponentSource.Listed(json.json.decodeFromJsonElement(list, element))
            else -> throw SerializationException("Unknown components $element")
        }
    }

    override fun serialize(encoder: kotlinx.serialization.encoding.Encoder, value: ComponentSource) {
        val json = encoder as JsonEncoder
        when (value) {
            ComponentSource.FromRate -> json.encodeJsonElement(JsonPrimitive("fromRate"))
            is ComponentSource.Listed -> json.encodeSerializableValue(list, value.references)
        }
    }
}

@Serializable
data class ComponentRef(
    /** A component code, or `$localComponent` for the place-of-supply region's local component. */
    val code: String,
    val share: String,
    val rateOverride: String? = null,
    val categoryOverride: TaxCategory? = null,
)

/** Keys a rule or check matches on; every listed key must match (`ENGINE.md` Step 1, Step 12). */
@Serializable
data class TaxCondition(
    val supplyType: List<String>? = null,
    val sameRegion: Boolean? = null,
    val sellerRegistration: List<String>? = null,
    val buyerIsBusiness: Boolean? = null,
    val buyerHasTaxId: Boolean? = null,
    val reverseCharge: Boolean? = null,
    val docType: List<String>? = null,
    val foreignCurrency: Boolean? = null,
    val totalAtLeastMinor: Long? = null,
) {
    companion object {
        /** A condition with no keys: always matches. */
        val always = TaxCondition()
    }
}

@Serializable
data class ReverseChargeRules(val supported: Boolean, val notes: List<String>? = null)

@Serializable
enum class TaxLevel { line, invoice }

@Serializable
data class RoundingRules(
    val amountMode: RoundingMode,
    val taxLevel: TaxLevel,
    val taxMode: RoundingMode,
    val grandTotal: GrandTotalRounding? = null,
)

@Serializable
data class GrandTotalRounding(val roundToMinor: Long, val mode: RoundingMode, val label: String, val defaultOn: Boolean)

@Serializable
enum class ShippingRule { principalSupplyRate, apportion }

@Serializable
data class ShippingRules(val rule: ShippingRule)

@Serializable
data class ProductCodeRules(val tiers: List<ProductCodeTier>)

@Serializable
data class ProductCodeTier(val maxTurnoverMinor: Long? = null, val b2bDigits: Int, val b2cDigits: Int)

@Serializable
data class NumberingRules(
    val maxLength: Int? = null,
    val allowedPattern: String? = null,
    val reset: NumberingReset,
    val invoicePattern: String,
    val quotePattern: String,
)

@Serializable
data class ForeignCurrencyRules(val homeTotals: Boolean, val taxInHomeCurrency: Boolean)

@Serializable
data class TaxCheck(
    val code: String,
    val severity: String,
    val type: String? = null,
    val require: List<String>? = null,
    @SerialName("when") val condition: TaxCondition? = null,
)

@Serializable
data class NoteText(val text: String, val placement: String)
