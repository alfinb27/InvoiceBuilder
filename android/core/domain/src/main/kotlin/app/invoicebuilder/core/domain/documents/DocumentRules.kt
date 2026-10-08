package app.invoicebuilder.core.domain.documents

import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCatalog
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.numbering.NumberAllocator
import app.invoicebuilder.core.domain.numbering.NumberingError
import app.invoicebuilder.core.domain.support.SpecLoadingError
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.ComputedDocument
import app.invoicebuilder.core.domain.tax.EngineBuyer
import app.invoicebuilder.core.domain.tax.EngineDraft
import app.invoicebuilder.core.domain.tax.EngineInput
import app.invoicebuilder.core.domain.tax.EngineIssue
import app.invoicebuilder.core.domain.tax.EngineLine
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.tax.TaxConfigStore
import app.invoicebuilder.core.domain.tax.TaxEngine
import app.invoicebuilder.core.domain.tax.TaxEngineError
import app.invoicebuilder.core.domain.tax.TaxLevel
import app.invoicebuilder.core.domain.tax.TaxRate
import java.time.LocalDate

/** Why a document cannot be issued yet (`spec/documents.md` §6 step 3–5). Screens turn these into messages. */
sealed interface IssueProblem {
    data object NoLines : IssueProblem
    /** 0-based line indexes. */
    data class LineDescriptionMissing(val lines: List<Int>) : IssueProblem
    data class LineRateMissing(val lines: List<Int>) : IssueProblem
    /** The engine could not compute the document. */
    data class Engine(val error: TaxEngineError) : IssueProblem
    /** An engine issue with severity `error`. */
    data class BlockingIssue(val issue: EngineIssue) : IssueProblem
    /** This device owns no series for the document type. */
    data object NoSeries : IssueProblem
    data class Numbering(val error: NumberingError) : IssueProblem
}

/** The engine input of a document (`spec/documents.md` §4). iOS: `EngineInput(document:…)`. */
fun engineInput(document: Document, seller: app.invoicebuilder.core.domain.tax.EngineSeller, buyer: EngineBuyer, config: TaxConfig, currencies: CurrencyCatalog) =
    EngineInput(
        config = config, seller = seller, buyer = buyer, currencies = currencies,
        draft = EngineDraft(
            docType = document.docType, issueDate = document.issueDate, supplyDate = document.supplyDate,
            dueDate = document.dueDate, currency = document.currency, exchangeRate = document.exchangeRate?.trimmedOrNull,
            supplyType = document.supplyType, placeOfSupply = document.placeOfSupply?.trimmedOrNull,
            reverseCharge = document.reverseCharge, pricesIncludeTax = document.pricesIncludeTax,
            lines = document.lines.map { EngineLine(it.description, it.productCode, it.quantity, it.unitPriceMinor, it.discount, it.rateId) },
            discount = document.discount, shipping = if (document.shippingMinor > 0) document.shippingMinor else null,
            roundOff = document.roundOff,
        ),
    )

/**
 * Document rules for one business (`spec/documents.md`): a new draft's defaults, the edits that move other fields,
 * snapshots, the engine input and what blocks issuing. iOS: `DocumentRules`.
 */
