package app.invoicebuilder.android.documents

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.invoicebuilder.android.app.DocumentRoute
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.reminders.ReminderMessage
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.documents.Document
import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.documents.DocumentRules
import app.invoicebuilder.core.domain.documents.DocumentStatus
import app.invoicebuilder.core.domain.documents.DocumentInput
import app.invoicebuilder.core.domain.documents.IssueProblem
import app.invoicebuilder.core.domain.documents.LineItem
import app.invoicebuilder.core.domain.documents.LineItemDraft
import app.invoicebuilder.core.domain.documents.LineItemField
import app.invoicebuilder.core.domain.documents.LineItemRules
import app.invoicebuilder.core.domain.documents.OneOffLine
import app.invoicebuilder.core.domain.documents.RateChips
import app.invoicebuilder.core.domain.decimal.DecimalInput
import app.invoicebuilder.core.domain.decimal.DecimalString
import app.invoicebuilder.core.domain.decimal.MoneyInput
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.documents.Payment
import app.invoicebuilder.core.domain.documents.QuoteOutcome
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.models.NumberingSeries
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.numbering.NumberAllocator
import app.invoicebuilder.core.domain.numbering.SeriesOwnership
import app.invoicebuilder.core.domain.repositories.DocumentServiceError
import app.invoicebuilder.core.domain.setup.FieldIssue
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.ComputedDocument
import app.invoicebuilder.core.domain.tax.EngineIssue
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.tax.TaxEngineError
import app.invoicebuilder.core.domain.tax.TaxRate
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.LocalDate

/**
 * One invoice or quote: the builder while it is a draft (`spec/documents.md` §2–5, autosaved), the read-only view
 * once issued, and the issue / duplicate / convert / delete actions. Totals always come from `TaxEngine`.
 * iOS: `DocumentViewModel`. Held by the `Session` (not a composable), so the open draft survives the activity being
 * recreated; every edit is also in Room within 500 ms, so process death loses nothing either.
 */
class DocumentViewModel(private val session: Session, val route: DocumentRoute, private val autosaveDelayMs: Long = 500) {
    data class SeriesChoice(val ownFirstNumber: String?, val others: List<Option>) {
        data class Option(val series: NumberingSeries, val nextNumber: String?)
    }

    data class LineEditorState(
        val lineID: String,
        val isNew: Boolean,
        val draft: LineItemDraft,
        val attemptedDone: Boolean = false,
        /** The catalogue price could not be converted to the document currency. */
        val needsPrice: Boolean = false,
        /** "My price already includes {tax}": how the typed price is read (`documents.md` §3.2). */
        val includesTax: Boolean = false,
        /** "Save to my items so I can reuse it": new lines in the home currency only. */
        val saveToItems: Boolean = false,
    )

    /** The live total of the line being edited: "2 × ₹2,500 + ₹900 GST" and "₹5,900". */
    data class LinePreview(val text: String, val total: String)

    var document by mutableStateOf(
        session.documentRules.newDocument((route as? DocumentRoute.New)?.docType ?: DocumentType.invoice, route.id,
            session.container.time.today(), null, session.container.time.now()),
    )
        private set
    var isLoaded by mutableStateOf(false)
        private set
    var notFound by mutableStateOf(false)
        private set
    /** The draft has been written at least once. */
    var isPersisted by mutableStateOf(false)
        private set
    var client by mutableStateOf<Client?>(null)
        private set
    var clientMissing by mutableStateOf(false)
        private set
    /** The engine result: recomputed for drafts, the stored one for issued documents. */
    var result by mutableStateOf<Outcome<ComputedDocument, TaxEngineError>?>(null)
        private set
    /** This invoice's live payments, newest first. */
    var payments by mutableStateOf(emptyList<Payment>())
        private set
    var paymentsRecorded by mutableIntStateOf(0)
        private set

    // Typed fields, kept as typed; the document holds their last valid value.
    @set:JvmName("assignDiscountText")
    var discountText by mutableStateOf("")
        private set
    @set:JvmName("assignDiscountIsPercent")
    var discountIsPercent by mutableStateOf(true)
        private set
    @set:JvmName("assignShippingText")
    var shippingText by mutableStateOf("")
        private set
    @set:JvmName("assignExchangeRateText")
    var exchangeRateText by mutableStateOf("")
        private set
    @set:JvmName("assignNotesText")
    var notesText by mutableStateOf("")
        private set
    @set:JvmName("assignTermsText")
    var termsText by mutableStateOf("")
        private set

