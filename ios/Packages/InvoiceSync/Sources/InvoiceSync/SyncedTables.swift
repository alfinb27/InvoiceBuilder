import Foundation
import SQLiteData

// The synced tables as SQLiteData sees them (`spec/sync.md` §1): one `@Table` per table, one property per column,
// generated from `spec/schema/db/schema.sql`. The app reads and writes through GRDB records in InvoiceData; these
// types exist only so `SyncEngine` knows every column to send. `TableMirrorTests` fails when they drift from the
// schema. Booleans stay `Int64` (0/1): the engine copies values, it never interprets them.

@Table("business")
struct SyncedBusiness: Hashable, Sendable {
    var id: String
    var name: String
    @Column("legal_name")
    var legalName: String?
    var address: String?
    var email: String?
    var phone: String?
    var website: String?
    @Column("country_code")
    var countryCode: String
    @Column("tax_config")
    var taxConfig: String
    @Column("tax_registration")
    var taxRegistration: String
    @Column("tax_id")
    var taxId: String?
    @Column("extra_ids")
    var extraIds: String?
    @Column("home_currency")
    var homeCurrency: String
    @Column("turnover_minor")
    var turnoverMinor: Int64?
    var bank: String?
    @Column("upi_vpa")
    var upiVpa: String?
    @Column("payment_terms_days")
    var paymentTermsDays: Int64
    @Column("default_notes")
    var defaultNotes: String?
    @Column("default_terms")
    var defaultTerms: String?
    @Column("template_id")
    var templateId: String
    @Column("accent_color")
    var accentColor: String?
    @Column("logo_asset_id")
    var logoAssetId: String?
    @Column("signature_asset_id")
    var signatureAssetId: String?
    @Column("reminder_days_after_due")
    var reminderDaysAfterDue: Int64?
    @Column("custom_rates")
    var customRates: String?
    @Column("created_at")
    var createdAt: Int64
    @Column("updated_at")
    var updatedAt: Int64
    @Column("deleted_at")
    var deletedAt: Int64?
}

@Table("asset")
struct SyncedAsset: Hashable, Sendable {
    var id: String
    @Column("business_id")
    var businessId: String
    var kind: String
    var mime: String
    var sha256: String
    var data: Data
    @Column("created_at")
    var createdAt: Int64
    @Column("updated_at")
    var updatedAt: Int64
    @Column("deleted_at")
    var deletedAt: Int64?
}

@Table("client")
struct SyncedClient: Hashable, Sendable {
    var id: String
    @Column("business_id")
    var businessId: String
    var name: String
    @Column("contact_name")
    var contactName: String?
    var email: String?
    var phone: String?
    @Column("billing_address")
    var billingAddress: String?
    @Column("shipping_address")
    var shippingAddress: String?
    @Column("country_code")
    var countryCode: String
    @Column("region_code")
    var regionCode: String?
    @Column("tax_id")
    var taxId: String?
    @Column("is_business")
    var isBusiness: Int64
    @Column("default_currency")
    var defaultCurrency: String?
    var notes: String?
    @Column("archived_at")
    var archivedAt: Int64?
    @Column("created_at")
    var createdAt: Int64
    @Column("updated_at")
    var updatedAt: Int64
    @Column("deleted_at")
    var deletedAt: Int64?
}

@Table("catalog_item")
struct SyncedCatalogItem: Hashable, Sendable {
    var id: String
    @Column("business_id")
    var businessId: String
    var name: String
    @Column("description")
    var descriptionText: String?
    var kind: String
    var unit: String
    @Column("unit_price_minor")
    var unitPriceMinor: Int64
    var currency: String
    @Column("rate_id")
    var rateId: String
    @Column("product_code")
    var productCode: String?
    @Column("price_includes_tax")
    var priceIncludesTax: Int64
    @Column("archived_at")
    var archivedAt: Int64?
    @Column("created_at")
    var createdAt: Int64
    @Column("updated_at")
    var updatedAt: Int64
    @Column("deleted_at")
    var deletedAt: Int64?
}

@Table("numbering_series")
struct SyncedNumberingSeries: Hashable, Sendable {
    var id: String
    @Column("business_id")
    var businessId: String
    @Column("doc_type")
    var docType: String
    var label: String
    var pattern: String
    var reset: String
    @Column("owner_device_id")
    var ownerDeviceId: String
    var counters: String
    @Column("created_at")
    var createdAt: Int64
    @Column("updated_at")
    var updatedAt: Int64
    @Column("deleted_at")
    var deletedAt: Int64?
}

