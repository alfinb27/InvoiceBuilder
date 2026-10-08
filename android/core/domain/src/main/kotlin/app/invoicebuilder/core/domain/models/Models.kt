package app.invoicebuilder.core.domain.models

import app.invoicebuilder.core.domain.dates.IsoDate
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.money.Money
import app.invoicebuilder.core.domain.numbering.NumberingReset
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.tax.TaxRate
import kotlinx.serialization.Required
import kotlinx.serialization.Serializable

// Domain records (`spec/schema/domain.schema.json`), the JSON form both apps share (backups, JSON columns).
// Fields that Swift requires when decoding are `@Required` even when they have a default here, so a backup that
// lacks them is rejected the same way on both platforms (`spec/backup.md` §3 check 5).

/** Document types. An open set (`CLAUDE.md` rule 5): a value written by a newer app version is kept. */
@Serializable
@JvmInline
value class DocumentType(val rawValue: String) {
    companion object {
        val invoice = DocumentType("invoice")
        val quote = DocumentType("quote")
        val known = listOf(invoice, quote)
    }
}

/** PDF template ids. An open set. */
@Serializable
@JvmInline
value class TemplateID(val rawValue: String) {
    companion object {
        val classic = TemplateID("classic")
        val modern = TemplateID("modern")
        val minimal = TemplateID("minimal")
        val compact = TemplateID("compact")
        val known = listOf(classic, modern, minimal, compact)
    }
}

/** A postal address (`domain.schema.json#/$defs/address`), stored as JSON on businesses and clients. */
@Serializable
data class Address(
    val line1: String,
    val line2: String? = null,
    val city: String? = null,
    val regionCode: String? = null,
    val postalCode: String? = null,
    val countryCode: String,
) {
    /** One line for lists and document snapshots: `12 MG Road, Bengaluru 560001`. */
    val singleLine: String
        get() {
            val cityLine = listOfNotNull(city?.trimmedOrNull, postalCode?.trimmedOrNull).joinToString(" ")
            return listOfNotNull(line1.trimmedOrNull, line2?.trimmedOrNull, cityLine.trimmedOrNull).joinToString(", ")
        }
}

/** The seller (`domain.schema.json#/$defs/Business`). */
@Serializable
data class Business(
    val id: String,
    @Required val createdAt: Long = 0,
    @Required val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val name: String,
    val legalName: String? = null,
    val address: Address? = null,
    val email: String? = null,
    val phone: String? = null,
    val website: String? = null,
    val countryCode: String,
    /** Tax config family: `IN`, `GB` or `GENERIC` (the file name in `spec/tax`). */
    val taxConfig: String,
    val taxRegistration: String,
    val taxId: String? = null,
    val extraIds: ExtraIDs? = null,
    val homeCurrency: CurrencyCode,
    val turnoverMinor: Long? = null,
    val bank: BankDetails? = null,
    val upiVpa: String? = null,
    @Required val paymentTermsDays: Int = 15,
    val defaultNotes: String? = null,
    val defaultTerms: String? = null,
    @Required val templateId: TemplateID = TemplateID.modern,
    val accentColor: String? = null,
    val logoAssetId: String? = null,
    val signatureAssetId: String? = null,
    val reminderDaysAfterDue: Int? = null,
    val customRates: List<TaxRate>? = null,
) {
    /** The seller's region: from the address, or the GSTIN prefix (`ENGINE.md` Step 0). */
    fun region(config: TaxConfig): String? {
        address?.regionCode?.trimmedOrNull?.let { return it }
        val length = config.taxIDFormat?.regionFromPrefix ?: return null
        val taxId = taxId ?: return null
        return if (taxId.length >= length) taxId.substring(0, length) else null
    }
}

/** Other identifiers printed on documents (`extraIds`). */
@Serializable
data class ExtraIDs(
    val pan: String? = null,
    val companyNumber: String? = null,
    val registeredOffice: String? = null,
    val lutReference: String? = null,
    val lutValidUntil: IsoDate? = null,
) {
    val isEmpty: Boolean
        get() = listOf(pan, companyNumber, registeredOffice, lutReference).all { it == null } && lutValidUntil == null
}