    var saveFailed by mutableStateOf(false)
        private set
    var issueProblems by mutableStateOf(emptyList<IssueProblem>())
        private set
    /** The Review & send screen is open (`documents.md` §6.1): the checks passed and `numberPreview` is set. */
    var confirmingIssue by mutableStateOf(false)
    var numberPreview by mutableStateOf<String?>(null)
        private set
    /** Chosen on Review & send: once the review closes, the document is issued and the PDF goes out this way. */
    var pendingSend by mutableStateOf<SendChannel?>(null)
        private set
    var seriesChoice by mutableStateOf<SeriesChoice?>(null)
    var showsPaywall by mutableStateOf(false)
    var isWorking by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
    var lineEditor by mutableStateOf<LineEditorState?>(null)
    var selectedLineID by mutableStateOf<String?>(null)
    /** The open preview, or null. */
    var preview by mutableStateOf<DocumentPreviewViewModel?>(null)

    private var saveJob: Job? = null
    /** "Save to my items": the catalogue item is written first, then the line is linked to it. */
    private var itemSave: Job? = null
    private val saveLock = Mutex()
    private var isDirty = false
    private var loadStarted = false

    // Derived

    val rules: DocumentRules get() = session.documentRules
    val config: TaxConfig get() = rules.config(document)
    val chargesTax get() = rules.chargesTax(config)
    val isDraft get() = document.isDraft
    val exponent get() = session.container.reference.currencies.exponent(document.currency)
    val homeCurrency: CurrencyCode get() = session.business.homeCurrency
    val isForeignCurrency get() = document.currency != homeCurrency
    val computed: ComputedDocument? get() = (result as? Outcome.Success)?.value
    val engineError: TaxEngineError? get() = (result as? Outcome.Failure)?.error
    val showsSupplyType get() = chargesTax && config.supplyTypes.size > 1
    val showsPlaceOfSupply get() = chargesTax && config.regions.isNotEmpty()
    val showsReverseCharge get() = chargesTax && config.reverseCharge.supported
    val showsPricesIncludeTax get() = chargesTax
    val showsRoundOff get() = config.rounding.grandTotal != null
    val roundOffOn get() = document.roundOff ?: config.rounding.grandTotal?.defaultOn ?: false

    /** The place of supply the engine derives when none is set (shown as "Automatic (…)"). */
    val derivedPlaceOfSupply: String?
        get() {
            if (!showsPlaceOfSupply) return null
            val automatic = document.copy(placeOfSupply = null)
            val result = rules.compute(automatic, rules.sellerSnapshot(config), rules.buyerSnapshot(automatic, client))
            return (result as? Outcome.Success)?.value?.placeOfSupply
        }

    val discountIssue: FieldIssue? get() = (DocumentInput.discount(discountText, discountIsPercent, exponent) as? Outcome.Failure)?.error
    val shippingIssue: FieldIssue? get() = (DocumentInput.shipping(shippingText, exponent) as? Outcome.Failure)?.error
    val exchangeRateIssue: FieldIssue? get() = (DocumentInput.exchangeRate(exchangeRateText) as? Outcome.Failure)?.error
    val engineIssues: List<EngineIssue> get() = computed?.issues ?: emptyList()
    val canRequestIssue get() = isDraft && isLoaded && !isWorking
    val canConvert get() = rules.canConvert(document)
    val lineRules: LineItemRules get() = rules.lineRules(document)
    val lineEditorIssues: Map<LineItemField, FieldIssue> get() = lineEditor?.let { lineRules.issues(it.draft) } ?: emptyMap()

    fun visibleLineIssue(field: LineItemField): FieldIssue? = lineEditor?.takeIf { it.attemptedDone }?.let { lineEditorIssues[field] }

    fun rateChoices(selected: String?): List<TaxRate> = rules.rateChoices(document, selected)

    // Loading and saving

