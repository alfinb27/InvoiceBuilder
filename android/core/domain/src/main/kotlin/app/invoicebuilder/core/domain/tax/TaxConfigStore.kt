package app.invoicebuilder.core.domain.tax

import app.invoicebuilder.core.domain.support.SpecJson
import app.invoicebuilder.core.domain.support.SpecLoadingError
import app.invoicebuilder.core.domain.support.SpecResources
import java.time.LocalDate

/** Every tax config the app knows, loaded from `spec/tax/<family>.json` (bundled by `make sync-spec`). iOS: `TaxConfigStore`. */
class TaxConfigStore(configs: List<TaxConfig>) {
    /** Sorted by family, then `configVersion`. */
    val configs: List<TaxConfig> = configs.sortedWith(compareBy<TaxConfig>({ it.family }, { it.configVersion }))

    /** `IN@2025-09-22` → that exact config version. */
    fun config(ref: String): TaxConfig? = configs.firstOrNull { it.ref == ref }

    /**
     * The newest version of a family in effect on [date] (the newest overall when [date] is null, or when every
     * version is newer than [date]).
     */
    fun latest(family: String, date: LocalDate? = null): TaxConfig? {
        val versions = configs.filter { it.family == family }
        if (date == null) return versions.lastOrNull()
        return versions.lastOrNull { it.configVersion <= date } ?: versions.firstOrNull()
    }

    companion object {
        /**
         * The files in `spec/tax`. Classpath resources (and APK assets) cannot be listed, so the names live here;
         * `TaxConfigStoreTest` fails when a file in `spec/tax` is missing from this list.
         */
        val bundledFiles = listOf("IN.json", "GB.json", "GENERIC.json")

        fun bundled(): TaxConfigStore = TaxConfigStore(bundledFiles.map { name ->
            try {
                SpecJson.decodeFromString(TaxConfig.serializer(), SpecResources.text("tax/$name"))
            } catch (error: Exception) {
                throw SpecLoadingError("tax/$name", error.message ?: error.toString())
            }
        })

        /** The config family a business in [countryCode] uses: `IN`, `GB`, or `GENERIC` (`spec/setup.md` §3). */
        fun family(countryCode: String): String = if (countryCode == "IN" || countryCode == "GB") countryCode else "GENERIC"
    }
}
