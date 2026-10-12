package app.invoicebuilder.core.domain.support

/**
 * Whole-string matching for the regular expressions written in the spec (tax ID formats, numbering rules, field
 * rules). The patterns use a subset that ICU, JavaScript and java.util.regex read the same way. iOS: `SpecRegex`.
 */
object SpecRegex {
    private val cache = java.util.concurrent.ConcurrentHashMap<String, Regex?>()

    /** True when [pattern] matches all of [text]. An invalid pattern never matches. */
    fun matches(pattern: String, text: String): Boolean {
        val regex = cache.getOrPut(pattern) { runCatching { Regex(pattern) }.getOrNull() } ?: return false
        return regex.matchEntire(text) != null
    }
}

/** Removes every whitespace or newline character, including those inside the string. */
val String.removingWhitespace: String get() = filterNot { it.isWhitespace() }

/** Trimmed text, or null when nothing is left (optional fields store NULL, `spec/setup.md` §1). */
val String.trimmedOrNull: String? get() = trim().ifEmpty { null }

/** True when every character is an ASCII digit (and the string is not empty). */
val String.isAsciiDigits: Boolean get() = isNotEmpty() && all { it in '0'..'9' }
