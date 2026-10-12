package app.invoicebuilder.core.domain.pdf

import app.invoicebuilder.core.domain.documents.AmountInWords
import app.invoicebuilder.core.domain.documents.Document
import app.invoicebuilder.core.domain.documents.UPIPaymentLink
import app.invoicebuilder.core.domain.models.Address
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.reference.ReferenceData
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.ComputedDocument
import app.invoicebuilder.core.domain.tax.Discount
import app.invoicebuilder.core.domain.tax.TaxCategory
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.tax.TaxLevel
import app.invoicebuilder.core.domain.pdf.PDFDocumentModel.Align
import app.invoicebuilder.core.domain.pdf.PDFDocumentModel.Column
import app.invoicebuilder.core.domain.pdf.PDFDocumentModel.Field
import app.invoicebuilder.core.domain.pdf.PDFDocumentModel.Party
import app.invoicebuilder.core.domain.pdf.PDFDocumentModel.TotalRow

/**
 * Builds the PDF view model from a stored document and its engine result (`spec/pdf/RENDERING.md` §1). Pure: no
 * clock, no locale, no I/O — the same document always produces the same strings, on both platforms.
 * iOS: `PDFModelBuilder`.
 */
object PDFModelBuilder {
    fun build(document: Document, computed: ComputedDocument, config: TaxConfig, labels: PDFLabels, reference: ReferenceData): PDFDocumentModel =
        Builder(document, computed, config, labels, reference).build()

