package app.invoicebuilder.core.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

// Room entities, one per table of `spec/schema/db/schema.sql`, generated from it (iOS: InvoiceData's records). The
// database itself is created by the spec's SQL migrations (`SpecMigrator`); Room only checks, every time it opens
// the file, that these declarations match what the SQL built — so the two cannot drift. `RoomSchemaTest` also
// opens a fresh database and compares it with `schema.sql`.

@Entity(
    tableName = "business",
)
data class BusinessEntity(
    @PrimaryKey @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "legal_name") val legalName: String?,
    @ColumnInfo(name = "address") val address: String?,
    @ColumnInfo(name = "email") val email: String?,
    @ColumnInfo(name = "phone") val phone: String?,
    @ColumnInfo(name = "website") val website: String?,
    @ColumnInfo(name = "country_code") val countryCode: String,
    @ColumnInfo(name = "tax_config") val taxConfig: String,
    @ColumnInfo(name = "tax_registration") val taxRegistration: String,
    @ColumnInfo(name = "tax_id") val taxId: String?,
    @ColumnInfo(name = "extra_ids") val extraIds: String?,
    @ColumnInfo(name = "home_currency") val homeCurrency: String,
    @ColumnInfo(name = "turnover_minor") val turnoverMinor: Long?,
    @ColumnInfo(name = "bank") val bank: String?,
    @ColumnInfo(name = "upi_vpa") val upiVpa: String?,
    @ColumnInfo(name = "payment_terms_days", defaultValue = "15") val paymentTermsDays: Int,
    @ColumnInfo(name = "default_notes") val defaultNotes: String?,
    @ColumnInfo(name = "default_terms") val defaultTerms: String?,
    @ColumnInfo(name = "template_id", defaultValue = "'modern'") val templateId: String,
    @ColumnInfo(name = "accent_color") val accentColor: String?,
    @ColumnInfo(name = "logo_asset_id") val logoAssetId: String?,
    @ColumnInfo(name = "signature_asset_id") val signatureAssetId: String?,
    @ColumnInfo(name = "reminder_days_after_due") val reminderDaysAfterDue: Int?,
    @ColumnInfo(name = "custom_rates") val customRates: String?,
    @ColumnInfo(name = "created_at") val createdAt: Long,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "deleted_at") val deletedAt: Long?,
)

@Entity(
    tableName = "asset",
    foreignKeys = [
        ForeignKey(entity = BusinessEntity::class, parentColumns = ["id"], childColumns = ["business_id"], onDelete = ForeignKey.CASCADE),
    ],
    indices = [
        Index(value = ["business_id"], name = "idx_asset_business"),
    ],
)
data class AssetEntity(
    @PrimaryKey @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "business_id") val businessId: String,
    @ColumnInfo(name = "kind") val kind: String,
    @ColumnInfo(name = "mime") val mime: String,
    @ColumnInfo(name = "sha256") val sha256: String,
    @ColumnInfo(name = "data") val data: ByteArray,
    @ColumnInfo(name = "created_at") val createdAt: Long,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "deleted_at") val deletedAt: Long?,
)

@Entity(
    tableName = "client",
    foreignKeys = [
        ForeignKey(entity = BusinessEntity::class, parentColumns = ["id"], childColumns = ["business_id"], onDelete = ForeignKey.CASCADE),
    ],
    indices = [
        Index(value = ["business_id", "name"], name = "idx_client_business"),
    ],
)
data class ClientEntity(
    @PrimaryKey @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "business_id") val businessId: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "contact_name") val contactName: String?,
    @ColumnInfo(name = "email") val email: String?,
    @ColumnInfo(name = "phone") val phone: String?,
    @ColumnInfo(name = "billing_address") val billingAddress: String?,
    @ColumnInfo(name = "shipping_address") val shippingAddress: String?,
    @ColumnInfo(name = "country_code") val countryCode: String,
    @ColumnInfo(name = "region_code") val regionCode: String?,
    @ColumnInfo(name = "tax_id") val taxId: String?,
    @ColumnInfo(name = "is_business", defaultValue = "0") val isBusiness: Boolean,
    @ColumnInfo(name = "default_currency") val defaultCurrency: String?,
    @ColumnInfo(name = "notes") val notes: String?,
    @ColumnInfo(name = "archived_at") val archivedAt: Long?,
    @ColumnInfo(name = "created_at") val createdAt: Long,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "deleted_at") val deletedAt: Long?,
)