    fun load() {
        if (loadStarted) return
        loadStarted = true
        session.scope.launch {
            val container = session.container
            try {
                val stored = container.documents.fetchDocument(route.id)
                if (stored != null) {
                    document = stored
                    isPersisted = true
                } else if (route is DocumentRoute.Existing) {
                    notFound = true
                }
                document.clientId?.let { id ->
                    client = container.clients.fetchClient(id)
                    clientMissing = client == null
                }
                if (document.docType == DocumentType.invoice && document.lifecycle == DocumentLifecycle.issued) {
                    payments = container.payments.fetchPayments(document.id)
                }
            } catch (error: Exception) {
                errorMessage = "This document couldn't be opened."
            }
            resetTexts()
            recompute()
            isLoaded = true
        }
    }

    // PDF preview

    val canPreview get() = computed != null

    /** What the renderer draws: a draft prepared exactly as it would be stored. */
    val documentToRender: Document get() = if (isDraft) rules.preparedDraft(document, client) else document

    fun openPreview(reminderMessage: String? = null) {
        val computed = computed ?: return
        if (preview != null) return
        session.scope.launch {
            if (isDraft) flush()
            preview = DocumentPreviewViewModel(session, documentToRender, computed, reminderMessage) { sentAt -> document = document.copy(sentAt = sentAt) }
        }
    }

    val canSendReminder: Boolean
        get() = document.docType == DocumentType.invoice && document.status(session.today, paidMinor) != DocumentStatus.paid &&
            document.lifecycle != DocumentLifecycle.void

    fun sendReminder() {
        if (!canSendReminder) return
        val due = document.dueDate?.displayText
        openPreview(ReminderMessage.text(document, paidMinor, session.business, { minor, currency -> session.money(minor, currency) }, due))
    }

    /** Saves now if anything changed (before issuing, leaving the screen or going to the background). */
    suspend fun flush() {
        itemSave?.join()
        saveJob?.cancel()
        saveJob = null
        save()
    }

    /** Leaving the builder: an untouched draft (no client, no lines) is deleted; anything else is saved. */
    suspend fun close() {
        if (!isDraft || !isLoaded || notFound) return
        if (document.clientId == null && document.lines.isEmpty()) {
            saveJob?.cancel()
            isDirty = false
            saveLock.withLock {}
            if (isPersisted) {
                runCatching { session.container.documentService.deleteDraft(document.id) }
                isPersisted = false
            }
            return
        }
        flush()
    }

    /** Each save waits for the one before, so writes land in order (≈ the chained `lastSave` task). */
    private suspend fun save() = saveLock.withLock { write() }

    private suspend fun write() {
        if (!isDirty || !isDraft) return
        isDirty = false
        val prepared = rules.preparedDraft(document, client)
        try {
            val stored = session.container.documents.saveDraft(prepared)
            document = document.copy(createdAt = stored.createdAt, updatedAt = stored.updatedAt)
            isPersisted = true
            saveFailed = false
        } catch (error: Exception) {
            isDirty = true
            saveFailed = true
        }
    }

    private fun scheduleSave() {
        saveJob?.cancel()
        saveJob = session.scope.launch {
            delay(autosaveDelayMs)
            save()
        }
    }

    /** Applies an edit to the draft, recomputes and schedules the autosave. */
    private fun mutate(change: (Document) -> Document) {
        if (!isDraft || !isLoaded) return
        document = change(document)
        recompute()
        if (issueProblems.isNotEmpty()) issueProblems = currentProblems()
        isDirty = true
        scheduleSave()
    }

    private fun recompute() {
        if (!isDraft) {
            result = document.computed?.let { Outcome.Success(it) }
            return
        }
        result = rules.compute(document, rules.sellerSnapshot(config), rules.buyerSnapshot(document, client))
    }

    private fun resetTexts() {
        val (text, isPercent) = DocumentInput.editingText(document.discount, exponent)
        discountText = text
        discountIsPercent = isPercent
        shippingText = DocumentInput.editingText(document.shippingMinor, exponent)
        exchangeRateText = document.exchangeRate ?: ""
        notesText = document.notes ?: ""
        termsText = document.terms ?: ""
    }

    private fun currentProblems(): List<IssueProblem> =
        rules.issueProblems(document, result ?: Outcome.Failure(TaxEngineError(TaxEngineError.Code.InvalidInput)))

    // Header intents (§2.2)

