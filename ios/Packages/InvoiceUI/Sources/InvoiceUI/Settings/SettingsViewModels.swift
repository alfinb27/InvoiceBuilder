import Foundation
import InvoiceCore
import Observation

/// Settings → Business profile and Defaults: the onboarding fields plus invoice defaults (`spec/setup.md` §4).
@MainActor @Observable
final class BusinessProfileViewModel {
    struct State: Equatable {
        var draft: BusinessDraft
        var attemptedSave = false
        var isSaving = false
        var didSave = false
        var errorMessage: String?
    }

    var state: State {
        didSet {
            var draft = state.draft
            rules.applyDerivations(to: &draft)
            if draft != state.draft { state.draft = draft }
        }
    }

    private let session: Session

    init(session: Session) {
        self.session = session
        state = State(draft: BusinessDraft(business: session.business, rules: session.businessRules))
    }

    var rules: BusinessRules { session.businessRules }
    var business: Business { session.business }
    var issues: [BusinessField: FieldIssue] { rules.issues(state.draft) }

    func visibleIssue(_ field: BusinessField) -> FieldIssue? {
        state.attemptedSave ? issues[field] : nil
    }

    var taxIDFeedback: TaxIDFeedback? {
        guard let validation = rules.taxIDValidation(state.draft) else { return nil }
        if validation.valid { return .valid(validation.region.flatMap { rules.config.region($0)?.name }) }
        guard state.attemptedSave || validation.normalized.count >= 15, let error = validation.error else { return nil }
        let name = rules.config.labels.taxIdName
        return .invalid(IssueMessages.text(.invalidTaxID(error), field: name, taxIDName: name))
    }

    var hasChanges: Bool { rules.updating(business, from: state.draft) != business }

    func save() async {
        state.attemptedSave = true
        state.didSave = false
        guard issues.isEmpty else { return }
        state.isSaving = true
        defer { state.isSaving = false }
        do {
            try await session.dependencies.businesses.save(rules.updating(business, from: state.draft))
            state.attemptedSave = false
            state.didSave = true
            await session.reconcileReminders() // the default may have changed (`spec/reminders.md` §3)
        } catch {
            state.errorMessage = "Your changes couldn't be saved."
        }
    }

    func discardChanges() {
        state = State(draft: BusinessDraft(business: business, rules: rules))
    }
}

/// Settings → Logo and signature: saved immediately (`spec/setup.md` §9).
@MainActor @Observable
final class BusinessImagesViewModel {
    struct State: Equatable {
        var logo: Data?
        var signature: Data?
        var isBusy = false
        var errorMessage: String?
    }

    private(set) var state = State()
    private let session: Session

    init(session: Session) {
        self.session = session
    }

    func load() async {
        state.logo = await data(for: session.business.logoAssetId)
        state.signature = await data(for: session.business.signatureAssetId)
    }

    private func data(for assetID: String?) async -> Data? {
        guard let assetID else { return nil }
        return try? await session.dependencies.assets.fetchAsset(id: assetID)?.data
    }

    func setLogo(imageData: Data) async {
        await update(kind: .logo) { try await ImageProcessing.logo(from: imageData) }
    }

    func setSignature(_ payload: ImagePayload?) async {
        await update(kind: .signature) { payload }
    }

    func removeLogo() async {
        await update(kind: .logo) { nil }
    }

    private func update(kind: AssetKind, _ makePayload: () async throws -> ImagePayload?) async {
        state.isBusy = true
        defer { state.isBusy = false }
        do {
            let payload = try await makePayload()
            _ = try await session.dependencies.setup.setImage(payload, kind: kind, businessID: session.business.id)
            if kind == .logo { state.logo = payload?.data } else { state.signature = payload?.data }
        } catch {
            state.errorMessage = "The image couldn't be saved. Try a PNG or JPEG."
        }
    }

    func dismissError() { state.errorMessage = nil }
}

/// Settings → Invoice numbering (`spec/setup.md` §6).
@MainActor @Observable
final class NumberingSettingsViewModel {
    struct State: Equatable {
        var series: [NumberingSeries] = []
        var editing: NumberingSeries?
        var draft: NumberingSeriesDraft?
        /// Period key → the highest sequence already issued from the series being edited.
        var highestIssued: [String: Int] = [:]
        var attemptedSave = false
        var errorMessage: String?
    }

    var state = State()
    private let session: Session

    init(session: Session) {
        self.session = session
    }

    var rules: NumberingSeriesRules { session.numberingRules }

    func observe() async {
        do {
            for try await series in session.dependencies.numberingSeries.observeSeries(businessID: session.business.id) {
                state.series = series
            }
        } catch {
            state.errorMessage = "Your numbering couldn't be loaded."
        }
    }

    func nextNumber(_ series: NumberingSeries) -> String {
        (try? rules.nextNumber(series).get().number) ?? "—"
    }

