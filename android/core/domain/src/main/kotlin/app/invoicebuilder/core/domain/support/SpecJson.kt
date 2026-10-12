package app.invoicebuilder.core.domain.support

import kotlinx.serialization.json.Json

/**
 * The JSON settings every spec file and stored JSON column uses (≈ Swift's `JSONDecoder`/`JSONEncoder` with
 * synthesized `Codable`): unknown keys are ignored (a newer app may add some), absent optionals decode as null and
 * nulls are left out when encoding.
 */
val SpecJson: Json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
}

/** The runtime copy of `spec/` bundled into `:core:domain` by `make sync-spec` (iOS: `SpecResources`). */
object SpecResources {
    fun text(relativePath: String): String {
        val stream = SpecResources::class.java.getResourceAsStream("/spec/$relativePath")
            ?: throw SpecLoadingError(relativePath, "not bundled; run `make sync-spec`")
        return stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
    }

    fun bytes(relativePath: String): ByteArray {
        val stream = SpecResources::class.java.getResourceAsStream("/spec/$relativePath")
            ?: throw SpecLoadingError(relativePath, "not bundled; run `make sync-spec`")
        return stream.use { it.readBytes() }
    }
}

/** A spec file that is missing or does not match its schema. */
class SpecLoadingError(val path: String, val reason: String) : Exception("$path: $reason")
