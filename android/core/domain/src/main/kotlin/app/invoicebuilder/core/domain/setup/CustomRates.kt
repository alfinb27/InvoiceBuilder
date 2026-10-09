package app.invoicebuilder.core.domain.setup

import app.invoicebuilder.core.domain.decimal.DecimalInput
import app.invoicebuilder.core.domain.decimal.DecimalString
import app.invoicebuilder.core.domain.decimal.InputError
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.RateComponent
import app.invoicebuilder.core.domain.tax.TaxCategory
import app.invoicebuilder.core.domain.tax.TaxRate
import java.math.BigDecimal
import java.time.LocalDate

/** Business-defined tax rates for GENERIC countries (`spec/setup.md` §7). iOS: `CustomRates`. */
object CustomRates {
    /** Every GENERIC business has it, so items always have a valid rate even if the business registers later. */
    val noTax = TaxRate(
        id = "none", category = TaxCategory.zero, label = "No tax", effectiveFrom = LocalDate.of(2000, 1, 1),
        components = listOf(RateComponent("TAX", "Tax", "0")),
    )

    /** The rates onboarding creates: the named rate (tax-charging registrations only), then "No tax". */
    fun initialRates(chargesTax: Boolean, taxName: String, percent: String, today: LocalDate, newID: () -> String): List<TaxRate> {
        if (!chargesTax) return listOf(noTax)
        return listOf(CustomRateDraft(name = taxName, percent = percent).makeRate(rateID(newID()), today), noTax)
    }

    /** `r` + the first 8 hex digits of a UUID; `r` + all 32 when a rate in [existing] already has the short id. */
    fun rateID(uuid: String, existing: List<TaxRate> = emptyList()): String {
        val hex = uuid.lowercase().filter { it in '0'..'9' || it in 'a'..'f' }
        val short = "r" + hex.take(8)
        return if (existing.any { it.id == short }) "r$hex" else short
    }

    /** `T` upper-cased, keeping only `A–Z 0–9`, at most 12 characters; `TAX` when nothing is left. */
    fun componentCode(name: String): String =
        name.uppercase().filter { it in 'A'..'Z' || it in '0'..'9' }.take(12).ifEmpty { "TAX" }

    /** A typed percent that is not a decimal in 0–100. */
    fun percentIssue(text: String): FieldIssue? = when (val parsed = DecimalInput.parse(text)) {
        is Outcome.Failure -> if (parsed.error == InputError.Empty) FieldIssue.Required else FieldIssue.InvalidNumber(parsed.error)
        is Outcome.Success -> {
            val decimal = DecimalString.parse(parsed.value)
            if (decimal == null || decimal > BigDecimal(100)) FieldIssue.OutOfRange(0..100) else null
        }
    }
}

enum class CustomRateField { Name, Percent, SecondName, SecondPercent }

/** A custom rate being edited: one component, or two with the second optionally compound. */
data class CustomRateDraft(
    val name: String = "",
    val percent: String = "",
    val hasSecondComponent: Boolean = false,
    val secondName: String = "",
    val secondPercent: String = "",
    val secondIsCompound: Boolean = false,
) {
    val issues: Map<CustomRateField, FieldIssue>
        get() {
            val issues = mutableMapOf<CustomRateField, FieldIssue>()
            if (name.trimmedOrNull == null) issues[CustomRateField.Name] = FieldIssue.Required
            CustomRates.percentIssue(percent)?.let { issues[CustomRateField.Percent] = it }
            if (hasSecondComponent) {
                if (secondName.trimmedOrNull == null) issues[CustomRateField.SecondName] = FieldIssue.Required
                CustomRates.percentIssue(secondPercent)?.let { issues[CustomRateField.SecondPercent] = it }
            }
            return issues
        }

    /** The stored rate; label `"T p%"`, or `"T1 p1% + T2 p2%"` (`+ " (compound)"`). */
    fun makeRate(id: String, today: LocalDate): TaxRate {
        val components = mutableListOf(component(name, percent, null))
        if (hasSecondComponent) components += component(secondName, secondPercent, if (secondIsCompound) true else null)
        val label = components.joinToString(" + ") { "${it.label} ${it.percent}%" } + if (secondIsCompound && hasSecondComponent) " (compound)" else ""
        return TaxRate(id = id, category = TaxCategory.standard, label = label, effectiveFrom = today, components = components)
    }

    private fun component(name: String, percent: String, compound: Boolean?): RateComponent {
        val label = name.trimmedOrNull ?: "Tax"
        val value = (DecimalInput.parse(percent) as? Outcome.Success)?.value ?: "0"
        return RateComponent(CustomRates.componentCode(label), label, value, compound)
    }

    companion object {
        fun of(rate: TaxRate): CustomRateDraft {
            val components = rate.components ?: emptyList()
            val second = components.getOrNull(1)
            return CustomRateDraft(
                name = components.firstOrNull()?.label ?: rate.label, percent = components.firstOrNull()?.percent ?: rate.percent ?: "",
                hasSecondComponent = second != null, secondName = second?.label ?: "", secondPercent = second?.percent ?: "",
                secondIsCompound = second?.compound ?: false,
            )
        }
    }
}
