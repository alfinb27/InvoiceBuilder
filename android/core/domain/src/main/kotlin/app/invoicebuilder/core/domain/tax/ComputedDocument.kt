package app.invoicebuilder.core.domain.tax

import app.invoicebuilder.core.domain.money.CurrencyCode
import kotlinx.serialization.Serializable

/** The engine result (`ENGINE.md` §4), stored on issued documents as `computed`. Key names match iOS's JSON. */
@Serializable
data class ComputedDocument(
    val title: String,
    val chargesTax: Boolean,
    val placeOfSupply: String? = null,
    val sameRegion: Boolean? = null,
    val reverseCharge: Boolean,
    val inclusive: Boolean,
    val lines: List<ComputedLine>,
    val shipping: ComputedShipping? = null,
    val taxLines: List<ComputedTaxLine>,
    val totals: ComputedTotals,
    val home: HomeTotals? = null,
    val notes: List<ComputedNote>,
    val issues: List<EngineIssue>,
) {
    val hasBlockingIssues: Boolean get() = issues.any { it.severity == EngineIssue.Severity.error }
}

@Serializable
data class ComputedLine(
    val amount: Long,
    val discount: Long,
    val taxable: Long,
    val rateId: String,
    val rate: String,
    val category: TaxCategory,
    val taxes: List<LineTax>? = null,
) {
    val tax: Long get() = taxes?.sumOf { it.amount } ?: 0
}

@Serializable
data class LineTax(val component: String? = null, val rate: String, val amount: Long)

@Serializable
data class ComputedShipping(val amount: Long, val taxable: Long, val parts: List<ShippingPart>)

@Serializable
data class ShippingPart(val rateId: String, val amount: Long, val taxable: Long)

@Serializable
data class ComputedTaxLine(
    val component: String? = null,
    val rate: String,
    val category: TaxCategory,
    val taxable: Long,
    val tax: Long,
    val charged: Boolean,
    val homeTax: Long? = null,
)

@Serializable
data class ComputedTotals(
    val subtotal: Long,
    val discount: Long,
    val shipping: Long,
    val taxable: Long,
    val tax: Long,
    val taxNotCharged: Long,
    val roundOff: Long,
    val total: Long,
)

@Serializable
data class HomeTotals(val currency: CurrencyCode, val rate: String, val taxable: Long, val tax: Long, val total: Long)

@Serializable
data class ComputedNote(val id: String, val text: String, val placement: String)

@Serializable
data class EngineIssue(val code: String, val severity: Severity, val lines: List<Int>? = null) {
    @Serializable
    @JvmInline
    value class Severity(val rawValue: String) {
        companion object {
            val error = Severity("error")
            val warning = Severity("warning")
        }
    }
}

class TaxEngineError(val code: Code, val line: Int? = null) : Exception("${code.rawValue}${line?.let { " (line $it)" } ?: ""}") {
    enum class Code(val rawValue: String) {
        NoComponentRule("no_component_rule"),
        UnknownRate("unknown_rate"),
        UnknownRegion("unknown_region"),
        DiscountExceedsSubtotal("discount_exceeds_subtotal"),
        LineDiscountExceedsAmount("line_discount_exceeds_amount"),
        InclusiveCompoundUnsupported("inclusive_compound_unsupported"),
        InvalidInput("invalid_input"),
    }

    override fun equals(other: Any?): Boolean = other is TaxEngineError && other.code == code && other.line == line
    override fun hashCode(): Int = code.hashCode() * 31 + (line ?: -1)
}
