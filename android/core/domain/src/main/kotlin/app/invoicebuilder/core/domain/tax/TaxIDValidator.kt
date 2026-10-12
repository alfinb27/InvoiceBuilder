package app.invoicebuilder.core.domain.tax

import app.invoicebuilder.core.domain.support.SpecRegex
import app.invoicebuilder.core.domain.support.isAsciiDigits
import app.invoicebuilder.core.domain.support.removingWhitespace

/** Result of validating a GSTIN or UK VAT number (`spec/tax/ENGINE.md` §8). */
data class TaxIDValidation(
    val valid: Boolean,
    /** Trimmed, whitespace removed, upper-cased (and `GB`-prefixed for bare UK numbers). Reported even when invalid. */
    val normalized: String,
    /** GSTIN state code (first 2 characters) of a valid GSTIN. */
    val region: String? = null,
    val error: TaxIDError? = null,
)

enum class TaxIDError(val rawValue: String) { Format("format"), Checksum("checksum"), UnknownRegion("unknown_region") }

/** iOS: `TaxIDValidator`. */
object TaxIDValidator {
    /** Validates [value] with the config's tax ID format; null when the config has none (GENERIC). */
    fun validate(value: String, config: TaxConfig): TaxIDValidation? =
        config.taxIDFormat?.let { validate(value, it, config.regions) }

    /** Normalise, then check the format, the checksum and (GSTIN) the region, in that order. */
    fun validate(value: String, format: TaxIDFormat, regions: List<TaxRegion>): TaxIDValidation {
        var normalized = value.removingWhitespace.uppercase()
        if (format.normalizePrefix != null && normalized.isAsciiDigits && normalized.length in listOf(9, 12)) {
            normalized = format.normalizePrefix + normalized
        }
        if (!SpecRegex.matches(format.pattern, normalized)) return TaxIDValidation(false, normalized, error = TaxIDError.Format)
        when (format.checksum) {
            "gstinMod36" -> if (!gstinChecksumIsValid(normalized)) return TaxIDValidation(false, normalized, error = TaxIDError.Checksum)
            "ukVatMod97" -> if (!ukVatChecksumIsValid(normalized)) return TaxIDValidation(false, normalized, error = TaxIDError.Checksum)
        }
        val prefixLength = format.regionFromPrefix ?: return TaxIDValidation(true, normalized)
        val region = normalized.take(prefixLength)
        if (regions.none { it.code == region }) return TaxIDValidation(false, normalized, error = TaxIDError.UnknownRegion)
        return TaxIDValidation(true, normalized, region = region)
    }

    /**
     * `0-9A-Z` → 0–35; weights 1, 2, 1, 2, … over the first 14 characters; `p = value × weight`;
     * `sum += p / 36 + p % 36`; the check character is `(36 − sum % 36) % 36`.
     */
    fun gstinChecksumIsValid(gstin: String): Boolean {
        val values = gstin.mapNotNull(::base36Value)
        if (values.size != 15) return false
        var sum = 0
        for ((index, value) in values.take(14).withIndex()) {
            val product = value * (if (index % 2 == 0) 1 else 2)
            sum += product / 36 + product % 36
        }
        return (36 - sum % 36) % 36 == values[14]
    }

    /**
     * Numeric forms: the 9 digits after `GB`; `w = Σ d_i × (8, 7, 6, 5, 4, 3, 2)` over d0…d6 and
     * `chk = 10 × d7 + d8`; valid if `(w + chk) % 97 == 0` or `(w + 55 + chk) % 97 == 0`.
     * `GD`/`HA` (government departments, health authorities) are format-checked only.
     */
    fun ukVatChecksumIsValid(vat: String): Boolean {
        val body = vat.drop(2)
        if (body.firstOrNull()?.isDigit() != true) return true
        val digits = body.take(9).mapNotNull { it.digitToIntOrNull() }
        if (digits.size != 9) return false
        val weights = listOf(8, 7, 6, 5, 4, 3, 2)
        val weighted = digits.take(7).zip(weights).sumOf { it.first * it.second }
        val check = 10 * digits[7] + digits[8]
        return (weighted + check) % 97 == 0 || (weighted + 55 + check) % 97 == 0
    }

    private fun base36Value(character: Char): Int? = when (character) {
        in '0'..'9' -> character - '0'
        in 'A'..'Z' -> character - 'A' + 10
        else -> null
    }
}