@Serializable
data class BankDetails(
    val accountName: String? = null,
    val accountNumber: String? = null,
    val bankName: String? = null,
    val ifsc: String? = null,
    val sortCode: String? = null,
    val iban: String? = null,
    val swift: String? = null,
) {
    val isEmpty: Boolean
        get() = listOf(accountName, accountNumber, bankName, ifsc, sortCode, iban, swift).all { it == null }
}

/** A customer (`domain.schema.json#/$defs/Client`). */
@Serializable
data class Client(
    val id: String,
    @Required val createdAt: Long = 0,
    @Required val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val businessId: String,
    val name: String,
    val contactName: String? = null,
    val email: String? = null,
    val phone: String? = null,
    val billingAddress: Address? = null,
    val shippingAddress: Address? = null,
    val countryCode: String,
    val regionCode: String? = null,
    val taxId: String? = null,
    /** B2B when true. */
    @Required val isBusiness: Boolean = false,
    /** Null = the business home currency. */
    val defaultCurrency: CurrencyCode? = null,
    val notes: String? = null,
    val archivedAt: Long? = null,
) {
    val isArchived: Boolean get() = archivedAt != null
}

/** Goods or service. An open set. */
@Serializable
@JvmInline
value class ItemKind(val rawValue: String) {
    /** The unit a new item of this kind starts with (`spec/setup.md` §10). */
    val defaultUnit: String get() = if (this == goods) "NOS" else "OTH"

    companion object {
        val goods = ItemKind("goods")
        val service = ItemKind("service")
        val known = listOf(goods, service)
    }
}

/** A product or service in the item catalogue (`domain.schema.json#/$defs/CatalogItem`). */
@Serializable
data class CatalogItem(
    val id: String,
    @Required val createdAt: Long = 0,
    @Required val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val businessId: String,
    val name: String,
    val description: String? = null,
    @Required val kind: ItemKind = ItemKind.service,
    /** A `spec/reference/units.json` id (UQC). */
    val unit: String,
    val unitPriceMinor: Long,
    val currency: CurrencyCode,
    val rateId: String,
    /** HSN/SAC (India) or commodity code. */
    val productCode: String? = null,
    @Required val priceIncludesTax: Boolean = false,
    val archivedAt: Long? = null,
) {
    val isArchived: Boolean get() = archivedAt != null
    val unitPrice: Money get() = Money(unitPriceMinor, currency)
}

/** A document number series (`domain.schema.json#/$defs/NumberingSeries`). Only the owner device advances it. */
@Serializable
data class NumberingSeries(
    val id: String,
    @Required val createdAt: Long = 0,
    @Required val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val businessId: String,
    val docType: DocumentType,
    val label: String,
    val pattern: String,
    val reset: NumberingReset,
    val ownerDeviceId: String,
    /** Period key (`all`, `FY2026`, `CY2026`) → next sequence number. */
    @Required val counters: Map<String, Int> = emptyMap(),
) {
    /** The sequence the next document issued in [periodKey] gets. */
    fun nextSequence(periodKey: String): Int = maxOf(counters[periodKey] ?: 1, 1)
}

/** Logo or signature. An open set. */
@Serializable
@JvmInline
value class AssetKind(val rawValue: String) {
    companion object {
        val logo = AssetKind("logo")
        val signature = AssetKind("signature")
    }
}

/** This device's local row (`device_state`): never synced, never backed up (`spec/setup.md` §2). */
@Serializable
data class DeviceState(
    val id: String,
    val deviceName: String,
    val freeCounterMirror: Long = 0,
    val preferences: DevicePreferences = DevicePreferences(),
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
)

@Serializable
data class DevicePreferences(val activeBusinessId: String? = null, val syncEnabled: Boolean? = null) {
    val isSyncEnabled: Boolean get() = syncEnabled ?: true
}