class DocumentRules(
    val configs: TaxConfigStore,
    val business: Business,
    val currencies: CurrencyCatalog,
    /** Used when the store has no version of the business's family (the session's config). */
    private val defaultConfig: TaxConfig = configs.latest(business.taxConfig) ?: configs.latest("GENERIC")
        ?: throw SpecLoadingError("tax/${business.taxConfig}.json", "no config for this business"),
) {
    /** The business's config family in force on [date] (a document's `supplyDate ?: issueDate`). */
    fun config(date: LocalDate): TaxConfig = configs.latest(business.taxConfig, date) ?: defaultConfig

    fun config(document: Document): TaxConfig = config(document.effectiveDate)

    fun chargesTax(config: TaxConfig): Boolean = config.registration(business.taxRegistration)?.chargesTax ?: false

    /** The line editor's rules for a line of [document]. */
    fun lineRules(document: Document): LineItemRules {
        val config = config(document)
        return LineItemRules(config, chargesTax(config), currencies.exponent(document.currency))
    }

    // §2 New drafts

    fun newDocument(docType: DocumentType, id: String, today: LocalDate, client: Client? = null, now: Long): Document {
        val config = config(today)
        var document = Document(
            id = id, createdAt = now, updatedAt = now, businessId = business.id, docType = docType, issueDate = today,
            currency = business.homeCurrency, supplyType = config.supplyTypes.firstOrNull()?.id ?: "domestic",
            notes = business.defaultNotes, terms = business.defaultTerms, templateId = business.templateId,
            taxConfigRef = config.ref,
        )
        document = applyTypeDates(document)
        return setClient(client, document)
    }

    /** Invoice: due after the payment terms, no valid-until date; quote: valid for 30 days, no due date. */
    fun applyTypeDates(document: Document): Document = if (document.docType == DocumentType.quote) {
        document.copy(dueDate = null, validUntil = document.issueDate.plusDays(QUOTE_VALIDITY_DAYS.toLong()))
    } else {
        document.copy(validUntil = null, dueDate = document.issueDate.plusDays(business.paymentTermsDays.toLong()))
    }

    /** §2.1: the first `supplyTypeDefaults` entry that matches, else the first supply type. */
    fun defaultSupplyType(client: Client?, config: TaxConfig): String {
        val foreign = client?.let { it.countryCode != business.countryCode } ?: false
        val isBusiness = client?.isBusiness ?: false
        val hasLUT = business.extraIds?.lutReference?.trimmedOrNull != null
        val match = config.supplyTypeDefaults.firstOrNull { entry ->
            (entry.condition.buyerForeign?.let { it == foreign } ?: true) &&
                (entry.condition.buyerIsBusiness?.let { it == isBusiness } ?: true) &&
                (entry.condition.sellerHasLutReference?.let { it == hasLUT } ?: true)
        }
        return match?.supplyType ?: config.supplyTypes.firstOrNull()?.id ?: "domestic"
    }

    // §2.2 Edits that move other fields

    /** Choosing, changing or clearing the client resets the currency, supply type, round-off and place of supply. */
    fun setClient(client: Client?, document: Document): Document {
        var updated = setCurrency(client?.defaultCurrency ?: business.homeCurrency, document.copy(clientId = client?.id))
        updated = updated.copy(supplyType = defaultSupplyType(client, config(updated)), placeOfSupply = null)
        return updated
    }

    /** A foreign currency starts without round-off; the home currency uses the config default. */
    fun setCurrency(currency: CurrencyCode, document: Document): Document = document.copy(
        exchangeRate = if (currency != document.currency) null else document.exchangeRate,
        currency = currency,
        roundOff = if (currency == business.homeCurrency) null else false,
    )

    /** The due date and valid-until date move with the issue date. */
    fun setIssueDate(date: LocalDate, document: Document): Document {
        val days = date.toEpochDay() - document.issueDate.toEpochDay()
        return document.copy(issueDate = date, dueDate = document.dueDate?.plusDays(days), validUntil = document.validUntil?.plusDays(days))
    }

    fun setDocType(docType: DocumentType, document: Document): Document =
        if (docType == document.docType) document else applyTypeDates(document.copy(docType = docType))

    // §3 Lines

    /** A line for a catalogue item; `needsPrice` when its price could not be converted (§3.1). */
    fun line(item: CatalogItem, document: Document, id: String): Pair<LineItem, Boolean> {
        val config = config(document)
        val price = LinePricing.unitPrice(
            item, config.rate(item.rateId, business.customRates), chargesTax(config), business.homeCurrency,
            document.currency, document.exchangeRate, document.pricesIncludeTax, currencies, config.rounding.amountMode,
        )
        val minor = (price as? Outcome.Success)?.value
        val line = LineItem(
            id = id, position = document.lines.size, catalogItemId = item.id, description = item.name,
            productCode = item.productCode, unit = item.unit, quantity = "1", unitPriceMinor = minor ?: 0, rateId = item.rateId,
        )
        return line to (minor == null)
    }

    /** A one-off line's rate: the previous line's; with none, the first rate in force when tax is not charged. */
    fun oneOffRateID(document: Document): String {
        document.lines.lastOrNull()?.rateId?.takeIf { it.isNotEmpty() }?.let { return it }
        val config = config(document)
        if (chargesTax(config)) return ""
        return config.ratesInForce(document.effectiveDate, business.customRates).firstOrNull()?.id ?: ""
    }

    /** Rates offered for a line: those in force on the document's date, plus the line's own rate when it no longer is. */
    fun rateChoices(document: Document, selected: String?): List<TaxRate> {
        val config = config(document)
        val choices = config.ratesInForce(document.effectiveDate, business.customRates).toMutableList()
        if (!selected.isNullOrEmpty() && choices.none { it.id == selected }) {
            config.rate(selected, business.customRates)?.let { choices += it }
        }
        return choices
    }

    // §4 Snapshots

    fun sellerSnapshot(config: TaxConfig): SellerSnapshot = SellerSnapshot(
        registration = business.taxRegistration, taxId = business.taxId?.trimmedOrNull, region = business.region(config),
        country = business.countryCode, homeCurrency = business.homeCurrency,
        lutReference = business.extraIds?.lutReference?.trimmedOrNull, address = business.address?.singleLine?.trimmedOrNull,
        turnoverMinor = business.turnoverMinor, customRates = business.customRates, name = business.name,
        legalName = business.legalName?.trimmedOrNull, postalAddress = business.address, email = business.email?.trimmedOrNull,
        phone = business.phone?.trimmedOrNull, website = business.website?.trimmedOrNull,
        extraIds = business.extraIds?.takeUnless { it.isEmpty }, bank = business.bank?.takeUnless { it.isEmpty },
        upiVpa = business.upiVpa?.trimmedOrNull, logoAssetId = business.logoAssetId, signatureAssetId = business.signatureAssetId,
    )

    fun buyerSnapshot(client: Client): BuyerSnapshot = BuyerSnapshot(
        name = client.name, address = client.billingAddress?.singleLine?.trimmedOrNull, country = client.countryCode,
        region = client.regionCode?.trimmedOrNull, taxId = client.taxId?.trimmedOrNull, isBusiness = client.isBusiness,
        contactName = client.contactName?.trimmedOrNull, email = client.email?.trimmedOrNull, phone = client.phone?.trimmedOrNull,
        billingAddress = client.billingAddress, shippingAddress = client.shippingAddress,
    )

    /** The buyer of [document]: none without a client; the live client; otherwise the last snapshot kept. */
    fun buyerSnapshot(document: Document, client: Client?): BuyerSnapshot? {
        val clientID = document.clientId ?: return null
        if (client != null && client.id == clientID) return buyerSnapshot(client)
        return document.buyerSnapshot
    }

    // Engine

    fun engineInput(document: Document, seller: SellerSnapshot, buyer: BuyerSnapshot?): EngineInput =
        engineInput(document, seller.engineSeller, buyer?.engineBuyer ?: EngineBuyer(), config(document), currencies)

    fun compute(document: Document, seller: SellerSnapshot, buyer: BuyerSnapshot?): Outcome<ComputedDocument, TaxEngineError> =
        try {
            Outcome.Success(TaxEngine.compute(engineInput(document, seller, buyer)))
        } catch (error: TaxEngineError) {
            Outcome.Failure(error)
        }

    // §5 Saving a draft

    /** A draft as it is saved: snapshots from the live business and client, the config ref and the totals. */
    fun preparedDraft(document: Document, client: Client?): Document {
        val config = config(document)
        val seller = sellerSnapshot(config)
        val buyer = buyerSnapshot(document, client)
        val draft = document.copy(
            sellerSnapshot = seller, buyerSnapshot = buyer, taxConfigRef = config.ref, computed = null,
            lines = document.lines.mapIndexed { index, line -> line.clearingComputed.copy(position = index) },
        )
        val totals = when (val result = compute(draft, seller, buyer)) {
            is Outcome.Success -> DocumentTotals.of(result.value.totals)
            is Outcome.Failure -> DocumentTotals.zero
        }
        return draft.copy(totals = totals)
    }

    // §6 Issuing

    /** Problems that block issuing, from the document and its engine result (§6 step 3). */
    fun issueProblems(document: Document, result: Outcome<ComputedDocument, TaxEngineError>): List<IssueProblem> {
        val problems = mutableListOf<IssueProblem>()
        if (document.lines.isEmpty()) problems += IssueProblem.NoLines
        val noDescription = document.lines.indices.filter { document.lines[it].description.trimmedOrNull == null }
        if (noDescription.isNotEmpty()) problems += IssueProblem.LineDescriptionMissing(noDescription)
        val noRate = document.lines.indices.filter { document.lines[it].rateId.trimmedOrNull == null }
        if (noRate.isNotEmpty()) problems += IssueProblem.LineRateMissing(noRate)
        when (result) {
            // A missing rate is already reported for its line.
            is Outcome.Failure -> if (!(result.error.code == TaxEngineError.Code.UnknownRate && result.error.line in noRate)) {
                problems += IssueProblem.Engine(result.error)
            }
            is Outcome.Success -> problems += result.value.issues.filter { it.severity == EngineIssue.Severity.error }.map(IssueProblem::BlockingIssue)
        }
        return problems
    }

    /** The issued form of [document] (§6 step 6): lifecycle, number, frozen snapshots, stored results. */
    fun issued(document: Document, seller: SellerSnapshot, buyer: BuyerSnapshot?, computed: ComputedDocument, allocation: NumberAllocator.Allocation): Document {
        val config = config(document)
        val lineLevel = config.rounding.taxLevel == TaxLevel.line
        return document.copy(
            lifecycle = DocumentLifecycle.issued, number = allocation.number, seriesId = allocation.series.id,
            periodKey = allocation.periodKey, sequence = allocation.sequence, sellerSnapshot = seller, buyerSnapshot = buyer,
            taxConfigRef = config.ref, revision = 1, totals = DocumentTotals.of(computed.totals), computed = computed,
            lines = document.lines.zip(computed.lines).mapIndexed { index, (line, result) ->
                line.copy(
                    position = index,
                    rateSnapshot = RateSnapshot(result.rate, result.category, config.rate(line.rateId, seller.customRates)?.label ?: line.rateId),
                    amountMinor = result.amount, taxableMinor = result.taxable,
                    taxMinor = if (lineLevel) result.tax else null, totalMinor = if (lineLevel) result.taxable + result.tax else null,
                )
            },
        )
    }

    // §7 Duplicate and convert

    /** A new draft copying [source]'s content, dated [today] (§7). */
    fun duplicate(source: Document, id: String, today: LocalDate, now: Long, newLineID: () -> String): Document = applyTypeDates(
        Document(
            id = id, createdAt = now, updatedAt = now, businessId = source.businessId, docType = source.docType,
            issueDate = today, currency = source.currency, exchangeRate = source.exchangeRate, supplyType = source.supplyType,
            placeOfSupply = source.placeOfSupply, reverseCharge = source.reverseCharge, pricesIncludeTax = source.pricesIncludeTax,
            roundOff = source.roundOff, clientId = source.clientId, buyerSnapshot = source.buyerSnapshot, discount = source.discount,
            shippingMinor = source.shippingMinor, notes = source.notes, terms = source.terms, templateId = source.templateId,
            taxConfigRef = config(today).ref,
            lines = source.lines.mapIndexed { index, line -> line.clearingComputed.copy(id = newLineID(), position = index) },
        ),
    )

    /** An invoice draft from an issued quote (§7); the caller marks the quote `converted` in the same transaction. */
    fun convertedInvoice(quote: Document, id: String, today: LocalDate, now: Long, newLineID: () -> String): Document =
        applyTypeDates(duplicate(quote, id, today, now, newLineID).copy(docType = DocumentType.invoice, convertedFromId = quote.id))

    fun canConvert(document: Document): Boolean = document.docType == DocumentType.quote &&
        document.lifecycle == DocumentLifecycle.issued && document.deletedAt == null && document.quoteOutcome != QuoteOutcome.converted

    companion object {
        const val QUOTE_VALIDITY_DAYS = 30
    }
}
