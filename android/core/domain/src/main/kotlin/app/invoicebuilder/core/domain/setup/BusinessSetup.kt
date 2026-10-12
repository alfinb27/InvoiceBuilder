package app.invoicebuilder.core.domain.setup

import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.models.DevicePreferences
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.models.NumberingSeries
import app.invoicebuilder.core.domain.tax.TaxConfig

/** Pure parts of creating a business and choosing the active one (`spec/setup.md` §2–3, §6). iOS: `BusinessSetup`. */
object BusinessSetup {
    /** One series per document type from the config's patterns, owned by this device. */
    fun defaultSeries(businessID: String, config: TaxConfig, ownerDeviceID: String, now: Long, newID: () -> String): List<NumberingSeries> =
        listOf(DocumentType.invoice to "Invoices", DocumentType.quote to "Quotes").map { (docType, label) ->
            NumberingSeries(
                id = newID(), createdAt = now, updatedAt = now, businessId = businessID, docType = docType, label = label,
                pattern = config.numberingPattern(docType), reset = config.numbering.reset, ownerDeviceId = ownerDeviceID,
            )
        }

    /** `preferences.activeBusinessId` when it names a live business; otherwise the earliest-created live business. */
    fun activeBusiness(preferences: DevicePreferences, businesses: List<Business>): Business? {
        val live = businesses.filter { it.deletedAt == null }
        preferences.activeBusinessId?.let { id -> live.firstOrNull { it.id == id }?.let { return it } }
        return live.minWithOrNull(compareBy<Business>({ it.createdAt }, { it.id }))
    }
}

/** List and picker search (`spec/setup.md` §5, §10): case-insensitive substring match, sorted by name then id. */
object SetupSearch {
    fun clients(clients: List<Client>, query: String): List<Client> =
        filter(clients, query, { it.name }, { it.id }) { listOf(it.name, it.contactName, it.email, it.phone, it.taxId) }

    fun items(items: List<CatalogItem>, query: String): List<CatalogItem> =
        filter(items, query, { it.name }, { it.id }) { listOf(it.name, it.description, it.productCode) }

    private fun <T> filter(rows: List<T>, query: String, name: (T) -> String, id: (T) -> String, fields: (T) -> List<String?>): List<T> {
        val needle = query.trim()
        val matches = if (needle.isEmpty()) rows else rows.filter { row -> fields(row).any { it?.contains(needle, ignoreCase = true) == true } }
        return matches.sortedWith(compareBy<T, String>(String.CASE_INSENSITIVE_ORDER) { name(it) }.thenBy { id(it) })
    }
}