@Table("document")
struct SyncedDocument: Hashable, Sendable {
    var id: String
    @Column("business_id")
    var businessId: String
    @Column("doc_type")
    var docType: String
    var number: String?
    @Column("series_id")
    var seriesId: String?
    @Column("period_key")
    var periodKey: String?
    var lifecycle: String
    @Column("issue_date")
    var issueDate: String
    @Column("supply_date")
    var supplyDate: String?
    @Column("due_date")
    var dueDate: String?
    @Column("valid_until")
    var validUntil: String?
    @Column("sent_at")
    var sentAt: Int64?
    @Column("voided_at")
    var voidedAt: Int64?
    @Column("void_reason")
    var voidReason: String?
    @Column("quote_outcome")
    var quoteOutcome: String?
    @Column("converted_from_id")
    var convertedFromId: String?
    var currency: String
    @Column("exchange_rate")
    var exchangeRate: String?
    @Column("supply_type")
    var supplyType: String
    @Column("place_of_supply")
    var placeOfSupply: String?
    @Column("reverse_charge")
    var reverseCharge: Int64
    @Column("prices_include_tax")
    var pricesIncludeTax: Int64
    @Column("round_off")
    var roundOff: Int64?
    @Column("client_id")
    var clientId: String?
    @Column("seller_snapshot")
    var sellerSnapshot: String?
    @Column("buyer_snapshot")
    var buyerSnapshot: String?
    var discount: String?
    @Column("shipping_minor")
    var shippingMinor: Int64
    var notes: String?
    var terms: String?
    @Column("template_id")
    var templateId: String
    @Column("tax_config_ref")
    var taxConfigRef: String
    var revision: Int64
    @Column("subtotal_minor")
    var subtotalMinor: Int64
    @Column("discount_minor")
    var discountMinor: Int64
    @Column("taxable_minor")
    var taxableMinor: Int64
    @Column("tax_minor")
    var taxMinor: Int64
    @Column("tax_not_charged_minor")
    var taxNotChargedMinor: Int64
    @Column("round_off_minor")
    var roundOffMinor: Int64
    @Column("total_minor")
    var totalMinor: Int64
    var computed: String?
    @Column("created_at")
    var createdAt: Int64
    @Column("updated_at")
    var updatedAt: Int64
    @Column("deleted_at")
    var deletedAt: Int64?
    var sequence: Int64?
    @Column("reminder_days_after_due_override")
    var reminderDaysAfterDueOverride: Int64?
}

@Table("line_item")
struct SyncedLineItem: Hashable, Sendable {
    var id: String
    @Column("document_id")
    var documentId: String
    var position: Int64
    @Column("catalog_item_id")
    var catalogItemId: String?
    @Column("description")
    var descriptionText: String
    @Column("product_code")
    var productCode: String?
    var unit: String?
    var quantity: String
    @Column("unit_price_minor")
    var unitPriceMinor: Int64
    var discount: String?
    @Column("rate_id")
    var rateId: String
    @Column("rate_snapshot")
    var rateSnapshot: String?
    @Column("amount_minor")
    var amountMinor: Int64?
    @Column("taxable_minor")
    var taxableMinor: Int64?
    @Column("tax_minor")
    var taxMinor: Int64?
    @Column("total_minor")
    var totalMinor: Int64?
    @Column("created_at")
    var createdAt: Int64
    @Column("updated_at")
    var updatedAt: Int64
    @Column("deleted_at")
    var deletedAt: Int64?
}

@Table("tax_line")
struct SyncedTaxLine: Hashable, Sendable {
    var id: String
    @Column("document_id")
    var documentId: String
    @Column("line_id")
    var lineId: String?
    var component: String?
    var rate: String
    var category: String
    @Column("taxable_minor")
    var taxableMinor: Int64
    @Column("tax_minor")
    var taxMinor: Int64
    var charged: Int64
    @Column("created_at")
    var createdAt: Int64
    @Column("updated_at")
    var updatedAt: Int64
    @Column("deleted_at")
    var deletedAt: Int64?
}

@Table("payment")
struct SyncedPayment: Hashable, Sendable {
    var id: String
    @Column("business_id")
    var businessId: String
    @Column("document_id")
    var documentId: String
    @Column("amount_minor")
    var amountMinor: Int64
    var date: String
    var method: String
    var reference: String?
    var note: String?
    @Column("created_at")
    var createdAt: Int64
    @Column("updated_at")
    var updatedAt: Int64
    @Column("deleted_at")
    var deletedAt: Int64?
}

/// Every synced table, in the order they are registered with the sync engine (parents first).
enum SyncedTables {
    static let names = ["business", "asset", "client", "catalog_item", "numbering_series", "document", "line_item", "tax_line", "payment"]
}