    fun setDocType(docType: DocumentType) = mutate { rules.setDocType(docType, it) }
    fun setIssueDate(date: LocalDate) = mutate { rules.setIssueDate(date, it) }
    fun setDueDate(date: LocalDate) = mutate { it.copy(dueDate = date) }
    fun setDue(daysAfterIssue: Long) = mutate { it.copy(dueDate = it.issueDate.plusDays(daysAfterIssue)) }
    /** Null defers to `business.reminderDaysAfterDue` (`spec/reminders.md` §1). */
    fun setReminderOverride(days: Int?) = mutate { it.copy(reminderDaysAfterDueOverride = days) }
    fun setValidUntil(date: LocalDate) = mutate { it.copy(validUntil = date) }

    /**
     * The "When should they pay?" chips (`documents.md` §3.3): invoices 0, 7, 15, 30 days plus the business's own
     * terms; quotes 7, 15, 30, 60 days of validity.
     */
    val termChoices: List<Int>
        get() = if (document.docType == DocumentType.quote) listOf(7, 15, 30, 60)
        else (setOf(0, 7, 15, 30, session.business.paymentTermsDays)).sorted()

    /** The chip matching the due date (validity for quotes), if any. */
    val selectedTermDays: Int?
        get() {
            val target = (if (document.docType == DocumentType.quote) document.validUntil else document.dueDate) ?: return null
            val days = java.time.temporal.ChronoUnit.DAYS.between(document.issueDate, target).toInt()
            return days.takeIf { it in termChoices }
        }

    fun setTerm(days: Int) {
        if (document.docType == DocumentType.quote) setValidUntil(document.issueDate.plusDays(days.toLong()))
        else setDue(days.toLong())
    }
    fun setSupplyDate(date: LocalDate?) = mutate { it.copy(supplyDate = date) }

    fun chooseClient(client: Client?) {
        val previousCurrency = document.currency
        this.client = client
        clientMissing = false
        mutate { rules.setClient(client, it) }
        if (document.currency != previousCurrency) currencyTextsChanged()
    }

    fun setSupplyType(id: String) = mutate { it.copy(supplyType = id) }
    fun setPlaceOfSupply(code: String?) = mutate { it.copy(placeOfSupply = code) }
    fun setReverseCharge(on: Boolean) = mutate { it.copy(reverseCharge = on) }
    fun setPricesIncludeTax(on: Boolean) = mutate { it.copy(pricesIncludeTax = on) }
    fun setRoundOff(on: Boolean) = mutate { it.copy(roundOff = on) }

    fun setCurrency(currency: CurrencyCode) {
        if (currency == document.currency) return
        mutate { rules.setCurrency(currency, it) }
        currencyTextsChanged()
    }

    /** A new currency has a new exchange rate and maybe other fraction digits: re-read the typed amounts. */
    private fun currencyTextsChanged() {
        exchangeRateText = document.exchangeRate ?: ""
        val discount = (DocumentInput.discount(discountText, discountIsPercent, exponent) as? Outcome.Success)?.value
        mutate { it.copy(discount = discount) }
        val shipping = (DocumentInput.shipping(shippingText, exponent) as? Outcome.Success)?.value
        mutate { it.copy(shippingMinor = shipping ?: 0) }
    }

    fun setExchangeRateText(text: String) {
        exchangeRateText = text
        (DocumentInput.exchangeRate(text) as? Outcome.Success)?.let { rate -> mutate { it.copy(exchangeRate = rate.value) } }
    }

    fun setDiscountText(text: String) { discountText = text; applyDiscount() }
    fun setDiscountIsPercent(isPercent: Boolean) { discountIsPercent = isPercent; applyDiscount() }

    private fun applyDiscount() {
        (DocumentInput.discount(discountText, discountIsPercent, exponent) as? Outcome.Success)?.let { d -> mutate { it.copy(discount = d.value) } }
    }

    fun setShippingText(text: String) {
        shippingText = text
        (DocumentInput.shipping(text, exponent) as? Outcome.Success)?.let { s -> mutate { it.copy(shippingMinor = s.value) } }
    }

    fun setNotesText(text: String) { notesText = text; mutate { it.copy(notes = text.trimmedOrNull) } }
    fun setTermsText(text: String) { termsText = text; mutate { it.copy(terms = text.trimmedOrNull) } }

    // Lines (§3)

