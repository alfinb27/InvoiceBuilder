package app.invoicebuilder.android.documents

import androidx.compose.runtime.getValue
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
    )

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
    var paymentsRecorded by mutableStateOf(0)
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
    var confirmingIssue by mutableStateOf(false)
    var numberPreview by mutableStateOf<String?>(null)
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
        if (needsPrice) {
            editLine(line.id)
            lineEditor = lineEditor?.copy(needsPrice = true)
        }
        return needsPrice
    }

    fun addLine() {
        if (!isDraft) return
        lineEditor = LineEditorState(session.container.ids.make(), true, LineItemDraft(rateId = rules.oneOffRateID(document)))
    }

    fun editLine(id: String) {
        if (!isDraft) return
        val line = document.lines.firstOrNull { it.id == id } ?: return
        lineEditor = LineEditorState(id, false, LineItemDraft.of(line, exponent))
        selectedLineID = id
    }

    fun updateLineDraft(draft: LineItemDraft) { lineEditor = lineEditor?.copy(draft = draft) }

    /** Done in the line editor: applies the line, or shows its problems. True when the editor can close. */
    fun commitLineEditor(): Boolean {
        val editor = lineEditor?.copy(attemptedDone = true) ?: return true
        lineEditor = editor
        val rules = lineRules
        if (rules.issues(editor.draft).isNotEmpty()) return false
        mutate { document ->
            val index = document.lines.indexOfFirst { it.id == editor.lineID }
            if (index >= 0) {
                document.copy(lines = document.lines.toMutableList().also { it[index] = rules.apply(editor.draft, it[index]) })
            } else {
                document.copy(lines = document.lines + rules.apply(editor.draft, LineItem(editor.lineID, position = document.lines.size)))
            }
        }
        selectedLineID = editor.lineID
        lineEditor = null
        return true
    }

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
        session.scope.launch {
            isWorking = true
            try {
                if (!saveBeforeAction()) return@launch
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
                errorMessage = "The ${DocumentText.noun(document.docType)} couldn't be issued."
            } finally {
                isWorking = false
            }
        }
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
