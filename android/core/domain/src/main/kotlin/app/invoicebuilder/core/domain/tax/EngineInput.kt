package app.invoicebuilder.core.domain.tax

import app.invoicebuilder.core.domain.dates.IsoDate
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCatalog
import app.invoicebuilder.core.domain.money.CurrencyCode
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

/** Everything `TaxEngine.compute` reads (`spec/tax/ENGINE.md` §1). iOS: `EngineInput`. */
data class EngineInput(
    val config: TaxConfig,
    val seller: EngineSeller,
    val buyer: EngineBuyer,
    val draft: EngineDraft,
    /** Currency exponents for home-currency conversion. */
    val currencies: CurrencyCatalog,
)

@Serializable
data class EngineSeller(
    val registration: String,
    val taxId: String? = null,
    /** The seller's region when known; otherwise read from the tax ID prefix (GSTIN). */
    val region: String? = null,
    val country: String,
    val homeCurrency: CurrencyCode,
    val lutReference: String? = null,
    /** One line, for the `seller.address` check. */
    val address: String? = null,
    val turnoverMinor: Long? = null,
    /** Business-defined rates (`ratesFrom = business`). */
    val customRates: List<TaxRate>? = null,
)

@Serializable
data class EngineBuyer(
    val name: String? = null,
    val address: String? = null,
    /** Null means domestic (walk-in customers, quick bills). */
    val country: String? = null,
    val region: String? = null,
    val taxId: String? = null,
    val isBusiness: Boolean = false,
)

@Serializable
data class EngineDraft(
    val docType: DocumentType,
    val issueDate: IsoDate,
    /** Tax point; selects the rates in force (defaults to `issueDate`). */
    val supplyDate: IsoDate? = null,
    val dueDate: IsoDate? = null,
    val currency: CurrencyCode,
    /** Units of home currency per 1 unit of document currency (decimal string). */
    val exchangeRate: String? = null,
    val supplyType: String,
    /** Overrides the derived place of supply. */
    val placeOfSupply: String? = null,
    val reverseCharge: Boolean = false,
    val pricesIncludeTax: Boolean = false,
    val lines: List<EngineLine>,
    val discount: Discount? = null,
    /** Minor units, on the same price basis as the lines. */
    val shipping: Long? = null,
    /** Overrides the config's `grandTotal.defaultOn`. */
    val roundOff: Boolean? = null,
)

@Serializable
data class EngineLine(
    val description: String? = null,
    val productCode: String? = null,
    /** Decimal string. */
    val quantity: String,
    /** Minor units of the document currency. */
    val unitPrice: Long,
    val discount: Discount? = null,
    val rateId: String,
)

/**
 * A line or invoice discount: a percentage (decimal string) or an amount (minor units).
 * JSON: `{ "type": "percent", "value": "10" }` or `{ "type": "amount", "value": 5000 }`.
 */
@Serializable(with = DiscountSerializer::class)
sealed interface Discount {
    data class Percent(val value: String) : Discount
    data class Amount(val value: Long) : Discount
}

object DiscountSerializer : KSerializer<Discount> {
    override val descriptor = buildClassSerialDescriptor("Discount")

    override fun deserialize(decoder: Decoder): Discount {
        val element = (decoder as JsonDecoder).decodeJsonElement() as? JsonObject
            ?: throw SerializationException("A discount is an object")
        val value = element["value"]?.jsonPrimitive ?: throw SerializationException("discount.value missing")
        return when (element["type"]?.jsonPrimitive?.contentOrNull) {
            "percent" -> if (value.isString) Discount.Percent(value.content) else throw SerializationException("percent value")
            "amount" -> if (!value.isString) Discount.Amount(value.long) else throw SerializationException("amount value")
            else -> throw SerializationException("Unknown discount ${element["type"]}")
        }
    }

    override fun serialize(encoder: Encoder, value: Discount) {
        val json = encoder as JsonEncoder
        json.encodeJsonElement(
            when (value) {
                is Discount.Percent -> JsonObject(mapOf("type" to JsonPrimitive("percent"), "value" to JsonPrimitive(value.value)))
                is Discount.Amount -> JsonObject(mapOf("type" to JsonPrimitive("amount"), "value" to JsonPrimitive(value.value)))
            },
        )
    }
}