    /** Adds a catalogue line; true when its price could not be converted, so the line editor asks for it. */
    fun addItem(item: CatalogItem): Boolean {
        val (line, needsPrice) = rules.line(item, document, session.container.ids.make())
        mutate { it.copy(lines = it.lines + line) }
        selectedLineID = line.id
        // "Something new" was prepared before this line existed: give it this line's rate (`documents.md` §3).
        lineEditor?.takeIf { it.isNew && it.draft.rateId.isEmpty() }?.let { editor ->
            lineEditor = editor.copy(draft = editor.draft.copy(rateId = rules.oneOffRateID(document)))
        }
        if (needsPrice) {
            editLine(line.id)
            lineEditor = lineEditor?.copy(needsPrice = true)
        }
        return needsPrice
    }

    fun addLine() {
        if (!isDraft) return
        lineEditor = LineEditorState(session.container.ids.make(), true, LineItemDraft(rateId = rules.oneOffRateID(document)),
            includesTax = document.pricesIncludeTax, saveToItems = !isForeignCurrency)
    }

    fun editLine(id: String) {
        if (!isDraft) return
        val line = document.lines.firstOrNull { it.id == id } ?: return
        lineEditor = LineEditorState(id, false, LineItemDraft.of(line, exponent), includesTax = document.pricesIncludeTax)
        selectedLineID = id
    }

    fun updateLineDraft(draft: LineItemDraft) { lineEditor = lineEditor?.copy(draft = draft) }
    fun setLineIncludesTax(on: Boolean) { lineEditor = lineEditor?.copy(includesTax = on) }
    fun setLineSaveToItems(on: Boolean) { lineEditor = lineEditor?.copy(saveToItems = on) }

    /** "Save to my items" is offered for a new line in the home currency (`documents.md` §3.2). */
    val canSaveLineToItems: Boolean get() = lineEditor?.isNew == true && !isForeignCurrency

    /** The rate chips, the other rates in force and the hint under the chips. */
    val lineRateChoices: RateChips.Choices
        get() {
            val choices = session.rateChips.choices(config, session.business.customRates, document.effectiveDate)
            val selected = lineEditor?.draft?.rateId?.takeIf { it.isNotEmpty() } ?: return choices
            if ((choices.chips + choices.others).any { it.id == selected }) return choices
            val saved = config.rate(selected, session.business.customRates) ?: return choices
            return choices.copy(others = choices.others + saved) // a saved rate no longer in force stays
        }

    /** − / + on "How many?": whole steps, never below 1 (a typed 0.5 can still go up). */
    fun stepLineQuantity(by: Int) {
        val editor = lineEditor ?: return
        val parsed = (DecimalInput.parse(editor.draft.quantityText) as? Outcome.Success)?.value?.let(DecimalString::parse)
        if (parsed == null) {
            updateLineDraft(editor.draft.copy(quantityText = "1"))
            return
        }
        val next = parsed + java.math.BigDecimal(by)
        if (next < java.math.BigDecimal.ONE && by < 0) return
        updateLineDraft(editor.draft.copy(quantityText = SpecFormatter.quantity(next.toPlainString())))
    }

    private data class LinePrice(val minor: Long, val typed: Long, val setsBasis: Boolean)

    /** The price the line gets: as typed when the switch matches the document's basis (or sets it), else converted. */
    private fun linePrice(editor: LineEditorState): LinePrice? {
        val typed = (MoneyInput.parse(editor.draft.priceText, exponent) as? Outcome.Success)?.value ?: return null
        val setsBasis = chargesTax && OneOffLine.setsDocumentBasis(document, if (editor.isNew) null else editor.lineID)
        if (setsBasis) return LinePrice(typed, typed, true)
        val price = OneOffLine.unitPrice(typed, editor.includesTax, config.rate(editor.draft.rateId, session.business.customRates),
            document, chargesTax, session.container.reference.currencies, config.rounding.amountMode)
        return LinePrice(price, typed, false)
    }

