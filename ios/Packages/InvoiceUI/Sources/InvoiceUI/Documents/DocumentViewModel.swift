import Foundation
import InvoiceCore
import Observation

/// One invoice or quote: the builder while it is a draft (`spec/documents.md` §2–5, autosaved), the read-only view
/// once issued, and the issue / duplicate / convert / delete actions. Totals always come from `TaxEngine`.
@MainActor @Observable
final class DocumentViewModel {
    struct State: Equatable {
        var document: Document
        var isLoaded = false
        var notFound = false
        /// The draft has been written at least once.
        var isPersisted = false
        /// The live client (drafts); nil without one or when it was deleted.
        var client: Client?
        var clientMissing = false
        /// The engine result: recomputed for drafts, the stored one for issued documents.
        var result: Result<ComputedDocument, TaxEngineError>?
        /// This invoice's live payments (`documents.md` §10), newest first; empty for quotes and drafts.
        var payments: [Payment] = []
        /// Payments recorded while this document is open (drives the success haptic).
        var paymentsRecorded = 0

        // Typed fields, kept as typed; the document holds their last valid value.
        var discountText = ""
        var discountIsPercent = true
        var shippingText = ""
        var exchangeRateText = ""
        var notesText = ""
        var termsText = ""

        var saveFailed = false
        /// Shown after Issue was tapped and something blocks it.
        var issueProblems: [IssueProblem] = []
        /// The Review & send screen is open (`documents.md` §6.1): the checks passed and `numberPreview` is set.
        var confirmingIssue = false
        var numberPreview: String?
        /// Chosen on Review & send: once the review closes, the document is issued and the PDF goes out this way.
        var pendingSend: SendChannel?
        /// This device owns no series of the document's type: start one or take one over (`spec/sync.md` §3).
        var seriesChoice: SeriesChoice?
        /// The free tier is used up and this is an invoice (`spec/billing.md`): only Issue is locked.
        var showsPaywall = false
        var isWorking = false
        var errorMessage: String?
        var lineEditor: LineEditorState?
        /// The line last added or edited (⌘D duplicates it).
        var selectedLineID: String?
    }

    struct SeriesChoice: Equatable, Identifiable {
        struct Option: Equatable, Identifiable {
            let series: NumberingSeries
            /// The number the next document would get after taking the series over.
            let nextNumber: String?
            var id: String { series.id }
        }

        let id = UUID()
        /// The first number of a new series on this device, or nil when no device letter is left.
        let ownFirstNumber: String?
        /// Live series of the type owned by other devices.
        let others: [Option]
    }

    struct LineEditorState: Equatable, Identifiable {
        let lineID: String
        let isNew: Bool
        var draft: LineItemDraft
        var attemptedDone = false
        /// The catalogue price could not be converted to the document currency.
        var needsPrice = false
        /// "My price already includes {tax}": how the typed price is read (`documents.md` §3.2).
        var includesTax = false
        /// "Save to my items so I can reuse it": new lines in the home currency only.
        var saveToItems = false

        var id: String { lineID }
    }

    /// The live total of the line being edited: "2 × ₹2,500 + ₹900 GST" and "₹5,900".
    struct LinePreview: Equatable {
        let text: String
        let total: String
    }

    var state: State
    let route: DocumentRoute
    private let session: Session
    private let autosaveDelay: Duration
    /// The pending autosave (debounced).
    private var saveTask: Task<Void, Never>?
    /// The last save started; each save waits for the one before, so writes land in order and `flush()` returns
    /// only when everything is written.
    private var lastSave: Task<Void, Never>?
    /// "Save to my items": the catalogue item is written first, then the line is linked to it.
    private var itemSave: Task<Void, Never>?
    private var isDirty = false

    init(session: Session, route: DocumentRoute, autosaveDelay: Duration = .milliseconds(500)) {
        self.session = session
        self.route = route
        self.autosaveDelay = autosaveDelay
        let dependencies = session.dependencies
        var docType = DocumentType.invoice
        if case .new(let type, _) = route { docType = type }
        state = State(document: session.documentRules.newDocument(
            docType: docType, id: route.id, today: dependencies.time.today(), now: dependencies.time.now()))
    }

    // MARK: Derived

    var rules: DocumentRules { session.documentRules }
    var config: TaxConfig { rules.config(for: state.document) }
    var chargesTax: Bool { rules.chargesTax(config) }
    var isDraft: Bool { state.document.isDraft }
    var exponent: Int { session.dependencies.reference.currencies.exponent(of: state.document.currency) }
    var homeCurrency: CurrencyCode { session.business.homeCurrency }
    var isForeignCurrency: Bool { state.document.currency != homeCurrency }

