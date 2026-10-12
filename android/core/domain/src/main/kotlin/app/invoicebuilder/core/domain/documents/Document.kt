package app.invoicebuilder.core.domain.documents

import app.invoicebuilder.core.domain.dates.IsoDate
import app.invoicebuilder.core.domain.models.Address
import app.invoicebuilder.core.domain.models.BankDetails
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.models.ExtraIDs
import app.invoicebuilder.core.domain.models.TemplateID
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.tax.ComputedDocument
import app.invoicebuilder.core.domain.tax.ComputedTotals
import app.invoicebuilder.core.domain.tax.Discount
import app.invoicebuilder.core.domain.tax.EngineBuyer
import app.invoicebuilder.core.domain.tax.EngineSeller
import app.invoicebuilder.core.domain.tax.TaxCategory
import app.invoicebuilder.core.domain.tax.TaxRate
import kotlinx.serialization.Required
import kotlinx.serialization.Serializable
import java.time.LocalDate

/**
 * An invoice or quote (`domain.schema.json#/$defs/Document`, `spec/documents.md`). Drafts are edited in place and
 * autosaved; issuing freezes the snapshots, allocates the number and stores the engine result. iOS: `Document`.
 */
@Serializable
data class Document(
    val id: String,
    @Required val createdAt: Long = 0,
    @Required val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val businessId: String,
    val docType: DocumentType,
    /** Null until issued. */
    val number: String? = null,
    val seriesId: String? = null,
    val periodKey: String? = null,
    /** The sequence allocated at issue (`spec/documents.md` §6). */
    val sequence: Int? = null,
    @Required val lifecycle: DocumentLifecycle = DocumentLifecycle.draft,
    val issueDate: IsoDate,
    /** Tax point; selects the rates in force. */
    val supplyDate: IsoDate? = null,
    val dueDate: IsoDate? = null,
    /** Overrides `business.reminderDaysAfterDue` for this invoice (`spec/reminders.md` §1); null defers to it. */
    val reminderDaysAfterDueOverride: Int? = null,
    /** Quotes only. */
    val validUntil: IsoDate? = null,
    val sentAt: Long? = null,
    val voidedAt: Long? = null,
    val voidReason: String? = null,
    val quoteOutcome: QuoteOutcome? = null,
    /** The quote this invoice was converted from. */
    val convertedFromId: String? = null,
    val currency: CurrencyCode,
    /** Units of home currency per 1 unit of `currency` (decimal string). */
    val exchangeRate: String? = null,
    val supplyType: String,
    /** Overrides the derived place of supply (region code). */
    val placeOfSupply: String? = null,
    @Required val reverseCharge: Boolean = false,
    @Required val pricesIncludeTax: Boolean = false,
    /** Null = the config's default. */
    val roundOff: Boolean? = null,
    val clientId: String? = null,
    val sellerSnapshot: SellerSnapshot? = null,
    val buyerSnapshot: BuyerSnapshot? = null,
    val discount: Discount? = null,
    @Required val shippingMinor: Long = 0,
    val notes: String? = null,
    val terms: String? = null,
    @Required val templateId: TemplateID = TemplateID.modern,
    /** `<family>@<configVersion>` of the tax config applied. */
    val taxConfigRef: String,
    /** 0 for drafts; 1 once issued. */
    @Required val revision: Int = 0,
    @Required val lines: List<LineItem> = emptyList(),
    @Required val totals: DocumentTotals = DocumentTotals.zero,
    /** The full engine result, stored at issue. */
    val computed: ComputedDocument? = null,
) {
    val isDraft: Boolean get() = lifecycle == DocumentLifecycle.draft

    /** The date that selects the rates and config version in force (`ENGINE.md` Step 0). */
    val effectiveDate: LocalDate get() = supplyDate ?: issueDate

    /** Derived display status (`ENGINE.md` §6). [paid] is the sum of the invoice's live payments. */
    fun status(today: LocalDate, paid: Long = 0): DocumentStatus = DocumentStatus.derive(statusInput(today, paid))

    fun statusInput(today: LocalDate, paid: Long = 0) = DocumentStatus.Input(
        docType, lifecycle, totals.totalMinor, paid, dueDate, validUntil, sentAt, quoteOutcome, today,
    )
}

/** A document line (`domain.schema.json#/$defs/LineItem`). The computed columns are filled at issue. */
@Serializable
data class LineItem(
    val id: String,
    @Required val position: Int = 0,
    val catalogItemId: String? = null,
    @Required val description: String = "",
    val productCode: String? = null,
    /** A `reference/units.json` id. */
    val unit: String? = null,
    /** Decimal string. */
    @Required val quantity: String = "1",
    @Required val unitPriceMinor: Long = 0,
    val discount: Discount? = null,
    /** Empty until a rate is chosen (a one-off line with no previous line). */
    @Required val rateId: String = "",
    val rateSnapshot: RateSnapshot? = null,
    val amountMinor: Long? = null,
    val taxableMinor: Long? = null,
    val taxMinor: Long? = null,
    val totalMinor: Long? = null,
) {
    /** The same line without the results stored at issue (drafts, duplicates). */
    val clearingComputed: LineItem
        get() = copy(rateSnapshot = null, amountMinor = null, taxableMinor = null, taxMinor = null, totalMinor = null)
}

/** The rate as applied at issue: `{ percent, category, label }`. */
@Serializable
data class RateSnapshot(val percent: String, val category: TaxCategory, val label: String)