    /** The engine's result for this line alone, as the sheet shows it under the fields. */
    val lineEditorPreview: LinePreview?
        get() {
            val editor = lineEditor ?: return null
            val price = linePrice(editor) ?: return null
            val quantity = (DecimalInput.parse(editor.draft.quantityText) as? Outcome.Success)?.value ?: return null
            if (chargesTax && editor.draft.rateId.isEmpty()) return null
            val discount = (DocumentInput.discount(editor.draft.discountText, editor.draft.discountIsPercent, exponent) as? Outcome.Success)?.value
            val line = LineItem(editor.lineID, description = "–", quantity = quantity, unitPriceMinor = price.minor,
                rateId = editor.draft.rateId, discount = discount)
            var preview = document.copy(lines = listOf(line), discount = null, shippingMinor = 0)
            if (price.setsBasis) preview = preview.copy(pricesIncludeTax = editor.includesTax)
            val computed = (rules.compute(preview, rules.sellerSnapshot(config), rules.buyerSnapshot(preview, client)) as? Outcome.Success)?.value
                ?: return null
            val result = computed.lines.firstOrNull() ?: return null
            val currency = preview.currency
            val tax = result.tax
            val taxName = config.labels.taxName
            var text = "${SpecFormatter.quantity(quantity)} × ${session.money(price.typed, currency)}"
            if (chargesTax) {
                text += when {
                    tax == 0L -> " · no $taxName"
                    preview.pricesIncludeTax || editor.includesTax -> " incl. ${session.money(tax, currency)} $taxName"
                    else -> " + ${session.money(tax, currency)} $taxName"
                }
            }
            return LinePreview(text, session.money(result.taxable + tax, currency))
        }

    /** Done in the line editor: applies the line, or shows its problems. True when the editor can close. */
    fun commitLineEditor(): Boolean {
        val editor = lineEditor?.copy(attemptedDone = true) ?: return true
        lineEditor = editor
        val rules = lineRules
        if (rules.issues(editor.draft).isNotEmpty()) return false
        val price = linePrice(editor) ?: return false
        mutate { current ->
            val document = if (price.setsBasis) current.copy(pricesIncludeTax = editor.includesTax) else current
            val index = document.lines.indexOfFirst { it.id == editor.lineID }
            if (index >= 0) {
                document.copy(lines = document.lines.toMutableList().also {
                    it[index] = rules.apply(editor.draft, it[index]).copy(unitPriceMinor = price.minor)
                })
            } else {
                val line = rules.apply(editor.draft, LineItem(editor.lineID, position = document.lines.size)).copy(unitPriceMinor = price.minor)
                document.copy(lines = document.lines + line)
            }
        }
        if (editor.isNew && editor.saveToItems && !isForeignCurrency) saveToMyItems(editor.lineID, price.typed, editor.includesTax)
        selectedLineID = editor.lineID
        lineEditor = null
        return true
    }

    /** Writes the catalogue item, then links the line to it (the line's foreign key needs the item first). */
    private fun saveToMyItems(lineID: String, typedMinor: Long, includesTax: Boolean) {
        val line = document.lines.firstOrNull { it.id == lineID } ?: return
        val container = session.container
        val item = OneOffLine.catalogItem(line, typedMinor, includesTax, chargesTax, document.businessId, homeCurrency,
            container.ids.make(), container.time.now())
        val previous = itemSave
        itemSave = session.scope.launch {
            previous?.join()
            try {
                container.catalog.save(item)
                mutate { document ->
                    document.copy(lines = document.lines.map { if (it.id == lineID) it.copy(catalogItemId = item.id) else it })
                }
            } catch (error: Exception) {
                errorMessage = "The item was added, but it couldn't be saved to your items."
            }
        }
    }

    /** Waits until "Save to my items" has written its catalogue items (tests, and before saving). */
    suspend fun waitForItemSaves() { itemSave?.join() }

    fun cancelLineEditor() { lineEditor = null }

    fun deleteLine(id: String) {
        mutate { document -> document.copy(lines = renumber(document.lines.filter { it.id != id })) }
        if (selectedLineID != null && document.lines.none { it.id == selectedLineID }) selectedLineID = null
    }

    fun moveLine(from: Int, to: Int) {
        mutate { document ->
            val lines = document.lines.toMutableList()
            if (from !in lines.indices || to !in lines.indices) return@mutate document
            lines.add(to, lines.removeAt(from))
            document.copy(lines = renumber(lines))
        }
    }

    fun duplicateLine(id: String) {
        val index = document.lines.indexOfFirst { it.id == id }
        if (index < 0) return
        val copy = document.lines[index].copy(id = session.container.ids.make())
        mutate { document -> document.copy(lines = renumber(document.lines.toMutableList().also { it.add(index + 1, copy) })) }
        selectedLineID = copy.id
    }

