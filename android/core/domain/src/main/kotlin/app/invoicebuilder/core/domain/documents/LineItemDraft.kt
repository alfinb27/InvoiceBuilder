package app.invoicebuilder.core.domain.documents

import app.invoicebuilder.core.domain.decimal.DecimalInput
import app.invoicebuilder.core.domain.decimal.DecimalString
import app.invoicebuilder.core.domain.decimal.InputError
import app.invoicebuilder.core.domain.decimal.MoneyInput
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.setup.FieldIssue
import app.invoicebuilder.core.domain.setup.check
import app.invoicebuilder.core.domain.setup.normalized
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.Discount
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.validation.FieldRule
import java.math.BigDecimal

enum class LineItemField { Description, Quantity, Price, Discount, Rate, ProductCode }

/** A line being edited in the line editor: plain text, validated live and applied on Done. iOS: `LineItemDraft`. */
data class LineItemDraft(
    val description: String = "",
    val productCode: String = "",
    val unit: String? = null,
    val quantityText: String = "1",
    /** In the document's currency and price basis. */
    val priceText: String = "",
    val discountText: String = "",
    val discountIsPercent: Boolean = true,
    val rateId: String = "",
) {
    companion object {
        fun of(line: LineItem, exponent: Int): LineItemDraft {
            val (discountText, isPercent) = DocumentInput.editingText(line.discount, exponent)
            return LineItemDraft(
                description = line.description, productCode = line.productCode ?: "", unit = line.unit,
                quantityText = SpecFormatter.quantity(line.quantity), priceText = MoneyInput.editingText(line.unitPriceMinor, exponent),
                discountText = discountText, discountIsPercent = isPercent, rateId = line.rateId,
            )
        }
    }
}

/** Validation and normalisation for the line editor. iOS: `LineItemRules`. */
class LineItemRules(val config: TaxConfig, val chargesTax: Boolean, /** Fraction digits of the document currency. */ val exponent: Int) {
    /** India: HSN/SAC digits only. */
    val productCodeRule: FieldRule? get() = if (config.family == "IN") FieldRule.hsnSac else null

    fun issues(draft: LineItemDraft): Map<LineItemField, FieldIssue> {
        val issues = mutableMapOf<LineItemField, FieldIssue>()
        if (draft.description.trimmedOrNull == null) issues[LineItemField.Description] = FieldIssue.Required
        val quantity = DecimalInput.parse(draft.quantityText)
        if (quantity is Outcome.Failure) {
            issues[LineItemField.Quantity] = if (quantity.error == InputError.Empty) FieldIssue.Required else FieldIssue.InvalidNumber(quantity.error)
        }
        val price = MoneyInput.parse(draft.priceText, exponent)
        if (price is Outcome.Failure) {
            issues[LineItemField.Price] = if (price.error == InputError.Empty) FieldIssue.Required else FieldIssue.InvalidNumber(price.error)
        }
        when (val discount = DocumentInput.discount(draft.discountText, draft.discountIsPercent, exponent)) {
            is Outcome.Failure -> issues[LineItemField.Discount] = discount.error
            is Outcome.Success -> {
                val value = discount.value
                if (value is Discount.Amount && quantity is Outcome.Success && price is Outcome.Success) {
                    val gross = DecimalString.parse(quantity.value)?.multiply(BigDecimal.valueOf(price.value))
                    if (gross != null && BigDecimal.valueOf(value.value) > gross) issues[LineItemField.Discount] = FieldIssue.ExceedsLineAmount
                }
            }
        }
        if (chargesTax && draft.rateId.trimmedOrNull == null) issues[LineItemField.Rate] = FieldIssue.Required
        productCodeRule?.let { issues.check(LineItemField.ProductCode, draft.productCode, it) }
        return issues
    }

