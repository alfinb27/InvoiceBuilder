package app.invoicebuilder.android.documents

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import app.invoicebuilder.core.designsystem.Tag
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.documents.Document
import app.invoicebuilder.core.domain.documents.DocumentStatus
import app.invoicebuilder.core.domain.documents.IssueProblem
import app.invoicebuilder.core.domain.documents.PaymentMethod
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.numbering.NumberingError
import app.invoicebuilder.core.domain.tax.EngineIssue
import app.invoicebuilder.core.domain.tax.TaxCategory
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.tax.TaxEngineError
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** Words, messages and colours for documents. iOS: `DocumentText`. */
object DocumentText {
    fun noun(docType: DocumentType): String = if (docType == DocumentType.quote) "quote" else "invoice"

    /** The name of the shared PDF (`spec/documents.md` §8): "Invoice INV-26-27-0001.pdf", "Quote draft.pdf". */
    fun pdfFileName(document: app.invoicebuilder.core.domain.documents.Document): String {
        val noun = noun(document.docType).replaceFirstChar { it.uppercase() }
        val number = document.number ?: return "$noun draft.pdf"
        return "$noun ${number.replace("/", "-")}.pdf"
    }

    /** A document's title: its number once issued, else "New invoice" / "Quote draft". */
    fun title(document: Document, isPersisted: Boolean): String {
        document.number?.let { return it }
        val noun = noun(document.docType)
        return if (isPersisted) noun.replaceFirstChar { it.uppercase() } + " draft" else "New $noun"
    }

    fun status(status: DocumentStatus): String = when (status) {
        DocumentStatus.draft -> "Draft"
        DocumentStatus.issued -> "Not sent"
        DocumentStatus.sent -> "Sent"
        DocumentStatus.partiallyPaid -> "Part paid"
        DocumentStatus.paid -> "Paid"
        DocumentStatus.overdue -> "Past due"
        DocumentStatus.void -> "Void"
        DocumentStatus.open -> "Open"
        DocumentStatus.accepted -> "Accepted"
        DocumentStatus.declined -> "Declined"
        DocumentStatus.expired -> "Expired"
        DocumentStatus.converted -> "Converted"
    }

    @Composable
    fun color(status: DocumentStatus): Color = when (status) {
        DocumentStatus.draft, DocumentStatus.void, DocumentStatus.expired -> Theme.colors.textSecondary
        DocumentStatus.paid, DocumentStatus.accepted, DocumentStatus.converted -> Theme.colors.success
        DocumentStatus.overdue, DocumentStatus.declined -> Theme.colors.danger
        DocumentStatus.partiallyPaid -> Theme.colors.warning
        DocumentStatus.issued, DocumentStatus.sent, DocumentStatus.open -> Theme.colors.info
    }

    /** "Item 2", "Items 1 and 3", "Items 1, 2 and 5" (1-based for people; the screens call lines items). */
    fun lines(indexes: List<Int>): String {
        val numbers = indexes.map { (it + 1).toString() }
        if (numbers.size <= 1) return "Item ${numbers.firstOrNull() ?: ""}"
        return "Items " + numbers.dropLast(1).joinToString(", ") + " and " + numbers.last()
    }

    /** A compliance check or rate warning from the engine (`ENGINE.md` Step 12). */
    fun message(issue: EngineIssue, config: TaxConfig, homeCurrency: CurrencyCode): String {
        val labels = config.labels
        val lines = issue.lines?.let(::lines) ?: "Some items"
        return when (issue.code) {
            "rate_not_effective" -> "$lines: the ${labels.taxName} rate isn't in force on this date. Check the rate or the dates."
            "seller_tax_id_missing" -> "Add your ${labels.taxIdName} in Settings → Business profile."
            "buyer_details_required" -> if (config.family == "IN") {
                "For totals of ₹50,000 or more to unregistered buyers, add the client's name, address and state."
            } else "A ${labels.taxName} invoice needs the client's name and address."
            "buyer_address_missing" -> "Add the client's name and billing address: registered buyers need them on the invoice."
            "lut_reference_missing" -> "Exports without IGST need your LUT reference. Add it in Settings → Business profile."
            "export_buyer_details_required" -> "Exports need the client's name, address and country."
            "product_code_missing" -> "$lines: add the ${labels.productCodeName} with enough digits for your turnover."
            "exchange_rate_missing" -> "Add the exchange rate: ${labels.taxName} must also be shown in ${homeCurrency.rawValue}."
            else -> issue.code.split('_').joinToString(" ") { it.replaceFirstChar(Char::uppercase) }
        }
    }

