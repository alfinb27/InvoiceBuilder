package app.invoicebuilder.core.domain.decimal

/** Why typed text could not be read as an amount or a decimal (`spec/setup.md` §11). */
enum class InputError(val rawValue: String) {
    Empty("empty"), Invalid("invalid"), TooManyDecimals("tooManyDecimals"), TooLarge("tooLarge")
}

/** A result that is either a value or an error code — the counterpart of Swift's `Result<Value, Error>`. */
sealed interface Outcome<out V, out E> {
    data class Success<V>(val value: V) : Outcome<V, Nothing>
    data class Failure<E>(val error: E) : Outcome<Nothing, E>
}

/** Money typed by the user, read into minor units (`spec/setup.md` §11). Never goes through `Double`. */
object MoneyInput {
    /** The largest amount accepted: 10^15 minor units. */
    const val MAX_MINOR_UNITS: Long = 1_000_000_000_000_000

    /** Reads [text] as an amount with [exponent] fraction digits (the currency's `minorUnits`). */
    fun parse(text: String, exponent: Int): Outcome<Long, InputError> {
        val cleaned = text.filter { it != ',' && !it.isWhitespace() }
        if (cleaned.isEmpty()) return Outcome.Failure(InputError.Empty)
        val parts = TypedNumber.of(cleaned) ?: return Outcome.Failure(InputError.Invalid)
        if (parts.fraction.length > exponent) return Outcome.Failure(InputError.TooManyDecimals)
        val integerDigits = parts.integer.trimStart('0')
        // 10^15 minor units has at most 16 integer digits (exponent 0); anything longer is too large.
        if (integerDigits.length > 16) return Outcome.Failure(InputError.TooLarge)
        val digits = integerDigits + parts.fraction + "0".repeat(exponent - parts.fraction.length)
        val minor = (if (digits.isEmpty()) "0" else digits).toLongOrNull() ?: return Outcome.Failure(InputError.TooLarge)
        return if (minor > MAX_MINOR_UNITS) Outcome.Failure(InputError.TooLarge) else Outcome.Success(minor)
    }

    /** Plain text for editing an amount: no grouping, all fraction digits (`123450`, exponent 2 → `"1234.50"`). */
    fun editingText(minor: Long, exponent: Int): String {
        val sign = if (minor < 0) "-" else ""
        var digits = minor.toBigInteger().abs().toString()
        if (exponent <= 0) return sign + digits
        if (digits.length <= exponent) digits = "0".repeat(exponent + 1 - digits.length) + digits
        val split = digits.length - exponent
        return sign + digits.substring(0, split) + "." + digits.substring(split)
    }
}

/** A quantity or percent typed by the user, read into a canonical decimal string (`spec/setup.md` §11). */
object DecimalInput {
    fun parse(text: String): Outcome<String, InputError> {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return Outcome.Failure(InputError.Empty)
        val parts = TypedNumber.of(trimmed) ?: return Outcome.Failure(InputError.Invalid)
        val integer = parts.integer.trimStart('0')
        val fraction = parts.fraction.trimEnd('0')
        val whole = integer.ifEmpty { "0" }
        return Outcome.Success(if (fraction.isEmpty()) whole else "$whole.$fraction")
    }
}

/** `^[0-9]+(\.[0-9]*)?$` or `^\.[0-9]+$`, split into its digit runs. */
private class TypedNumber(val integer: String, val fraction: String) {
    companion object {
        fun of(text: String): TypedNumber? {
            val pieces = text.split('.')
            if (pieces.size > 2) return null
            val integer = pieces[0]
            val fraction = if (pieces.size == 2) pieces[1] else ""
            if (!integer.all { it in '0'..'9' } || !fraction.all { it in '0'..'9' }) return null
            if (integer.isEmpty() && fraction.isEmpty()) return null // "." alone
            return TypedNumber(integer, fraction)
        }
    }
}