    /** Copies the draft's valid values onto [line] (invalid text leaves the old value in place). */
    fun apply(draft: LineItemDraft, line: LineItem): LineItem {
        var updated = line.copy(
            description = draft.description.trimmedOrNull ?: line.description,
            productCode = productCodeRule?.let { normalized(draft.productCode, it) } ?: draft.productCode.trimmedOrNull,
            unit = draft.unit,
        )
        (DecimalInput.parse(draft.quantityText) as? Outcome.Success)?.let { updated = updated.copy(quantity = it.value) }
        (MoneyInput.parse(draft.priceText, exponent) as? Outcome.Success)?.let { updated = updated.copy(unitPriceMinor = it.value) }
        (DocumentInput.discount(draft.discountText, draft.discountIsPercent, exponent) as? Outcome.Success)?.let {
            updated = updated.copy(discount = it.value)
        }
        if (draft.rateId.trimmedOrNull != null) updated = updated.copy(rateId = draft.rateId)
        return updated
    }
}

/** The builder's typed document fields (`spec/setup.md` §11 parsers). iOS: `DocumentInput`. */
object DocumentInput {
    /** A line or invoice discount: empty → none; a percent must be at most 100. */
    fun discount(text: String, isPercent: Boolean, exponent: Int): Outcome<Discount?, FieldIssue> {
        if (text.trimmedOrNull == null) return Outcome.Success(null)
        if (isPercent) {
            return when (val parsed = DecimalInput.parse(text)) {
                is Outcome.Success -> {
                    val percent = DecimalString.parse(parsed.value)
                    if (percent == null || percent > BigDecimal(100)) Outcome.Failure(FieldIssue.OutOfRange(0..100))
                    else Outcome.Success(if (percent.signum() == 0) null else Discount.Percent(parsed.value))
                }
                is Outcome.Failure -> Outcome.Failure(FieldIssue.InvalidNumber(parsed.error))
            }
        }
        return when (val parsed = MoneyInput.parse(text, exponent)) {
            is Outcome.Success -> Outcome.Success(if (parsed.value == 0L) null else Discount.Amount(parsed.value))
            is Outcome.Failure -> Outcome.Failure(FieldIssue.InvalidNumber(parsed.error))
        }
    }

    /** Shipping: empty → 0. */
    fun shipping(text: String, exponent: Int): Outcome<Long, FieldIssue> {
        if (text.trimmedOrNull == null) return Outcome.Success(0)
        return when (val parsed = MoneyInput.parse(text, exponent)) {
            is Outcome.Success -> parsed
            is Outcome.Failure -> Outcome.Failure(FieldIssue.InvalidNumber(parsed.error))
        }
    }

    /** A payment amount (`spec/documents.md` §10): required, greater than 0; may exceed the outstanding amount. */
    fun paymentAmount(text: String, exponent: Int): Outcome<Long, FieldIssue> {
        if (text.trimmedOrNull == null) return Outcome.Failure(FieldIssue.Required)
        return when (val parsed = MoneyInput.parse(text, exponent)) {
            is Outcome.Success -> if (parsed.value > 0) parsed else Outcome.Failure(FieldIssue.InvalidNumber(InputError.Invalid))
            is Outcome.Failure -> Outcome.Failure(FieldIssue.InvalidNumber(parsed.error))
        }
    }

    /** Units of home currency per 1 unit of the document currency: empty → none; otherwise a positive decimal. */
    fun exchangeRate(text: String): Outcome<String?, FieldIssue> {
        if (text.trimmedOrNull == null) return Outcome.Success(null)
        return when (val parsed = DecimalInput.parse(text)) {
            is Outcome.Success -> {
                val rate = DecimalString.parse(parsed.value)
                if (rate == null || rate.signum() <= 0) Outcome.Failure(FieldIssue.InvalidNumber(InputError.Invalid)) else Outcome.Success(parsed.value)
            }
            is Outcome.Failure -> Outcome.Failure(FieldIssue.InvalidNumber(parsed.error))
        }
    }

    /** Editing text for a discount: `("10", true)`, `("250.00", false)` or `("", true)`. */
    fun editingText(discount: Discount?, exponent: Int): Pair<String, Boolean> = when (discount) {
        is Discount.Percent -> SpecFormatter.quantity(discount.value) to true
        is Discount.Amount -> MoneyInput.editingText(discount.value, exponent) to false
        null -> "" to true
    }

    /** Editing text for an amount that may be 0 (shown empty). */
    fun editingText(minor: Long, exponent: Int): String = if (minor == 0L) "" else MoneyInput.editingText(minor, exponent)
}