@Entity(
    tableName = "catalog_item",
    foreignKeys = [
        ForeignKey(entity = BusinessEntity::class, parentColumns = ["id"], childColumns = ["business_id"], onDelete = ForeignKey.CASCADE),
    ],
    indices = [
        Index(value = ["business_id", "name"], name = "idx_catalog_item_business"),
    ],
)
data class CatalogItemEntity(
    @PrimaryKey @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "business_id") val businessId: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "description") val description: String?,
    @ColumnInfo(name = "kind") val kind: String,
    @ColumnInfo(name = "unit") val unit: String,
    @ColumnInfo(name = "unit_price_minor") val unitPriceMinor: Long,
    @ColumnInfo(name = "currency") val currency: String,
    @ColumnInfo(name = "rate_id") val rateId: String,
    @ColumnInfo(name = "product_code") val productCode: String?,
    @ColumnInfo(name = "price_includes_tax", defaultValue = "0") val priceIncludesTax: Boolean,
    @ColumnInfo(name = "archived_at") val archivedAt: Long?,
    @ColumnInfo(name = "created_at") val createdAt: Long,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "deleted_at") val deletedAt: Long?,
)

@Entity(
    tableName = "numbering_series",
    foreignKeys = [
        ForeignKey(entity = BusinessEntity::class, parentColumns = ["id"], childColumns = ["business_id"], onDelete = ForeignKey.CASCADE),
    ],
    indices = [
        Index(value = ["business_id", "doc_type"], name = "idx_numbering_series_business"),
    ],
)
data class NumberingSeriesEntity(
    @PrimaryKey @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "business_id") val businessId: String,
    @ColumnInfo(name = "doc_type") val docType: String,
    @ColumnInfo(name = "label") val label: String,
    @ColumnInfo(name = "pattern") val pattern: String,
    @ColumnInfo(name = "reset") val reset: String,
    @ColumnInfo(name = "owner_device_id") val ownerDeviceId: String,
    @ColumnInfo(name = "counters", defaultValue = "'{}'") val counters: String,
    @ColumnInfo(name = "created_at") val createdAt: Long,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "deleted_at") val deletedAt: Long?,
)