    var computed: ComputedDocument? {
        if case .success(let computed)? = state.result { computed } else { nil }
    }

    var engineError: TaxEngineError? {
        if case .failure(let error)? = state.result { error } else { nil }
    }

    var showsSupplyType: Bool { chargesTax && config.supplyTypes.count > 1 }
    var showsPlaceOfSupply: Bool { chargesTax && !config.regions.isEmpty }
    var showsReverseCharge: Bool { chargesTax && config.reverseCharge.supported }
    var showsPricesIncludeTax: Bool { chargesTax }
    var showsRoundOff: Bool { config.rounding.grandTotal != nil }
    var roundOffOn: Bool { state.document.roundOff ?? config.rounding.grandTotal?.defaultOn ?? false }

    /// The place of supply the engine derives when none is set (shown as "Automatic (…)").
    var derivedPlaceOfSupply: String? {
        guard showsPlaceOfSupply else { return nil }
        var automatic = state.document
        automatic.placeOfSupply = nil
        let seller = rules.sellerSnapshot(config: config)
        let buyer = rules.buyerSnapshot(for: automatic, client: state.client)
        return try? rules.compute(automatic, seller: seller, buyer: buyer).get().placeOfSupply
    }

    var discountIssue: FieldIssue? {
        if case .failure(let issue) = DocumentInput.discount(state.discountText, isPercent: state.discountIsPercent,
                                                             exponent: exponent) { issue } else { nil }
    }

    var shippingIssue: FieldIssue? {
        if case .failure(let issue) = DocumentInput.shipping(state.shippingText, exponent: exponent) {
            issue
        } else {
            nil
        }
    }

    var exchangeRateIssue: FieldIssue? {
        if case .failure(let issue) = DocumentInput.exchangeRate(state.exchangeRateText) { issue } else { nil }
    }

    /// Engine issues to show while editing (warnings and blocking errors).
    var engineIssues: [EngineIssue] { computed?.issues ?? [] }

    var canRequestIssue: Bool { isDraft && state.isLoaded && !state.isWorking }
    var canConvert: Bool { rules.canConvert(state.document) }

    var lineRules: LineItemRules { rules.lineRules(for: state.document) }

    var lineEditorIssues: [LineItemField: FieldIssue] {
        state.lineEditor.map { lineRules.issues($0.draft) } ?? [:]
    }

    func visibleLineIssue(_ field: LineItemField) -> FieldIssue? {
        guard let editor = state.lineEditor, editor.attemptedDone else { return nil }
        return lineEditorIssues[field]
    }

    func rateChoices(selected: String?) -> [TaxRate] {
        rules.rateChoices(for: state.document, selected: selected)
    }

    // MARK: Loading and saving

    func load() async {
        guard !state.isLoaded else { return }
        let dependencies = session.dependencies
        do {
            if let stored = try await dependencies.documents.fetchDocument(id: route.id) {
                state.document = stored
                state.isPersisted = true
            } else if case .existing = route {
                state.notFound = true
            }
            if let clientID = state.document.clientId {
                state.client = try await dependencies.clients.fetchClient(id: clientID)
                state.clientMissing = state.client == nil
            }
            if state.document.docType == .invoice, state.document.lifecycle == .issued {
                state.payments = try await dependencies.payments.fetchPayments(documentID: state.document.id)
            }
        } catch {
            state.errorMessage = "This document couldn't be opened."
        }
        resetTexts()
        recompute()
        state.isLoaded = true
    }

    // MARK: PDF preview (`spec/pdf/RENDERING.md`, `spec/documents.md` §8)

    /// The open preview sheet, or nil. It lives beside `State` because it is a view model, not a value.
    var preview: DocumentPreviewViewModel?

    var canPreview: Bool { computed != nil }

    /// What the renderer draws. A draft is prepared exactly as it would be stored, so the seller and buyer
    /// snapshots on the page are the ones that would be frozen at issue.
    var documentToRender: Document {
        isDraft ? rules.preparedDraft(state.document, client: state.client) : state.document
    }

    /// The Preview button and ⌘P. A draft is saved first, so the file matches what is on screen. `reminderMessage`
    /// is set only by "Send reminder" (`spec/reminders.md` §4), shared alongside the PDF.
    func openPreview(reminderMessage: String? = nil) async {
        guard let computed, preview == nil else { return }
        if isDraft { await flush() }
        preview = DocumentPreviewViewModel(session: session, document: documentToRender, computed: computed,
                                           reminderMessage: reminderMessage) { [weak self] sentAt in
            self?.state.document.sentAt = sentAt
        }
    }