    /** Why the engine could not compute the document (`ENGINE.md` §3, errors). */
    fun message(error: TaxEngineError, config: TaxConfig): String {
        val line = error.line?.let { "Item ${it + 1}: " } ?: ""
        return when (error.code) {
            TaxEngineError.Code.NoComponentRule -> "This supply type can't be used with your registration."
            TaxEngineError.Code.UnknownRate -> line + "choose a ${config.labels.taxName} rate."
            TaxEngineError.Code.UnknownRegion -> "Choose a valid ${(config.labels.placeOfSupply ?: "place of supply").lowercase()}."
            TaxEngineError.Code.DiscountExceedsSubtotal -> "The discount is more than the subtotal."
            TaxEngineError.Code.LineDiscountExceedsAmount -> line + "the discount is more than the item's amount."
            TaxEngineError.Code.InclusiveCompoundUnsupported -> line + "compound taxes can't be used with tax-inclusive prices."
            TaxEngineError.Code.InvalidInput -> line + "check the quantity, price and amounts."
        }
    }

    /** What blocks issuing (`spec/documents.md` §6). */
    fun message(problem: IssueProblem, config: TaxConfig, homeCurrency: CurrencyCode, docType: DocumentType): String = when (problem) {
        IssueProblem.NoLines -> "Add at least one item."
        is IssueProblem.LineDescriptionMissing -> "${lines(problem.lines)}: add a description."
        is IssueProblem.LineRateMissing -> "${lines(problem.lines)}: choose a ${config.labels.taxName} rate."
        is IssueProblem.Engine -> message(problem.error, config)
        is IssueProblem.BlockingIssue -> message(problem.issue, config, homeCurrency)
        IssueProblem.NoSeries -> "This device has no number series for ${noun(docType)}s. Check Settings → Invoice numbering."
        is IssueProblem.Numbering -> when (problem.error) {
            NumberingError.NumberTooLong -> "The next number would be too long. Shorten the pattern in Settings → Invoice numbering."
            NumberingError.NumberInvalidChars -> "The next number has characters that aren't allowed. Check Settings → Invoice numbering."
        }
    }

    fun category(category: TaxCategory): String = when (category) {
        TaxCategory.exempt -> "Exempt"
        TaxCategory.nilRated -> "Nil rated"
        TaxCategory.outsideScope -> "Outside the scope"
        TaxCategory.zero -> "Zero rated"
        else -> category.rawValue.replaceFirstChar(Char::uppercase)
    }
}

object PaymentMethodText {
    /** The fixed set from `domain.schema.json#/$defs/Payment.method`, in picker order. */
    val all = listOf(PaymentMethod.cash, PaymentMethod.bank, PaymentMethod.upi, PaymentMethod.card, PaymentMethod.cheque, PaymentMethod.other)

    fun label(method: PaymentMethod): String = when (method) {
        PaymentMethod.cash -> "Cash"
        PaymentMethod.bank -> "Bank transfer"
        PaymentMethod.upi -> "UPI"
        PaymentMethod.card -> "Card"
        PaymentMethod.cheque -> "Cheque"
        PaymentMethod.other -> "Other"
        else -> method.rawValue.replaceFirstChar(Char::uppercase)
    }
}

/** A status chip for lists and headers. */
@Composable
fun StatusTag(status: DocumentStatus) = Tag(DocumentText.status(status), DocumentText.color(status))

/** `19 Sept 2026`, for rows and headers (display only; stored dates stay ISO). */
val LocalDate.displayText: String get() = format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))

/** From an epoch-ms audit timestamp, in the device's zone. */
fun localDate(epochMs: Long): LocalDate = Instant.ofEpochMilli(epochMs).atZone(ZoneId.systemDefault()).toLocalDate()