@Entity(
    tableName = "document",
    foreignKeys = [
        ForeignKey(entity = BusinessEntity::class, parentColumns = ["id"], childColumns = ["business_id"], onDelete = ForeignKey.CASCADE),
        ForeignKey(entity = NumberingSeriesEntity::class, parentColumns = ["id"], childColumns = ["series_id"], onDelete = ForeignKey.SET_NULL),
        ForeignKey(entity = ClientEntity::class, parentColumns = ["id"], childColumns = ["client_id"], onDelete = ForeignKey.SET_NULL),
    ],
    indices = [
        Index(value = ["client_id"], name = "idx_document_client"),
        Index(value = ["business_id", "doc_type", "lifecycle", "issue_date"], name = "idx_document_list"),
        Index(value = ["business_id", "number"], name = "idx_document_number"),
    ],
)
data class DocumentEntity(
    @PrimaryKey @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "business_id") val businessId: String,
    @ColumnInfo(name = "doc_type") val docType: String,
    @ColumnInfo(name = "number") val number: String?,
    @ColumnInfo(name = "series_id") val seriesId: String?,
    @ColumnInfo(name = "period_key") val periodKey: String?,
    @ColumnInfo(name = "lifecycle", defaultValue = "'draft'") val lifecycle: String,
    @ColumnInfo(name = "issue_date") val issueDate: String,
    @ColumnInfo(name = "supply_date") val supplyDate: String?,
    @ColumnInfo(name = "due_date") val dueDate: String?,
    @ColumnInfo(name = "valid_until") val validUntil: String?,
    @ColumnInfo(name = "sent_at") val sentAt: Long?,
    @ColumnInfo(name = "voided_at") val voidedAt: Long?,
    @ColumnInfo(name = "void_reason") val voidReason: String?,
    @ColumnInfo(name = "quote_outcome") val quoteOutcome: String?,
    @ColumnInfo(name = "converted_from_id") val convertedFromId: String?,
    @ColumnInfo(name = "currency") val currency: String,
    @ColumnInfo(name = "exchange_rate") val exchangeRate: String?,
    @ColumnInfo(name = "supply_type") val supplyType: String,
    @ColumnInfo(name = "place_of_supply") val placeOfSupply: String?,
    @ColumnInfo(name = "reverse_charge", defaultValue = "0") val reverseCharge: Boolean,
    @ColumnInfo(name = "prices_include_tax", defaultValue = "0") val pricesIncludeTax: Boolean,
    @ColumnInfo(name = "round_off") val roundOff: Boolean?,
    @ColumnInfo(name = "client_id") val clientId: String?,
    @ColumnInfo(name = "seller_snapshot") val sellerSnapshot: String?,
    @ColumnInfo(name = "buyer_snapshot") val buyerSnapshot: String?,
    @ColumnInfo(name = "discount") val discount: String?,
    @ColumnInfo(name = "shipping_minor", defaultValue = "0") val shippingMinor: Long,
    @ColumnInfo(name = "notes") val notes: String?,
    @ColumnInfo(name = "terms") val terms: String?,
    @ColumnInfo(name = "template_id", defaultValue = "'modern'") val templateId: String,
    @ColumnInfo(name = "tax_config_ref") val taxConfigRef: String,
    @ColumnInfo(name = "revision", defaultValue = "0") val revision: Int,
    @ColumnInfo(name = "subtotal_minor", defaultValue = "0") val subtotalMinor: Long,
    @ColumnInfo(name = "discount_minor", defaultValue = "0") val discountMinor: Long,
    @ColumnInfo(name = "taxable_minor", defaultValue = "0") val taxableMinor: Long,
    @ColumnInfo(name = "tax_minor", defaultValue = "0") val taxMinor: Long,
    @ColumnInfo(name = "tax_not_charged_minor", defaultValue = "0") val taxNotChargedMinor: Long,
    @ColumnInfo(name = "round_off_minor", defaultValue = "0") val roundOffMinor: Long,
    @ColumnInfo(name = "total_minor", defaultValue = "0") val totalMinor: Long,
    @ColumnInfo(name = "computed") val computed: String?,
    @ColumnInfo(name = "created_at") val createdAt: Long,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "deleted_at") val deletedAt: Long?,
    @ColumnInfo(name = "sequence") val sequence: Int?,
    @ColumnInfo(name = "reminder_days_after_due_override") val reminderDaysAfterDueOverride: Int?,
)