    /// "Send reminder" (`spec/reminders.md` §4): available while the derived status is not paid and not void.
    var canSendReminder: Bool {
        state.document.docType == .invoice && state.document.status(today: session.today, paid: paidMinor) != .paid
            && state.document.lifecycle != .void
    }

    func sendReminder() async {
        guard canSendReminder else { return }
        await openPreview(reminderMessage: ReminderMessage.text(document: state.document, paidMinor: paidMinor,
                                                                 session: session))
    }

    /// Saves now if anything changed (before issuing, leaving the screen or going to the background).
    func flush() async {
        await itemSave?.value
        saveTask?.cancel()
        saveTask = nil
        await save()
    }

    /// Leaving the builder: an untouched draft (no client, no lines) is deleted; anything else is saved.
    func close() async {
        guard isDraft, state.isLoaded, !state.notFound else { return }
        if state.document.clientId == nil, state.document.lines.isEmpty {
            saveTask?.cancel()
            isDirty = false
            await lastSave?.value
            if state.isPersisted {
                try? await session.dependencies.documentService.deleteDraft(documentID: state.document.id)
                state.isPersisted = false
            }
            return
        }
        await flush()
    }

    private func save() async {
        let previous = lastSave
        let save = Task { [weak self] in
            await previous?.value
            await self?.write()
        }
        lastSave = save
        await save.value
    }