    private class Builder(
        val document: Document,
        val computed: ComputedDocument,
        val config: TaxConfig,
        val labels: PDFLabels,
        val reference: ReferenceData,
    ) {
        val formatter = SpecFormatter(reference.currencies)
        val taxName get() = config.labels.taxName
        val taxIDName get() = config.labels.taxIdName
        val currency get() = document.currency
        val homeCurrency get() = document.sellerSnapshot?.homeCurrency ?: document.currency
        val isQuote get() = document.docType == DocumentType.quote
        val chargesTax get() = computed.chargesTax
        val lineLevelTax get() = config.rounding.taxLevel == TaxLevel.line

        fun money(minor: Long, currency: CurrencyCode? = null): String =
            formatter.money(minor, currency ?: this.currency, homeCurrency)

        fun build(): PDFDocumentModel {
            val columns = columns()
            return PDFDocumentModel(
                title = computed.title,
                isDraft = document.number == null,
                draftLabel = if (document.number == null) labels.text("draft") else null,
                number = document.number,
                numberLabel = labels.text(if (isQuote) "quoteNumber" else "invoiceNumber"),
                meta = meta(),
                seller = sellerParty(),
                buyer = buyerParty(),
                shipTo = shipToParty(),
                columns = columns,
                rows = rows(columns),
                totals = totalRows(),
                taxSummary = taxSummary(),
                amountInWords = amountInWords(),
                homeTotals = homeTotals(),
                reverseChargeNote = reverseChargeNote(),
                notes = notes(),
                payment = payment(),
                signature = signature(),
                footer = PDFDocumentModel.Footer(labels.text("page"), labels.text("continued")),
            )
        }

        // Header

        fun meta(): List<Field> {
            val fields = mutableListOf(field("issueDate", SpecFormatter.date(document.issueDate)))
            document.supplyDate?.let { fields += field("supplyDate", SpecFormatter.date(it)) }
            if (isQuote) document.validUntil?.let { fields += field("validUntil", SpecFormatter.date(it)) }
            if (!isQuote) document.dueDate?.let { fields += field("dueDate", SpecFormatter.date(it)) }
            computed.placeOfSupply?.let { place ->
                fields += Field(config.labels.placeOfSupply ?: labels.text("placeOfSupply"), config.region(place)?.name ?: place)
            }
            return fields
        }

        fun field(key: String, value: String) = Field(labels.text(key), value)

        // Parties

        fun sellerParty(): Party {
            val seller = document.sellerSnapshot ?: return Party(labels.text("from"), "")
            val lines = mutableListOf<String>()
            seller.legalName?.let { if (it != seller.name) lines += it }
            lines += addressLines(seller.postalAddress, seller.address, seller.country)
            lines += listOfNotNull(seller.email?.trimmedOrNull, seller.phone?.trimmedOrNull, seller.website?.trimmedOrNull)
            val fields = mutableListOf<Field>()
            seller.taxId?.trimmedOrNull?.let { fields += Field(taxIDName, it) }
            val extras = seller.extraIds
            for ((value, key) in listOf(extras?.pan to "pan", extras?.companyNumber to "companyNumber",
                extras?.registeredOffice to "registeredOffice", extras?.lutReference to "lutReference")) {
                value?.trimmedOrNull?.let { fields += field(key, it) }
            }
            return Party(labels.text("from"), seller.name, lines, fields)
        }

        fun buyerParty(): Party? {
            val buyer = document.buyerSnapshot ?: return null
            val fields = mutableListOf<Field>()
            buyer.taxId?.trimmedOrNull?.let { taxId ->
                val domestic = buyer.country == document.sellerSnapshot?.country
                fields += Field(if (domestic) taxIDName else labels.text("foreignTaxId"), taxId)
            }
            return Party(labels.text("billTo"), buyer.name ?: "", addressLines(buyer.billingAddress, buyer.address, document.sellerSnapshot?.country), fields)
        }

        fun shipToParty(): Party? {
            val buyer = document.buyerSnapshot ?: return null
            val shipping = buyer.shippingAddress ?: return null
            if (shipping == buyer.billingAddress) return null
            return Party(labels.text("shipTo"), buyer.name ?: "", addressLines(shipping, null, document.sellerSnapshot?.country))
        }

        /** Line 1, line 2, city with postcode, the region's name, then the country when it is not the business's own. */
        fun addressLines(address: Address?, fallback: String?, businessCountry: String?): List<String> {
            if (address == null) return listOfNotNull(fallback?.trimmedOrNull)
            val lines = mutableListOf(address.line1)
            address.line2?.trimmedOrNull?.let { lines += it }
            val city = listOfNotNull(address.city?.trimmedOrNull, address.postalCode?.trimmedOrNull).joinToString(" ")
            if (city.isNotEmpty()) lines += city
            address.regionCode?.trimmedOrNull?.let { lines += config.region(it)?.name ?: it }
            if (address.countryCode != businessCountry) lines += reference.country(address.countryCode)?.name ?: address.countryCode
            return lines
        }

        // Items table (§1.1)

        /** Component codes that appear on the lines, in order of first appearance. */
        val componentCodes: List<String>
            get() {
                if (!chargesTax || !lineLevelTax) return emptyList()
                val codes = mutableListOf<String>()
                for (line in computed.lines) for (tax in line.taxes ?: emptyList()) {
                    val code = tax.component ?: continue
                    if (code !in codes) codes += code
                }
                return codes
            }

        fun columns(): List<Column> {
            val columns = mutableListOf(Column("index", labels.text("item"), Align.leading), Column("description", labels.text("description"), Align.leading))
            if (document.lines.any { it.productCode?.trimmedOrNull != null }) columns += Column("productCode", config.labels.productCodeName, Align.leading)
            columns += Column("quantity", labels.text("quantity"), Align.trailing)
            if (document.lines.any { it.unit?.trimmedOrNull != null }) columns += Column("unit", labels.text("unit"), Align.leading)
            val priceLabel = if (computed.inclusive) labels.text("unitPriceInclusive", mapOf("taxName" to taxName)) else labels.text("unitPrice")
            columns += Column("unitPrice", priceLabel, Align.trailing)
            if (document.lines.any { it.discount != null }) columns += Column("discount", labels.text("discount"), Align.trailing)
            if (chargesTax) columns += Column("taxable", labels.text("taxableValue"), Align.trailing)
            val codes = componentCodes
            if (codes.isNotEmpty() && codes.size <= 2) {
                for (code in codes) {
                    val rates = computed.lines.flatMap { it.taxes ?: emptyList() }.filter { it.component == code }.map { it.rate }.toSet()
                    val label = if (rates.size == 1) "$code ${SpecFormatter.percent(rates.first())}" else code
                    columns += Column("tax:$code", label, Align.trailing)
                }
            }
            columns += Column("amount", labels.text("amount"), Align.trailing)
            return columns
        }

        fun rows(columns: List<Column>): List<List<String>> = document.lines.zip(computed.lines).mapIndexed { index, (line, result) ->
            val taxes = mutableMapOf<String, Long>()
            for (tax in result.taxes ?: emptyList()) tax.component?.let { taxes[it] = (taxes[it] ?: 0) + tax.amount }
            val isNonTax = (result.taxes ?: emptyList()).any { it.component == null }
            val lineTax = taxes.values.sum()
            columns.map { column ->
                when (column.id) {
                    "index" -> (index + 1).toString()
                    "description" -> line.description
                    "productCode" -> line.productCode ?: ""
                    "quantity" -> SpecFormatter.quantity(line.quantity)
                    "unit" -> line.unit ?: ""
                    "unitPrice" -> money(line.unitPriceMinor)
                    "discount" -> discountText(line.discount)
                    "taxable" -> money(result.taxable)
                    "amount" -> money(if (chargesTax && lineLevelTax) result.taxable + lineTax else result.taxable)
                    else -> if (column.id.startsWith("tax:")) {
                        if (isNonTax) categoryLabel(result.category) else money(taxes[column.id.removePrefix("tax:")] ?: 0)
                    } else ""
                }
            }
        }

        fun discountText(discount: Discount?): String = when (discount) {
            is Discount.Percent -> SpecFormatter.percent(discount.value)
            is Discount.Amount -> money(discount.value)
            null -> ""
        }

        fun categoryLabel(category: TaxCategory): String = when (category) {
            TaxCategory.exempt -> labels.text("exempt")
            TaxCategory.nilRated -> labels.text("nilRated")
            TaxCategory.zero -> labels.text("zeroRated")
            TaxCategory.outsideScope -> labels.text("outsideScope")
            else -> category.rawValue
        }

        // Totals (§1.2)

        private class ComponentTotal(val code: String, var tax: Long, val rates: MutableSet<String>)

        fun totalRows(): List<TotalRow> {
            val totals = computed.totals
            val rows = mutableListOf(TotalRow(labels.text("subtotal"), money(totals.subtotal)))
            if (totals.discount != 0L) rows += TotalRow(labels.text("invoiceDiscount"), money(-totals.discount))
            if (totals.shipping != 0L) rows += TotalRow(labels.text("shipping"), money(totals.shipping))
            if (chargesTax) rows += TotalRow(labels.text("taxableValue"), money(totals.taxable))
            // One row per component code, summing its tax lines; the per-rate split stays in the tax summary.
            val components = mutableListOf<ComponentTotal>()
            for (taxLine in computed.taxLines) {
                val code = taxLine.component
                if (!taxLine.charged || code == null) continue
                val existing = components.firstOrNull { it.code == code }
                if (existing != null) {
                    existing.tax += taxLine.tax
                    existing.rates += taxLine.rate
                } else {
                    components += ComponentTotal(code, taxLine.tax, mutableSetOf(taxLine.rate))
                }
            }
            for (component in components) {
                val label = if (component.rates.size == 1) "${component.code} ${SpecFormatter.percent(component.rates.first())}" else component.code
                rows += TotalRow(label, money(component.tax))
            }
            if (totals.roundOff != 0L) rows += TotalRow(config.rounding.grandTotal?.label ?: labels.text("roundOff"), money(totals.roundOff))
            rows += TotalRow(labels.text("total"), money(totals.total), PDFDocumentModel.Emphasis.strong)
            return rows
        }

        fun taxSummary(): PDFDocumentModel.Table? {
            if (!chargesTax || !(computed.taxLines.size > 1 || !lineLevelTax)) return null
            val showsHome = config.foreignCurrency.taxInHomeCurrency && computed.home != null
            val columns = mutableListOf(
                Column("rate", labels.text("taxRate", mapOf("taxName" to taxName)), Align.leading),
                Column("taxable", labels.text("taxableValue"), Align.trailing),
                Column("tax", labels.text("taxAmount", mapOf("taxName" to taxName)), Align.trailing),
            )
            if (showsHome) {
                columns += Column("homeTax", labels.text("taxAmountInCurrency", mapOf("taxName" to taxName, "currency" to homeCurrency.rawValue)), Align.trailing)
            }
            val rows = computed.taxLines.map { taxLine ->
                val name = taxLine.component?.let { "$it ${SpecFormatter.percent(taxLine.rate)}" } ?: categoryLabel(taxLine.category)
                val row = mutableListOf(name, money(taxLine.taxable), if (taxLine.component == null) "" else money(taxLine.tax))
                if (showsHome) row += if (taxLine.component == null) "" else money(taxLine.homeTax ?: 0, homeCurrency)
                row.toList()
            }.toMutableList()
            val totals = computed.totals
            val totalRow = mutableListOf(labels.text("totalTax", mapOf("taxName" to taxName)), money(totals.taxable),
                money(if (totals.tax != 0L) totals.tax else totals.taxNotCharged))
            if (showsHome) totalRow += money(computed.home?.tax ?: 0, homeCurrency)
            rows += totalRow.toList()
            return PDFDocumentModel.Table(columns, rows)
        }

        fun amountInWords(): String? =
            if (!config.amountInWords) null else AmountInWords.text(computed.totals.total, currency, reference.currencies)

        fun homeTotals(): String? {
            val home = computed.home ?: return null
            val prefix = labels.text("homeCurrencyEquivalent", mapOf("currency" to home.currency.rawValue, "rate" to SpecFormatter.quantity(home.rate)))
            return "$prefix: " + money(home.total, home.currency)
        }

        fun reverseChargeNote(): String? {
            if (computed.totals.taxNotCharged == 0L) return null
            return labels.text("taxNotChargedRecipient", mapOf("taxName" to taxName, "amount" to money(computed.totals.taxNotCharged)))
        }

        // Notes, payment, signature (§1.3)

        fun notes(): List<PDFDocumentModel.Note> {
            val notes = computed.notes.filter { it.placement == "top" }.map { PDFDocumentModel.Note(text = it.text, placement = "top") }.toMutableList()
            document.notes?.trimmedOrNull?.let { notes += PDFDocumentModel.Note(labels.text("notes"), it, "bottom") }
            document.terms?.trimmedOrNull?.let { notes += PDFDocumentModel.Note(labels.text("terms"), it, "bottom") }
            notes += computed.notes.filter { it.placement != "top" }.map { PDFDocumentModel.Note(text = it.text, placement = "bottom") }
            return notes
        }

        fun payment(): PDFDocumentModel.Payment {
            val seller = document.sellerSnapshot ?: return PDFDocumentModel.Payment()
            val bank = seller.bank
            val entries = listOf(bank?.accountName to "accountName", bank?.accountNumber to "accountNumber", bank?.bankName to "bankName",
                bank?.ifsc to "ifsc", bank?.sortCode to "sortCode", bank?.iban to "iban", bank?.swift to "swift")
            val fields = entries.mapNotNull { (value, key) -> value?.trimmedOrNull?.let { field(key, it) } }
            val outstanding = computed.totals.total
            val vpa = seller.upiVpa?.trimmedOrNull
            val upi = if (UPIPaymentLink.applies(currency, seller.upiVpa, outstanding) && vpa != null) {
                PDFDocumentModel.Payment.UPI(vpa, labels.text("upiScanToPay"),
                    UPIPaymentLink.url(vpa, seller.name, outstanding, document.number ?: ""))
            } else null
            return PDFDocumentModel.Payment(fields, upi)
        }

        fun signature(): PDFDocumentModel.Signature {
            val name = document.sellerSnapshot?.name ?: ""
            return PDFDocumentModel.Signature(document.sellerSnapshot?.signatureAssetId,
                labels.text("forBusiness", mapOf("businessName" to name)), labels.text("authorisedSignatory"))
        }
    }
}