    private fun renumber(lines: List<LineItem>) = lines.mapIndexed { index, line -> line.copy(position = index) }

    // Actions (§6–9)

    /** Issue tapped: shows what blocks issuing, or asks for confirmation with the number it will get. */
    fun requestIssue() {
        if (!canRequestIssue) return
        if (document.docType == DocumentType.invoice && !session.entitlement.canIssueInvoice) {
            showsPaywall = true
            return
        }
        val problems = currentProblems()
        issueProblems = problems
        if (problems.isNotEmpty()) return
        session.scope.launch {
            val series = runCatching { session.container.numberingSeries.observeSeries(document.businessId).first() }.getOrDefault(emptyList())
            val owned = NumberAllocator.series(document.docType, session.deviceID, series)
            if (owned == null) {
                seriesChoice = seriesChoice(series)
                if (seriesChoice == null) issueProblems = listOf(IssueProblem.NoSeries)
                return@launch
            }
            when (val allocation = NumberAllocator.allocate(owned, document.issueDate, config)) {
                is Outcome.Success -> {
                    numberPreview = allocation.value.number
                    confirmingIssue = true
                }
                is Outcome.Failure -> issueProblems = listOf(IssueProblem.Numbering(allocation.error))
            }
        }
    }

    /** What this device can number from (`spec/sync.md` §3): a new series of its own, or another device's. */
    private fun seriesChoice(series: List<NumberingSeries>): SeriesChoice? {
        val docType = document.docType
        val live = series.filter { it.deletedAt == null && it.docType == docType }
        val numbering = session.numberingRules
        val own = SeriesOwnership.deviceSeriesPattern(
            if (docType == DocumentType.quote) config.numbering.quotePattern else config.numbering.invoicePattern, docType, live.map { it.pattern },
        )
        val ownFirst = (own as? Outcome.Success)?.value?.let { value ->
            (numbering.preview(value.pattern, config.numbering.reset, 1) as? Outcome.Success)?.value?.number
        }
        val others = live.filter { it.ownerDeviceId != session.deviceID }.map { other ->
            SeriesChoice.Option(other, (numbering.nextNumber(other) as? Outcome.Success)?.value?.number)
        }
        if (ownFirst == null && others.isEmpty()) return null
        return SeriesChoice(ownFirst, others)
    }

    fun startOwnSeries() {
        seriesChoice = null
        session.scope.launch {
            try {
                session.container.numbering.createDeviceSeries(document.businessId, document.docType, session.deviceID)
                requestIssue()
            } catch (error: Exception) {
                errorMessage = "Numbering couldn't be set up on this device."
            }
        }
    }

    fun takeOver(seriesID: String) {
        seriesChoice = null
        session.scope.launch {
            try {
                session.container.numbering.takeOver(seriesID, session.deviceID)
                requestIssue()
            } catch (error: Exception) {
                errorMessage = "The series couldn't be taken over."
            }
        }
    }

    fun confirmIssue() {
        confirmingIssue = false
        if (!canRequestIssue) return
        session.scope.launch { issueNow() }
    }

    /** Issues the draft (`documents.md` §6); the document is issued when this returns without problems. */
    private suspend fun issueNow() {
        if (!canRequestIssue) return
        isWorking = true
        try {
            if (!saveBeforeAction()) return
            val issued = session.container.documentService.issue(document.id, session.deviceID)
            document = issued
            issueProblems = emptyList()
            lineEditor = null
            recompute()
            if (issued.docType == DocumentType.invoice) {
                session.container.entitlements.refreshCount()
                session.askForRemindersIfNeeded()
            }
        } catch (error: DocumentServiceError.Blocked) {
            issueProblems = error.problems
        } catch (error: Exception) {
            errorMessage = "The ${DocumentText.noun(document.docType)} couldn't be sent."
        } finally {
            isWorking = false
        }
    }

    // Review & send (§6.1, §8)

    /**
     * "Send on WhatsApp" etc.: closes the review and starts [sendAfterReview], which issues and opens the channel.
     * (iOS waits for its sheet to finish closing first; a Compose dialog can open while another closes.)
     */
    fun send(via: SendChannel) {
        pendingSend = via
        confirmingIssue = false
        session.scope.launch { sendAfterReview() }
    }

    /** "Keep as draft": closes the review and leaves the draft as it is. */
    fun keepAsDraft() {
        pendingSend = null
        confirmingIssue = false
    }