/** The stored totals columns (`subtotal_minor` … `total_minor`). */
@Serializable
data class DocumentTotals(
    val subtotalMinor: Long,
    val discountMinor: Long,
    val shippingMinor: Long,
    val taxableMinor: Long,
    val taxMinor: Long,
    val taxNotChargedMinor: Long,
    val roundOffMinor: Long,
    val totalMinor: Long,
) {
    companion object {
        val zero = DocumentTotals(0, 0, 0, 0, 0, 0, 0, 0)

        fun of(totals: ComputedTotals) = DocumentTotals(
            totals.subtotal, totals.discount, totals.shipping, totals.taxable, totals.tax, totals.taxNotCharged,
            totals.roundOff, totals.total,
        )
    }
}

/** The seller as the engine sees it plus what documents print (`spec/documents.md` §4). One flat JSON object. */
@Serializable
data class SellerSnapshot(
    val registration: String,
    val taxId: String? = null,
    val region: String? = null,
    val country: String,
    val homeCurrency: CurrencyCode,
    val lutReference: String? = null,
    /** The business address on one line. */
    val address: String? = null,
    val turnoverMinor: Long? = null,
    val customRates: List<TaxRate>? = null,
    val name: String,
    val legalName: String? = null,
    val postalAddress: Address? = null,
    val email: String? = null,
    val phone: String? = null,
    val website: String? = null,
    val extraIds: ExtraIDs? = null,
    val bank: BankDetails? = null,
    val upiVpa: String? = null,
    val logoAssetId: String? = null,
    val signatureAssetId: String? = null,
) {
    val engineSeller: EngineSeller
        get() = EngineSeller(registration, taxId, region, country, homeCurrency, lutReference, address, turnoverMinor, customRates)
}

/** The client as the engine sees it plus what documents print (`spec/documents.md` §4). One flat JSON object. */
@Serializable
data class BuyerSnapshot(
    val name: String? = null,
    /** The billing address on one line. */
    val address: String? = null,
    val country: String? = null,
    val region: String? = null,
    val taxId: String? = null,
    val isBusiness: Boolean,
    val contactName: String? = null,
    val email: String? = null,
    val phone: String? = null,
    val billingAddress: Address? = null,
    val shippingAddress: Address? = null,
) {
    val engineBuyer: EngineBuyer get() = EngineBuyer(name, address, country, region, taxId, isBusiness)
}

/** One row of the documents list: what a list shows without loading lines. */
data class DocumentSummary(
    val id: String,
    val docType: DocumentType,
    val number: String?,
    val lifecycle: DocumentLifecycle,
    val issueDate: LocalDate,
    val dueDate: LocalDate?,
    val validUntil: LocalDate?,
    val sentAt: Long?,
    val quoteOutcome: QuoteOutcome?,
    val clientId: String?,
    /** From the buyer snapshot. */
    val buyerName: String?,
    val currency: CurrencyCode,
    val totalMinor: Long,
    /** The sum of the invoice's live payments (`documents.md` §10); 0 for quotes and drafts. */
    val paidMinor: Long = 0,
    val lineCount: Int,
    val updatedAt: Long,
) {
    fun status(today: LocalDate): DocumentStatus = DocumentStatus.derive(
        DocumentStatus.Input(docType, lifecycle, totalMinor, paidMinor, dueDate, validUntil, sentAt, quoteOutcome, today),
    )

    /** `max(total − paid, 0)`; null for quotes (`ENGINE.md` §6). */
    fun outstanding(): Long? = if (docType == DocumentType.quote) null else maxOf(totalMinor - paidMinor, 0)
}

/**
 * Outstanding balance per currency across this client's live, unpaid issued invoices (`documents.md` §10), sorted
 * by currency code.
 */
fun List<DocumentSummary>.outstandingByCurrency(today: LocalDate): List<Pair<CurrencyCode, Long>> {
    val totals = sortedMapOf<String, Long>()
    for (document in this) {
        if (document.docType != DocumentType.invoice || document.lifecycle != DocumentLifecycle.issued) continue
        val outstanding = document.outstanding() ?: continue
        if (document.status(today) == DocumentStatus.paid) continue
        totals[document.currency.rawValue] = (totals[document.currency.rawValue] ?: 0) + outstanding
    }
    return totals.map { CurrencyCode(it.key) to it.value }
}

/** Home-currency totals for the Home dashboard (`docs/plan.md` Phase 4). */
data class DashboardTotals(val outstandingMinor: Long = 0, val overdueMinor: Long = 0, val paidThisMonthMinor: Long = 0)

/** How a payment was made (`spec/documents.md` §10). An open set. */
@Serializable
@JvmInline
value class PaymentMethod(val rawValue: String) {
    companion object {
        val cash = PaymentMethod("cash")
        val bank = PaymentMethod("bank")
        val upi = PaymentMethod("upi")
        val card = PaymentMethod("card")
        val cheque = PaymentMethod("cheque")
        val other = PaymentMethod("other")
        val known = listOf(cash, bank, upi, card, cheque, other)
    }
}

/** A payment recorded against an issued invoice (`domain.schema.json#/$defs/Payment`, `spec/documents.md` §10). */
@Serializable
data class Payment(
    val id: String,
    @Required val createdAt: Long = 0,
    @Required val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val businessId: String,
    val documentId: String,
    val amountMinor: Long,
    val date: IsoDate,
    val method: PaymentMethod,
    val reference: String? = null,
    val note: String? = null,
)
