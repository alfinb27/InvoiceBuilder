package app.invoicebuilder.core.domain.setup

import app.invoicebuilder.core.domain.decimal.InputError
import app.invoicebuilder.core.domain.models.Address
import app.invoicebuilder.core.domain.numbering.NumberingError
import app.invoicebuilder.core.domain.numbering.NumberingPatternIssue
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.TaxIDError
import app.invoicebuilder.core.domain.validation.FieldError
import app.invoicebuilder.core.domain.validation.FieldRule

/** Why a setup field cannot be saved as typed. Screens turn these into messages. iOS: `FieldIssue`. */
sealed interface FieldIssue {
    data object Required : FieldIssue
    /** A `spec/setup.md` §8 field rule failed. */
    data class Invalid(val rule: FieldRule, val error: FieldError) : FieldIssue
    /** A GSTIN / VAT number failed `ENGINE.md` §8. */
    data class InvalidTaxID(val error: TaxIDError) : FieldIssue
    /** Typed money or decimal text (`spec/setup.md` §11). */
    data class InvalidNumber(val error: InputError) : FieldIssue
    data class OutOfRange(val range: IntRange) : FieldIssue
    data class InvalidPattern(val issues: List<NumberingPatternIssue>) : FieldIssue
    data class InvalidNumbering(val error: NumberingError) : FieldIssue
    /** A next number at or below the highest one already issued in the period (`spec/setup.md` §6). */
    data class AlreadyIssued(val highest: Int) : FieldIssue
    /** A line discount larger than quantity × price. */
    data object ExceedsLineAmount : FieldIssue
}

/** An address being edited: plain text fields, normalised when saved. iOS: `AddressDraft`. */
data class AddressDraft(val line1: String = "", val line2: String = "", val city: String = "", val postalCode: String = "") {
    constructor(address: Address?) : this(address?.line1 ?: "", address?.line2 ?: "", address?.city ?: "", address?.postalCode ?: "")

    /** True when every field is blank. */
    val isBlank: Boolean get() = listOf(line1, line2, city, postalCode).all { it.trimmedOrNull == null }

    /** Issues for the address fields: `line1` once anything is filled, and the postal code rule. */
    fun issues(countryCode: String, lineRequired: Boolean): Pair<FieldIssue?, FieldIssue?> {
        val line1Issue = if ((lineRequired || !isBlank) && line1.trimmedOrNull == null) FieldIssue.Required else null
        var postalIssue: FieldIssue? = null
        val rule = postalRule(countryCode)
        val postal = postalCode.trimmedOrNull
        if (rule != null && postal != null) rule.validate(postal).error?.let { postalIssue = FieldIssue.Invalid(rule, it) }
        return line1Issue to postalIssue
    }

    /** The stored address, or null when blank. */
    fun address(countryCode: String, regionCode: String?): Address? {
        val line1 = line1.trimmedOrNull ?: return null
        val postal = postalCode.trimmedOrNull?.let { text -> postalRule(countryCode)?.validate(text)?.normalized ?: text }
        return Address(line1, line2.trimmedOrNull, city.trimmedOrNull, regionCode, postal, countryCode)
    }

    companion object {
        /** The postal code rule for addresses in [countryCode] (`spec/setup.md` §8), if any. */
        fun postalRule(countryCode: String): FieldRule? = when (countryCode) {
            "IN" -> FieldRule.postalCodeIN
            "GB" -> FieldRule.postalCodeGB
            else -> null
        }
    }
}

/** Adds the rule's issue for [value] (blank values are skipped: every rule field is optional unless stated). */
fun <K> MutableMap<K, FieldIssue>.check(key: K, value: String, rule: FieldRule) {
    val text = value.trimmedOrNull ?: return
    rule.validate(text).error?.let { this[key] = FieldIssue.Invalid(rule, it) }
}

/** Normalised text of a field rule, or the trimmed text when it does not validate (never stored: saving is blocked). */
fun normalized(value: String, rule: FieldRule): String? = value.trimmedOrNull?.let { rule.validate(it).normalized }