    private func write() async {
        guard isDirty, isDraft else { return }
        isDirty = false
        let prepared = rules.preparedDraft(state.document, client: state.client)
        do {
            let stored = try await session.dependencies.documents.saveDraft(prepared)
            state.document.createdAt = stored.createdAt
            state.document.updatedAt = stored.updatedAt
            state.isPersisted = true
            state.saveFailed = false
        } catch {
            isDirty = true
            state.saveFailed = true
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let delay = autosaveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// Applies an edit to the draft, recomputes and schedules the autosave.
    private func mutate(_ change: (inout Document) -> Void) {
        guard isDraft, state.isLoaded else { return }
        change(&state.document)
        recompute()
        if !state.issueProblems.isEmpty { state.issueProblems = currentProblems() }
        isDirty = true
        scheduleSave()
    }

    private func recompute() {
        guard isDraft else {
            state.result = state.document.computed.map { .success($0) }
            return
        }
        let seller = rules.sellerSnapshot(config: config)
        let buyer = rules.buyerSnapshot(for: state.document, client: state.client)
        state.result = rules.compute(state.document, seller: seller, buyer: buyer)
    }

    private func resetTexts() {
        let document = state.document
        let discount = DocumentInput.editingText(document.discount, exponent: exponent)
        state.discountText = discount.text
        state.discountIsPercent = discount.isPercent
        state.shippingText = DocumentInput.editingText(minor: document.shippingMinor, exponent: exponent)
        state.exchangeRateText = document.exchangeRate ?? ""
        state.notesText = document.notes ?? ""
        state.termsText = document.terms ?? ""
    }

    private func currentProblems() -> [IssueProblem] {
        rules.issueProblems(state.document, result: state.result ?? .failure(TaxEngineError(.invalidInput)))
    }

    // MARK: Header intents (§2.2)

    func setDocType(_ docType: DocumentType) {
        mutate { rules.setDocType(docType, on: &$0) }
    }

    func setIssueDate(_ date: LocalDate) {
        mutate { rules.setIssueDate(date, on: &$0) }
    }

    func setDueDate(_ date: LocalDate) {
        mutate { $0.dueDate = date }
    }

    /// Payment-terms presets: due N days after the issue date.
    func setDue(daysAfterIssue days: Int) {
        mutate { $0.dueDate = $0.issueDate.adding(days: days) }
    }

    /// Nil defers to `business.reminderDaysAfterDue` (`spec/reminders.md` §1).
    /// The "When should they pay?" chips (`documents.md` §3.3): invoices 0, 7, 15, 30 days plus the business's
    /// own terms; quotes 7, 15, 30, 60 days of validity.
    var termChoices: [Int] {
        if state.document.docType == .quote { return [7, 15, 30, 60] }
        let terms = session.business.paymentTermsDays
        return Set([0, 7, 15, 30, terms]).sorted()
    }

    /// The chip matching the due date (validity for quotes), if any.
    var selectedTermDays: Int? {
        let document = state.document
        let target = document.docType == .quote ? document.validUntil : document.dueDate
        guard let days = target.map({ $0.daysSinceEpoch - document.issueDate.daysSinceEpoch }),
              termChoices.contains(days) else { return nil }
        return days
    }

    func setTerm(days: Int) {
        if state.document.docType == .quote {
            setValidUntil(state.document.issueDate.adding(days: days))
        } else {
            setDue(daysAfterIssue: days)
        }
    }

    func setReminderOverride(_ days: Int?) {
        mutate { $0.reminderDaysAfterDueOverride = days }
    }

    func setValidUntil(_ date: LocalDate) {
        mutate { $0.validUntil = date }
    }

    func setSupplyDate(_ date: LocalDate?) {
        mutate { $0.supplyDate = date }
    }

    func chooseClient(_ client: Client?) {
        let previousCurrency = state.document.currency
        state.client = client
        state.clientMissing = false
        mutate { rules.setClient(client, on: &$0) }
        if state.document.currency != previousCurrency { currencyTextsChanged() }
    }

    func setSupplyType(_ id: String) {
        mutate { $0.supplyType = id }
    }

    func setPlaceOfSupply(_ code: String?) {
        mutate { $0.placeOfSupply = code }
    }

    func setReverseCharge(_ on: Bool) {
        mutate { $0.reverseCharge = on }
    }

    func setPricesIncludeTax(_ on: Bool) {
        mutate { $0.pricesIncludeTax = on }
    }

    func setRoundOff(_ on: Bool) {
        mutate { $0.roundOff = on }
    }

    func setCurrency(_ currency: CurrencyCode) {
        guard currency != state.document.currency else { return }
        mutate { rules.setCurrency(currency, on: &$0) }
        currencyTextsChanged()
    }

    /// A new currency has a new exchange rate and maybe other fraction digits: re-read the typed amounts. Text that
    /// no longer fits (12.50 in yen) clears its value instead of keeping the old minor amount, which would mean a
    /// different sum in the new currency.
    private func currencyTextsChanged() {
        state.exchangeRateText = state.document.exchangeRate ?? ""
        let discount = try? DocumentInput.discount(state.discountText, isPercent: state.discountIsPercent,
                                                   exponent: exponent).get()
        mutate { $0.discount = discount ?? nil }
        let shipping = try? DocumentInput.shipping(state.shippingText, exponent: exponent).get()
        mutate { $0.shippingMinor = shipping ?? 0 }
    }

    func setExchangeRateText(_ text: String) {
        state.exchangeRateText = text
        if case .success(let rate) = DocumentInput.exchangeRate(text) { mutate { $0.exchangeRate = rate } }
    }

    func setDiscountText(_ text: String) {
        state.discountText = text
        applyDiscount()
    }

    func setDiscountIsPercent(_ isPercent: Bool) {
        state.discountIsPercent = isPercent
        applyDiscount()
    }

    private func applyDiscount() {
        if case .success(let discount) = DocumentInput.discount(state.discountText, isPercent: state.discountIsPercent,
                                                                  exponent: exponent) {
            mutate { $0.discount = discount }
        }
    }

    func setShippingText(_ text: String) {
        state.shippingText = text
        if case .success(let minor) = DocumentInput.shipping(text, exponent: exponent) {
            mutate { $0.shippingMinor = minor }
        }
    }

    func setNotesText(_ text: String) {
        state.notesText = text
        mutate { $0.notes = text.trimmedOrNil }
    }

    func setTermsText(_ text: String) {
        state.termsText = text
        mutate { $0.terms = text.trimmedOrNil }
    }

    // MARK: Lines (§3)

    /// Adds a catalogue line; true when its price could not be converted, so the caller closes the picker and the
    /// line editor can ask for the price.
    @discardableResult
    func addItem(_ item: CatalogItem) -> Bool {
        let (line, needsPrice) = rules.line(from: item, for: state.document, id: session.dependencies.ids.make())
        mutate { $0.lines.append(line) }
        state.selectedLineID = line.id
        // "Something new" was prepared before this line existed: give it this line's rate (`documents.md` §3).
        if state.lineEditor?.isNew == true, state.lineEditor?.draft.rateId.isEmpty == true {
            let rateID = rules.oneOffRateID(for: state.document) // read before writing: one access to `state` at a time
            state.lineEditor?.draft.rateId = rateID
        }
        if needsPrice {
            editLine(line.id)
            state.lineEditor?.needsPrice = true
        }
        return needsPrice
    }

    func addLine() {
        guard isDraft else { return }
        var draft = LineItemDraft()
        draft.rateId = rules.oneOffRateID(for: state.document)
        state.lineEditor = LineEditorState(lineID: session.dependencies.ids.make(), isNew: true, draft: draft,
                                           includesTax: state.document.pricesIncludeTax,
                                           saveToItems: !isForeignCurrency)
    }

    func editLine(_ id: String) {
        guard isDraft, let line = state.document.lines.first(where: { $0.id == id }) else { return }
        state.lineEditor = LineEditorState(lineID: id, isNew: false,
                                           draft: LineItemDraft(line: line, exponent: exponent),
                                           includesTax: state.document.pricesIncludeTax)
        state.selectedLineID = id
    }

    /// "Save to my items" is offered for a new line in the home currency (`documents.md` §3.2).
    var canSaveLineToItems: Bool { state.lineEditor?.isNew == true && !isForeignCurrency }

    /// The rate chips, the other rates in force and the hint under the chips.
    var lineRateChoices: (chips: [TaxRate], others: [TaxRate], hint: String?) {
        let choices = session.rateChips.choices(config: config, customRates: session.business.customRates,
                                                on: state.document.effectiveDate)
        guard let selected = state.lineEditor?.draft.rateId, !selected.isEmpty,
              !(choices.chips + choices.others).contains(where: { $0.id == selected }),
              let saved = config.rate(selected, customRates: session.business.customRates) else { return choices }
        return (choices.chips, choices.others + [saved], choices.hint) // a saved rate no longer in force stays
    }

    /// − / + on "How many?": whole steps, never below 1 (a typed 0.5 can still go up).
    func stepLineQuantity(by delta: Int) {
        guard let text = state.lineEditor?.draft.quantityText,
              case .success(let value) = DecimalInput.parse(text), let quantity = DecimalString.parse(value) else {
            state.lineEditor?.draft.quantityText = "1"
            return
        }
        let next = quantity + Decimal(delta)
        guard next >= 1 || delta > 0 else { return }
        state.lineEditor?.draft.quantityText = SpecFormatter.quantity("\(next)")
    }

    /// The price the line gets: as typed when the switch matches the document's basis (or sets it), otherwise
    /// converted (`documents.md` §3.2). Nil while the typed price is not a valid amount.
    private func linePrice(for editor: LineEditorState) -> (minor: Int64, typed: Int64, setsBasis: Bool)? {
        guard case .success(let typed) = MoneyInput.parse(editor.draft.priceText, exponent: exponent) else {
            return nil
        }
        let setsBasis = chargesTax && OneOffLine.setsDocumentBasis(state.document,
                                                                    editing: editor.isNew ? nil : editor.lineID)
        guard !setsBasis else { return (typed, typed, true) }
        let price = OneOffLine.unitPrice(
            typedMinor: typed, includesTax: editor.includesTax,
            rate: config.rate(editor.draft.rateId, customRates: session.business.customRates),
            document: state.document, chargesTax: chargesTax,
            currencies: session.dependencies.reference.currencies, mode: config.rounding.amountMode)
        return (price, typed, false)
    }

    /// The engine's result for this line alone, as the sheet shows it under the fields.
    var lineEditorPreview: LinePreview? {
        guard let editor = state.lineEditor, let price = linePrice(for: editor),
              case .success(let quantity) = DecimalInput.parse(editor.draft.quantityText),
              !chargesTax || !editor.draft.rateId.isEmpty else { return nil }
        var line = LineItem(id: editor.lineID, description: "–", quantity: quantity, unitPriceMinor: price.minor,
                            rateId: editor.draft.rateId)
        if case .success(let discount) = DocumentInput.discount(editor.draft.discountText,
                                                                 isPercent: editor.draft.discountIsPercent,
                                                                 exponent: exponent) {
            line.discount = discount
        }
        var document = state.document
        document.lines = [line]
        document.discount = nil
        document.shippingMinor = 0
        if price.setsBasis { document.pricesIncludeTax = editor.includesTax }
        let seller = rules.sellerSnapshot(config: config)
        guard case .success(let computed) = rules.compute(document, seller: seller,
                                                          buyer: rules.buyerSnapshot(for: document,
                                                                                     client: state.client)),
              let result = computed.lines.first else { return nil }
        let currency = document.currency
        let tax = result.tax
        var text = "\(SpecFormatter.quantity(quantity)) × \(session.money(price.typed, currency: currency))"
        let taxName = config.labels.taxName
        if chargesTax {
            if tax == 0 {
                text += " · no \(taxName)"
            } else if document.pricesIncludeTax || editor.includesTax {
                text += " incl. \(session.money(tax, currency: currency)) \(taxName)"
            } else {
                text += " + \(session.money(tax, currency: currency)) \(taxName)"
            }
        }
        return LinePreview(text: text, total: session.money(result.taxable + tax, currency: currency))
    }

    /// Done in the line editor: applies the line, or shows its problems. True when the editor can close.
    @discardableResult
    func commitLineEditor() -> Bool {
        guard var editor = state.lineEditor else { return true }
        editor.attemptedDone = true
        state.lineEditor = editor
        let rules = lineRules
        guard rules.issues(editor.draft).isEmpty, let price = linePrice(for: editor) else { return false }
        mutate { document in
            if price.setsBasis { document.pricesIncludeTax = editor.includesTax }
            if let index = document.lines.firstIndex(where: { $0.id == editor.lineID }) {
                rules.apply(editor.draft, to: &document.lines[index])
                document.lines[index].unitPriceMinor = price.minor
            } else {
                var line = LineItem(id: editor.lineID, position: document.lines.count)
                rules.apply(editor.draft, to: &line)
                line.unitPriceMinor = price.minor
                document.lines.append(line)
            }
        }
        if editor.isNew, editor.saveToItems, !isForeignCurrency {
            saveToMyItems(lineID: editor.lineID, typedMinor: price.typed, includesTax: editor.includesTax)
        }
        state.selectedLineID = editor.lineID
        state.lineEditor = nil
        return true
    }

    /// Writes the catalogue item, then links the line to it (the line's foreign key needs the item first).
    private func saveToMyItems(lineID: String, typedMinor: Int64, includesTax: Bool) {
        guard let line = state.document.lines.first(where: { $0.id == lineID }) else { return }
        let dependencies = session.dependencies
        let item = OneOffLine.catalogItem(for: line, typedMinor: typedMinor, includesTax: includesTax,
                                          chargesTax: chargesTax, businessID: state.document.businessId,
                                          currency: homeCurrency, id: dependencies.ids.make(),
                                          now: dependencies.time.now())
        let previous = itemSave
        itemSave = Task { [weak self] in
            await previous?.value
            do {
                try await dependencies.catalog.save(item)
                self?.link(lineID: lineID, toItem: item.id)
            } catch {
                self?.state.errorMessage = "The item was added, but it couldn't be saved to your items."
            }
        }
    }

    private func link(lineID: String, toItem itemID: String) {
        mutate { document in
            if let index = document.lines.firstIndex(where: { $0.id == lineID }) {
                document.lines[index].catalogItemId = itemID
            }
        }
    }

    /// Waits until "Save to my items" has written its catalogue items (tests, and before saving).
    func waitForItemSaves() async {
        await itemSave?.value
    }

    func cancelLineEditor() {
        state.lineEditor = nil
    }

    func deleteLines(at offsets: IndexSet) {
        mutate { document in
            for index in offsets.sorted(by: >) where document.lines.indices.contains(index) {
                document.lines.remove(at: index)
            }
            Self.renumber(&document.lines)
        }
        if let selected = state.selectedLineID, !state.document.lines.contains(where: { $0.id == selected }) {
            state.selectedLineID = nil
        }
    }

    func deleteLine(_ id: String) {
        guard let index = state.document.lines.firstIndex(where: { $0.id == id }) else { return }
        deleteLines(at: IndexSet(integer: index))
    }

    func moveLines(from offsets: IndexSet, to destination: Int) {
        mutate { document in
            let moving = offsets.sorted().map { document.lines[$0] }
            for index in offsets.sorted(by: >) { document.lines.remove(at: index) }
            let target = destination - offsets.filter { $0 < destination }.count
            document.lines.insert(contentsOf: moving, at: min(max(target, 0), document.lines.count))
            Self.renumber(&document.lines)
        }
    }

    func duplicateLine(_ id: String) {
        guard let index = state.document.lines.firstIndex(where: { $0.id == id }) else { return }
        var copy = state.document.lines[index]
        copy.id = session.dependencies.ids.make()
        mutate { document in
            document.lines.insert(copy, at: index + 1)
            Self.renumber(&document.lines)
        }
        state.selectedLineID = copy.id
    }

    var canDuplicateSelectedLine: Bool {
        isDraft && state.selectedLineID.map { id in state.document.lines.contains { $0.id == id } } == true
    }

    func duplicateSelectedLine() {
        if let id = state.selectedLineID { duplicateLine(id) }
    }

    private static func renumber(_ lines: inout [LineItem]) {
        for index in lines.indices { lines[index].position = index }
    }

    // MARK: Actions (§6–9)

    /// Issue tapped: shows what blocks issuing, or asks for confirmation with the number it will get.
    func requestIssue() async {
        guard canRequestIssue else { return }
        if state.document.docType == .invoice, !session.entitlement.canIssueInvoice {
            state.showsPaywall = true
            return
        }
        let problems = currentProblems()
        state.issueProblems = problems
        guard problems.isEmpty else { return }
        let dependencies = session.dependencies
        let series = (try? await firstValue(dependencies.numberingSeries.observeSeries(
            businessID: state.document.businessId))) ?? []
        guard let owned = NumberAllocator.series(for: state.document.docType, deviceID: session.deviceID,
                                                 among: series) else {
            state.seriesChoice = seriesChoice(among: series)
            if state.seriesChoice == nil { state.issueProblems = [.noSeries] }
            return
        }
        switch NumberAllocator.allocate(from: owned, issueDate: state.document.issueDate, config: config) {
        case .success(let allocation):
            state.numberPreview = allocation.number
            state.confirmingIssue = true
        case .failure(let error):
            state.issueProblems = [.numbering(error)]
        }
    }

    /// What this device can number from (`spec/sync.md` §3): a new series of its own, or another device's.
    private func seriesChoice(among series: [NumberingSeries]) -> SeriesChoice? {
        let docType = state.document.docType
        let live = series.filter { $0.deletedAt == nil && $0.docType == docType }
        let rules = session.numberingRules
        let own = SeriesOwnership.deviceSeriesPattern(
            defaultPattern: docType == .quote ? config.numbering.quotePattern : config.numbering.invoicePattern,
            docType: docType, existingPatterns: live.map(\.pattern))
        let ownFirst = (try? own.get()).flatMap { value in
            try? rules.preview(pattern: value.pattern, reset: config.numbering.reset, seq: 1).get().number
        }
        let others = live.filter { $0.ownerDeviceId != session.deviceID }.map { other in
            SeriesChoice.Option(series: other, nextNumber: try? rules.nextNumber(other).get().number)
        }
        guard ownFirst != nil || !others.isEmpty else { return nil }
        return SeriesChoice(ownFirstNumber: ownFirst, others: others)
    }

    /// §3.1, then Issue again.
    func startOwnSeries() async {
        state.seriesChoice = nil
        do {
            _ = try await session.dependencies.numbering.createDeviceSeries(
                businessID: state.document.businessId, docType: state.document.docType, deviceID: session.deviceID)
            await requestIssue()
        } catch {
            state.errorMessage = "Numbering couldn't be set up on this device."
        }
    }

    /// §3.2, then Issue again.
    func takeOver(seriesID: String) async {
        state.seriesChoice = nil
        do {
            _ = try await session.dependencies.numbering.takeOver(seriesID: seriesID, deviceID: session.deviceID)
            await requestIssue()
        } catch {
            state.errorMessage = "The series couldn't be taken over."
        }
    }

    func confirmIssue() async {
        state.confirmingIssue = false
        guard canRequestIssue else { return }
        state.isWorking = true
        defer { state.isWorking = false }
        guard await saveBeforeAction() else { return }
        do {
            let issued = try await session.dependencies.documentService.issue(documentID: state.document.id,
                                                                              deviceID: session.deviceID)
            state.document = issued
            state.issueProblems = []
            state.lineEditor = nil
            recompute()
            if issued.docType == .invoice {
                await session.dependencies.entitlements.refreshCount()
                await session.reconcileReminders()
            }
        } catch DocumentServiceError.blocked(let problems) {
            state.issueProblems = problems
        } catch {
            state.errorMessage = "The \(DocumentText.noun(state.document.docType)) couldn't be sent."
        }
    }

    // MARK: Review & send (§6.1, §8)

    /// "Send on WhatsApp" etc.: closes the review; `sendAfterReview()` then issues and opens the channel.
    func send(via channel: SendChannel) {
        state.pendingSend = channel
        state.confirmingIssue = false
    }

    /// "Keep as draft": closes the review and leaves the draft as it is.
    func keepAsDraft() {
        state.pendingSend = nil
        state.confirmingIssue = false
    }

    /// Runs once the review sheet has gone: issues the document, then shows the PDF and opens the channel.
    func sendAfterReview() async {
        guard let channel = state.pendingSend else { return }
        state.pendingSend = nil
        await confirmIssue()
        guard !isDraft, let computed else { return }
        preview = DocumentPreviewViewModel(session: session, document: state.document, computed: computed,
                                           channel: channel) { [weak self] sentAt in
            self?.state.document.sentAt = sentAt
        }
    }

    func duplicate() async {
        guard await saveBeforeAction() else { return }
        do {
            let copy = try await session.dependencies.documentService.duplicate(documentID: state.document.id)
            show(copy)
        } catch {
            state.errorMessage = "The \(DocumentText.noun(state.document.docType)) couldn't be duplicated."
        }
    }

    func convertToInvoice() async {
        do {
            let invoice = try await session.dependencies.documentService.convertQuote(documentID: state.document.id)
            state.document.quoteOutcome = .converted
            show(invoice)
        } catch {
            state.errorMessage = "The quote couldn't be converted."
        }
    }

    // MARK: Void, quote outcome and payments (§10–12)

    var canVoid: Bool { state.document.lifecycle == .issued }
    var canRespondToQuote: Bool {
        state.document.docType == .quote && state.document.lifecycle == .issued
            && state.document.quoteOutcome != .converted
    }
    var canRecordPayment: Bool { state.document.docType == .invoice && state.document.lifecycle == .issued }
    var paidMinor: Int64 { state.payments.reduce(0) { $0 + $1.amountMinor } }

    /// Terminal: turns a live issued document into `void` (`spec/documents.md` §11). `reason` is trimmed by the
    /// service; an empty one is rejected there, not here, so the same message covers both.
    func voidDocument(reason: String) async {
        guard canVoid else { return }
        state.isWorking = true
        defer { state.isWorking = false }
        do {
            state.document = try await session.dependencies.documentService.voidDocument(
                documentID: state.document.id, reason: reason)
            reconcileReminders()
        } catch DocumentServiceError.voidReasonRequired {
            state.errorMessage = "Add a reason before voiding."
        } catch {
            state.errorMessage = "The \(DocumentText.noun(state.document.docType)) couldn't be voided."
        }
    }

    func acceptQuote() async {
        await respondToQuote { try await session.dependencies.documentService.acceptQuote(documentID: $0) }
    }

    func declineQuote() async {
        await respondToQuote { try await session.dependencies.documentService.declineQuote(documentID: $0) }
    }

    private func respondToQuote(_ action: (String) async throws -> Document) async {
        guard canRespondToQuote else { return }
        state.isWorking = true
        defer { state.isWorking = false }
        do {
            state.document = try await action(state.document.id)
        } catch {
            state.errorMessage = "The quote couldn't be updated."
        }
    }

    /// The payment sheet already wrote it (`PaymentEditorViewModel.save()`); this just keeps the list and status
    /// shown here in step, without a round trip back to the database.
    func recordedPayment(_ payment: Payment) {
        state.payments.insert(payment, at: 0)
        state.paymentsRecorded += 1
        reconcileReminders()
    }

    /// Correcting a payment is delete-and-re-add, never an in-place edit (`spec/documents.md` §10).
    func deletePayment(_ payment: Payment) async {
        do {
            try await session.dependencies.payments.softDelete(paymentID: payment.id)
            state.payments.removeAll { $0.id == payment.id }
            reconcileReminders()
        } catch {
            state.errorMessage = "The payment couldn't be removed."
        }
    }

    /// Fire-and-forget: a payment, a void or an issue can change reminder eligibility (`spec/reminders.md` §3).
    private func reconcileReminders() {
        let session = self.session
        Task { await session.reconcileReminders() }
    }

    func deleteDraft() async {
        guard isDraft else { return }
        saveTask?.cancel()
        isDirty = false
        await lastSave?.value
        do {
            if state.isPersisted {
                try await session.dependencies.documentService.deleteDraft(documentID: state.document.id)
            }
            state.isPersisted = false
            state.document.lines = []
            state.document.clientId = nil
            await session.pdfLibrary.forget(documentID: state.document.id)
            session.router.documents.didRemove(state.document.id)
        } catch {
            state.errorMessage = "The draft couldn't be deleted."
        }
    }

    /// Writes everything before an action that reads the stored document (issue, duplicate). False when the save
    /// failed, so the action never works from a stale version of the draft.
    private func saveBeforeAction() async -> Bool {
        guard isDraft else { return true }
        isDirty = isDirty || !state.isPersisted
        await flush()
        guard !isDirty, state.isPersisted else {
            state.errorMessage = "Your latest changes couldn't be saved, so nothing was issued or copied. "
                + "Check the device's storage and try again."
            return false
        }
        return true
    }

    private func show(_ document: Document) {
        let router = session.router.documents
        router.docType = document.docType
        router.open(document.id)
    }

    func dismissError() { state.errorMessage = nil }
}
