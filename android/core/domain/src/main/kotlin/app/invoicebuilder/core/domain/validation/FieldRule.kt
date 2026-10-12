package app.invoicebuilder.core.domain.validation

import app.invoicebuilder.core.domain.support.SpecRegex
import app.invoicebuilder.core.domain.support.isAsciiDigits
import app.invoicebuilder.core.domain.support.removingWhitespace

/** Setup field rules (`spec/setup.md` §8): each normalises its input, then validates it. iOS: `FieldRule`. */
enum class FieldRule {
    email, ifsc, upiVpa, sortCode, iban, bic, pan, postalCodeIN, postalCodeGB, companyNumberGB, hsnSac;

    fun validate(value: String): FieldValidation {
        val normalized = normalize(value)
        if (!SpecRegex.matches(pattern, normalized)) return FieldValidation(false, normalized, FieldError.Format)
        if (this == iban && !ibanChecksumIsValid(normalized)) return FieldValidation(false, normalized, FieldError.Checksum)
        return FieldValidation(true, if (this == sortCode) hyphenated(normalized) else normalized)
    }

    private fun normalize(value: String): String = when (this) {
        email -> value.trim()
        upiVpa -> value.trim().lowercase()
        sortCode -> value.removingWhitespace.replace("-", "")
        ifsc, iban, bic, pan -> value.removingWhitespace.uppercase()
        postalCodeIN, hsnSac -> value.removingWhitespace
        postalCodeGB -> spacedPostcode(value.removingWhitespace.uppercase())
        companyNumberGB -> paddedCompanyNumber(value.removingWhitespace.uppercase())
    }

    private val pattern: String
        get() = when (this) {
            email -> "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$"
            ifsc -> "^[A-Z]{4}0[A-Z0-9]{6}$"
            upiVpa -> "^[a-z0-9._-]{2,256}@[a-z][a-z0-9.-]{1,63}$"
            sortCode -> "^[0-9]{6}$"
            iban -> "^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$"
            bic -> "^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$"
            pan -> "^[A-Z]{5}[0-9]{4}[A-Z]$"
            postalCodeIN -> "^[1-9][0-9]{5}$"
            postalCodeGB -> "^[A-Z]{1,2}[0-9][A-Z0-9]? [0-9][A-Z]{2}$"
            companyNumberGB -> "^([0-9]{8}|[A-Z]{2}[0-9]{6})$"
            hsnSac -> "^[0-9]{2,8}$"
        }

    companion object {
        fun of(rawValue: String): FieldRule? = entries.firstOrNull { it.name == rawValue }

        /** `SW1A1AA` → `SW1A 1AA`: one space before the last 3 characters. */
        private fun spacedPostcode(compact: String): String =
            if (compact.length <= 3) compact else compact.dropLast(3) + " " + compact.takeLast(3)

        /** Companies House numbers have 8 characters; 1–7 digits are left-padded with zeros. */
        private fun paddedCompanyNumber(compact: String): String =
            if (!compact.isAsciiDigits || compact.length >= 8) compact else "0".repeat(8 - compact.length) + compact

        private fun hyphenated(sortCode: String): String =
            sortCode.substring(0, 2) + "-" + sortCode.substring(2, 4) + "-" + sortCode.substring(4, 6)

        /** ISO 7064 mod 97-10: move the first 4 characters to the end, letters → 10–35, remainder must be 1. */
        private fun ibanChecksumIsValid(iban: String): Boolean {
            val rearranged = iban.drop(4) + iban.take(4)
            var remainder = 0
            for (character in rearranged) {
                remainder = when (character) {
                    in '0'..'9' -> (remainder * 10 + (character - '0')) % 97
                    in 'A'..'Z' -> (remainder * 100 + (character - 'A') + 10) % 97 // two digits, 10–35
                    else -> return false
                }
            }
            return remainder == 1
        }
    }
}

data class FieldValidation(val valid: Boolean, val normalized: String, val error: FieldError? = null)

enum class FieldError(val rawValue: String) { Format("format"), Checksum("checksum") }