    func edit(_ series: NumberingSeries) {
        guard rules.isEditable(series) else { return }
        state.editing = series
        state.draft = NumberingSeriesDraft(series: series, periodKey: rules.periodKey(reset: series.reset))
        state.highestIssued = [:]
        state.attemptedSave = false
        Task { await loadHighestIssued(series) }
    }

    /// The highest numbers already issued in today's period for each reset choice (`spec/setup.md` §6).
    private func loadHighestIssued(_ series: NumberingSeries) async {
        var highest: [String: Int] = [:]
        for reset in NumberingReset.known {
            let key = rules.periodKey(reset: reset)
            if let value = try? await session.dependencies.documents.highestIssuedSequence(seriesID: series.id,
                                                                                          periodKey: key) {
                highest[key] = value
            }
        }
        if state.editing?.id == series.id { state.highestIssued = highest }
    }

    func cancelEditing() {
        state.editing = nil
        state.draft = nil
    }

    var draftIssues: [NumberingSeriesField: FieldIssue] {
        guard let draft = state.draft else { return [:] }
        return rules.issues(draft, highestIssued: state.highestIssued[rules.periodKey(reset: draft.reset)])
    }

    /// Issues are shown as soon as the pattern changes, so the preview and its problem appear together.
    func visibleIssue(_ field: NumberingSeriesField) -> FieldIssue? {
        guard let issue = draftIssues[field] else { return nil }
        return state.attemptedSave || field == .pattern ? issue : nil
    }

    var preview: String? {
        guard let draft = state.draft, case .success(let result)? = rules.preview(draft) else { return nil }
        return result.number
    }

    func saveEditing() async -> Bool {
        state.attemptedSave = true
        guard let series = state.editing, let draft = state.draft, draftIssues.isEmpty else { return false }
        do {
            try await session.dependencies.numberingSeries.save(rules.updating(series, from: draft))
            cancelEditing()
            return true
        } catch {
            state.errorMessage = "The numbering couldn't be saved."
            return false
        }
    }
}

/// Settings → Tax rates, for GENERIC businesses (`spec/setup.md` §7).
@MainActor @Observable
final class TaxRatesViewModel {
    struct State: Equatable {
        /// The rate being edited (nil id = a new rate).
        var editingID: String?
        var draft: CustomRateDraft?
        var attemptedSave = false
        var errorMessage: String?
    }

    var state = State()
    private let session: Session

    init(session: Session) {
        self.session = session
    }

    var rates: [TaxRate] { session.business.customRates ?? [] }

    func startNew() {
        state.editingID = nil
        state.draft = CustomRateDraft(name: rates.first?.components?.first?.label ?? "Tax")
        state.attemptedSave = false
    }

    func edit(_ rate: TaxRate) {
        state.editingID = rate.id
        state.draft = CustomRateDraft(rate: rate)
        state.attemptedSave = false
    }

    func cancelEditing() {
        state.draft = nil
        state.editingID = nil
    }

    var draftIssues: [CustomRateField: FieldIssue] { state.draft?.issues ?? [:] }

    func visibleIssue(_ field: CustomRateField) -> FieldIssue? {
        state.attemptedSave ? draftIssues[field] : nil
    }

    func saveEditing() async -> Bool {
        state.attemptedSave = true
        guard let draft = state.draft, draftIssues.isEmpty else { return false }
        let dependencies = session.dependencies
        let id = state.editingID ?? CustomRates.rateID(fromUUID: dependencies.ids.make(), existing: rates)
        var updatedRates = rates
        var rate = draft.makeRate(id: id, today: dependencies.time.today())
        if let index = updatedRates.firstIndex(where: { $0.id == id }) {
            rate.effectiveFrom = updatedRates[index].effectiveFrom
            updatedRates[index] = rate
        } else {
            updatedRates.insert(rate, at: max(0, updatedRates.count - (updatedRates.last?.id == CustomRates.noTax.id ? 1 : 0)))
        }
        return await store(updatedRates)
    }

    /// A rate used by a live catalogue item cannot be removed.
    func remove(_ rate: TaxRate) async {
        do {
            let users = try await session.dependencies.catalog.countItems(businessID: session.business.id,
                                                                         usingRate: rate.id)
            guard users == 0 else {
                state.errorMessage = "\(users) item\(users == 1 ? " uses" : "s use") this rate. Change \(users == 1 ? "it" : "them") first."
                return
            }
            _ = await store(rates.filter { $0.id != rate.id })
        } catch {
            state.errorMessage = "The rate couldn't be removed."
        }
    }

    private func store(_ rates: [TaxRate]) async -> Bool {
        var business = session.business
        business.customRates = rates
        do {
            try await session.dependencies.businesses.save(business)
            cancelEditing()
            return true
        } catch {
            state.errorMessage = "The rates couldn't be saved."
            return false
        }
    }
}