@Entity(
    tableName = "line_item",
    foreignKeys = [
        ForeignKey(entity = DocumentEntity::class, parentColumns = ["id"], childColumns = ["document_id"], onDelete = ForeignKey.CASCADE),
        ForeignKey(entity = CatalogItemEntity::class, parentColumns = ["id"], childColumns = ["catalog_item_id"], onDelete = ForeignKey.SET_NULL),
    ],
    indices = [
        Index(value = ["document_id", "position"], name = "idx_line_item_document"),
    ],
)
data class LineItemEntity(
    @PrimaryKey @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "document_id") val documentId: String,
    @ColumnInfo(name = "position") val position: Int,
    @ColumnInfo(name = "catalog_item_id") val catalogItemId: String?,
    @ColumnInfo(name = "description") val description: String,
    @ColumnInfo(name = "product_code") val productCode: String?,
    @ColumnInfo(name = "unit") val unit: String?,
    @ColumnInfo(name = "quantity") val quantity: String,
    @ColumnInfo(name = "unit_price_minor") val unitPriceMinor: Long,
    @ColumnInfo(name = "discount") val discount: String?,
    @ColumnInfo(name = "rate_id") val rateId: String,
    @ColumnInfo(name = "rate_snapshot") val rateSnapshot: String?,
    @ColumnInfo(name = "amount_minor") val amountMinor: Long?,
    @ColumnInfo(name = "taxable_minor") val taxableMinor: Long?,
    @ColumnInfo(name = "tax_minor") val taxMinor: Long?,
    @ColumnInfo(name = "total_minor") val totalMinor: Long?,
    @ColumnInfo(name = "created_at") val createdAt: Long,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "deleted_at") val deletedAt: Long?,
)

@Entity(
    tableName = "tax_line",
    foreignKeys = [
        ForeignKey(entity = DocumentEntity::class, parentColumns = ["id"], childColumns = ["document_id"], onDelete = ForeignKey.CASCADE),
        ForeignKey(entity = LineItemEntity::class, parentColumns = ["id"], childColumns = ["line_id"], onDelete = ForeignKey.CASCADE),
    ],
    indices = [
        Index(value = ["document_id"], name = "idx_tax_line_document"),
    ],
)
data class TaxLineEntity(
    @PrimaryKey @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "document_id") val documentId: String,
    @ColumnInfo(name = "line_id") val lineId: String?,
    @ColumnInfo(name = "component") val component: String?,
    @ColumnInfo(name = "rate") val rate: String,
    @ColumnInfo(name = "category") val category: String,
    @ColumnInfo(name = "taxable_minor") val taxableMinor: Long,
    @ColumnInfo(name = "tax_minor") val taxMinor: Long,
    @ColumnInfo(name = "charged", defaultValue = "1") val charged: Boolean,
    @ColumnInfo(name = "created_at") val createdAt: Long,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "deleted_at") val deletedAt: Long?,
)

@Entity(
    tableName = "payment",
    foreignKeys = [
        ForeignKey(entity = BusinessEntity::class, parentColumns = ["id"], childColumns = ["business_id"], onDelete = ForeignKey.CASCADE),
        ForeignKey(entity = DocumentEntity::class, parentColumns = ["id"], childColumns = ["document_id"], onDelete = ForeignKey.CASCADE),
    ],
    indices = [
        Index(value = ["document_id"], name = "idx_payment_document"),
    ],
)
data class PaymentEntity(
    @PrimaryKey @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "business_id") val businessId: String,
    @ColumnInfo(name = "document_id") val documentId: String,
    @ColumnInfo(name = "amount_minor") val amountMinor: Long,
    @ColumnInfo(name = "date") val date: String,
    @ColumnInfo(name = "method") val method: String,
    @ColumnInfo(name = "reference") val reference: String?,
    @ColumnInfo(name = "note") val note: String?,
    @ColumnInfo(name = "created_at") val createdAt: Long,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "deleted_at") val deletedAt: Long?,
)

@Entity(
    tableName = "device_state",
)
data class DeviceStateEntity(
    @PrimaryKey @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "device_name") val deviceName: String,
    @ColumnInfo(name = "free_counter_mirror", defaultValue = "0") val freeCounterMirror: Long,
    @ColumnInfo(name = "preferences", defaultValue = "'{}'") val preferences: String,
    @ColumnInfo(name = "created_at") val createdAt: Long,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
)

@Entity(
    tableName = "app_state",
)
data class AppStateEntity(
    @PrimaryKey @ColumnInfo(name = "key") val key: String,
    @ColumnInfo(name = "value") val value: String,
)
