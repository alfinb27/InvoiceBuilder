import Foundation
import InvoiceCore
import Observation

/// Onboarding (`spec/setup.md` §3): five steps over one `BusinessDraft`. Nothing is written until Finish, which
/// creates the business, its images, its numbering series and the active-business preference in one transaction.
@MainActor @Observable
public final class OnboardingViewModel {
    public struct State: Equatable {
        public var step: OnboardingStep = .country
        public var draft = BusinessDraft()
        /// Steps where Continue was pressed: their missing-field problems are now shown.
        public var attempted: Set<OnboardingStep> = []
        public var countrySearch = ""
        public var logo: ImagePayload?
        public var signature: ImagePayload?
        public var isProcessingImage = false
        public var isFinishing = false
        public var errorMessage: String?
    }

    public var state = State() {
        didSet { applyDerivations(previous: oldValue) }
    }

    let dependencies: AppDependencies
    let deviceID: String
    private let onFinished: @MainActor (Business) -> Void
    /// "Restore from a backup" instead of setting up (`spec/backup.md` §4): a new device can start from a file.
    let backup: BackupViewModel

    public init(dependencies: AppDependencies, deviceID: String,
                onRestored: @escaping @MainActor () async -> Void = {},
                onFinished: @escaping @MainActor (Business) -> Void) {
        self.dependencies = dependencies
        self.deviceID = deviceID
        self.onFinished = onFinished
        backup = BackupViewModel(dependencies: dependencies, deviceID: deviceID, onRestored: onRestored)
    }

    // MARK: Config for the chosen country

    /// IN → `IN.json`, GB → `GB.json`, anything else → `GENERIC.json`.
    public var config: TaxConfig? {
        state.draft.countryCode.flatMap {
            dependencies.taxConfigs.latest(family: TaxConfigStore.family(forCountry: $0), on: dependencies.time.today())
        }
    }

    public var rules: BusinessRules? { config.map(BusinessRules.init) }

    private func applyDerivations(previous: State) {
        guard let rules else { return }
        var draft = state.draft
        if draft.countryCode != previous.draft.countryCode {
            // A new country means a new config: start its registration and currency afresh.
            draft.taxRegistration = rules.config.registrations.first?.id
            draft.homeCurrency = rules.config.currency
            draft.regionCode = nil
            draft.turnoverTier = 0
        }
        rules.applyDerivations(to: &draft)
        if draft != state.draft { state.draft = draft }
    }

    // MARK: Steps

    public var stepNumber: Int { state.step.rawValue + 1 }

    /// Step titles; the bank step mentions UPI only in India.
    public func title(for step: OnboardingStep) -> String {
        step == .bank && rules?.isIndia != true ? "Bank details" : step.title
    }
    public var stepCount: Int { OnboardingStep.allCases.count }
    public var isLastStep: Bool { state.step == OnboardingStep.allCases.last }

    public func issues(for step: OnboardingStep) -> [BusinessField: FieldIssue] {
        guard let rules else { return step == .country ? [.country: .required] : [:] }
        return rules.issues(state.draft, steps: [step])
    }

    /// The problem to show under a field: every problem once Continue was pressed on its step, none before.
    public func visibleIssue(_ field: BusinessField) -> FieldIssue? {
        guard let step = field.step, state.attempted.contains(step) else { return nil }
        return issues(for: step)[field]
    }

    /// Live GSTIN / VAT number feedback, shown while typing: valid (with the state it names), or a problem once the
    /// text is long enough to be a complete ID.
    public var taxIDFeedback: TaxIDFeedback? {
        guard let rules, let validation = rules.taxIDValidation(state.draft) else { return nil }
        if validation.valid {
            return .valid(validation.region.flatMap { rules.config.region($0)?.name })
        }
        guard state.attempted.contains(.business) || validation.normalized.count >= 15,
              let error = validation.error else { return nil }
        return .invalid(IssueMessages.text(.invalidTaxID(error), field: "", taxIDName: rules.config.labels.taxIdName))
    }

    /// A step can be opened from the sidebar once every step before it is complete.
    public func canVisit(_ step: OnboardingStep) -> Bool {
        OnboardingStep.allCases.filter { $0 < step }.allSatisfy { issues(for: $0).isEmpty }
    }

    public func go(to step: OnboardingStep) {
        if canVisit(step) { state.step = step }
    }

    public func continueTapped() {
        state.attempted.insert(state.step)
        guard issues(for: state.step).isEmpty,
              let next = OnboardingStep(rawValue: state.step.rawValue + 1) else { return }
        state.step = next
    }

    public func back() {
        if let previous = OnboardingStep(rawValue: state.step.rawValue - 1) { state.step = previous }
    }

    // MARK: Country step

    public func selectCountry(_ code: String) {
        state.draft.countryCode = code
    }

    /// India and the UK first, then every country, filtered by the search text.
    public var suggestedCountries: [Country] {
        ["IN", "GB"].compactMap(dependencies.reference.country(code:))
    }

    public var countries: [Country] {
        let query = state.countrySearch.trimmingCharacters(in: .whitespaces)
        let all = dependencies.reference.countriesByName
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.code.caseInsensitiveCompare(query) == .orderedSame }
    }

    public var currencies: [Currency] {
        dependencies.reference.currencies.all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Images

    public func setLogo(imageData: Data) async {
        state.isProcessingImage = true
        defer { state.isProcessingImage = false }
        do {
            state.logo = try await ImageProcessing.logo(from: imageData)
        } catch {
            state.errorMessage = "That image couldn't be used. Try a PNG or JPEG."
        }
    }

    public func removeLogo() { state.logo = nil }

    public func setSignature(_ signature: ImagePayload?) { state.signature = signature }

    // MARK: Finish

    public func finish() async {
        guard let rules else { return }
        for step in OnboardingStep.allCases where !issues(for: step).isEmpty {
            state.attempted.insert(step)
            state.step = step
            return
        }
        state.isFinishing = true
        state.errorMessage = nil
        defer { state.isFinishing = false }
        let now = dependencies.time.now()
        let business = rules.makeBusiness(from: state.draft, id: dependencies.ids.make(), now: now,
                                          today: dependencies.time.today(), newID: dependencies.ids.make)
        let series = BusinessSetup.defaultSeries(businessID: business.id, config: rules.config,
                                                 ownerDeviceID: deviceID, now: now, newID: dependencies.ids.make)
        do {
            let created = try await dependencies.setup.createBusiness(
                business, series: series, logo: state.logo, signature: state.signature, deviceID: deviceID)
            onFinished(created)
        } catch {
            state.errorMessage = "Your business couldn't be saved. Please try again."
        }
    }
}

/// Live feedback for a typed tax ID.
public enum TaxIDFeedback: Equatable, Sendable {
    /// Valid; for a GSTIN, the name of the state it belongs to.
    case valid(String?)
    case invalid(String)
}