    /** Runs once the review has gone: issues the document, then shows the PDF and opens the channel. */
    suspend fun sendAfterReview() {
        val channel = pendingSend ?: return
        pendingSend = null
        issueNow()
        val computed = computed ?: return
        if (isDraft) return
        preview = DocumentPreviewViewModel(session, document, computed, null, channel) { sentAt -> document = document.copy(sentAt = sentAt) }
    }

    fun duplicate() {
        session.scope.launch {
            if (!saveBeforeAction()) return@launch
            try {
                show(session.container.documentService.duplicate(document.id))
            } catch (error: Exception) {
                errorMessage = "The ${DocumentText.noun(document.docType)} couldn't be duplicated."
            }
        }
    }

    fun convertToInvoice() {
        session.scope.launch {
            try {
                val invoice = session.container.documentService.convertQuote(document.id)
                document = document.copy(quoteOutcome = QuoteOutcome.converted)
                show(invoice)
            } catch (error: Exception) {
                errorMessage = "The quote couldn't be converted."
            }
        }
    }

    // Void, quote outcome and payments (§10–12)

    val canVoid get() = document.lifecycle == DocumentLifecycle.issued
    val canRespondToQuote get() = document.docType == DocumentType.quote && document.lifecycle == DocumentLifecycle.issued &&
        document.quoteOutcome != QuoteOutcome.converted
    val canRecordPayment get() = document.docType == DocumentType.invoice && document.lifecycle == DocumentLifecycle.issued
    val paidMinor: Long get() = payments.sumOf { it.amountMinor }

    fun voidDocument(reason: String) {
        if (!canVoid) return
        session.scope.launch {
            isWorking = true
            try {
                document = session.container.documentService.voidDocument(document.id, reason)
                session.reconcileReminders()
            } catch (error: DocumentServiceError.VoidReasonRequired) {
                errorMessage = "Add a reason before voiding."
            } catch (error: Exception) {
                errorMessage = "The ${DocumentText.noun(document.docType)} couldn't be voided."
            } finally {
                isWorking = false
            }
        }
    }

    fun acceptQuote() = respondToQuote { session.container.documentService.acceptQuote(it) }
    fun declineQuote() = respondToQuote { session.container.documentService.declineQuote(it) }

    private fun respondToQuote(action: suspend (String) -> Document) {
        if (!canRespondToQuote) return
        session.scope.launch {
            isWorking = true
            try {
                document = action(document.id)
            } catch (error: Exception) {
                errorMessage = "The quote couldn't be updated."
            } finally {
                isWorking = false
            }
        }
    }

    /** The payment editor already wrote it; keep the list and status here in step. */
    fun recordedPayment(payment: Payment) {
        payments = listOf(payment) + payments
        paymentsRecorded += 1
        session.reconcileReminders()
    }

    /** Correcting a payment is delete-and-re-add, never an in-place edit (`spec/documents.md` §10). */
    fun deletePayment(payment: Payment) {
        session.scope.launch {
            try {
                session.container.payments.softDelete(payment.id)
                payments = payments.filter { it.id != payment.id }
                session.reconcileReminders()
            } catch (error: Exception) {
                errorMessage = "The payment couldn't be removed."
            }
        }
    }

    fun deleteDraft() {
        if (!isDraft) return
        session.scope.launch {
            saveJob?.cancel()
            isDirty = false
            saveLock.withLock {}
            try {
                if (isPersisted) session.container.documentService.deleteDraft(document.id)
                isPersisted = false
                document = document.copy(lines = emptyList(), clientId = null)
                session.pdfLibrary.forget(document.id)
                session.router.documents.didRemove(document.id)
            } catch (error: Exception) {
                errorMessage = "The draft couldn't be deleted."
            }
        }
    }

    /** Writes everything before an action that reads the stored document. False when the save failed. */
    private suspend fun saveBeforeAction(): Boolean {
        if (!isDraft) return true
        isDirty = isDirty || !isPersisted
        flush()
        if (isDirty || !isPersisted) {
            errorMessage = "Your latest changes couldn't be saved, so nothing was issued or copied. Check the device's storage and try again."
            return false
        }
        return true
    }

    private fun show(document: Document) {
        val router = session.router.documents
        router.docType = document.docType
        router.open(document.id)
    }
}
