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
        var confirmingIssue = false
        var numberPreview: String?
        var isWorking = false
        var errorMessage: String?
        var lineEditor: LineEditorState?
        /// The line last added or edited (⌘D duplicates it).
        var selectedLineID: String?
    }

    struct LineEditorState: Equatable, Identifiable {
        let lineID: String
        let isNew: Bool
        var draft: LineItemDraft
        var attemptedDone = false
        /// The catalogue price could not be converted to the document currency.
        var needsPrice = false

        var id: String { lineID }
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
        } catch {
            state.errorMessage = "This document couldn't be opened."
        }
        resetTexts()
        recompute()
        state.isLoaded = true
    }

    /// Saves now if anything changed (before issuing, leaving the screen or going to the background).
    func flush() async {
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
        state.lineEditor = LineEditorState(lineID: session.dependencies.ids.make(), isNew: true, draft: draft)
    }

    func editLine(_ id: String) {
        guard isDraft, let line = state.document.lines.first(where: { $0.id == id }) else { return }
        state.lineEditor = LineEditorState(lineID: id, isNew: false,
                                           draft: LineItemDraft(line: line, exponent: exponent))
        state.selectedLineID = id
    }

    /// Done in the line editor: applies the line, or shows its problems. True when the editor can close.
    @discardableResult
    func commitLineEditor() -> Bool {
        guard var editor = state.lineEditor else { return true }
        editor.attemptedDone = true
        state.lineEditor = editor
        let rules = lineRules
        guard rules.issues(editor.draft).isEmpty else { return false }
        mutate { document in
            if let index = document.lines.firstIndex(where: { $0.id == editor.lineID }) {
                rules.apply(editor.draft, to: &document.lines[index])
            } else {
                var line = LineItem(id: editor.lineID, position: document.lines.count)
                rules.apply(editor.draft, to: &line)
                document.lines.append(line)
            }
        }
        state.selectedLineID = editor.lineID
        state.lineEditor = nil
        return true
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

    // MARK: Actions (§6–8)

    /// Issue tapped: shows what blocks issuing, or asks for confirmation with the number it will get.
    func requestIssue() async {
        guard canRequestIssue else { return }
        let problems = currentProblems()
        state.issueProblems = problems
        guard problems.isEmpty else { return }
        let dependencies = session.dependencies
        let series = (try? await firstValue(dependencies.numberingSeries.observeSeries(
            businessID: state.document.businessId))) ?? []
        guard let owned = NumberAllocator.series(for: state.document.docType, deviceID: session.deviceID,
                                                 among: series) else {
            state.issueProblems = [.noSeries]
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
        } catch DocumentServiceError.blocked(let problems) {
            state.issueProblems = problems
        } catch {
            state.errorMessage = "The \(DocumentText.noun(state.document.docType)) couldn't be issued."
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
