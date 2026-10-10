import InvoiceCore
import SwiftUI

/// Onboarding (`spec/setup.md` §3, ADR-0020): the Welcome screen, then three stages. One guided column on iPhone; a
/// stage sidebar beside the form on iPad. The state lives in the view model, so resizing an iPad window mid-way keeps
/// every answer.
public struct OnboardingView: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(model: OnboardingViewModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.state.showsWelcome {
                WelcomeView(model: model)
            } else if sizeClass == .regular {
                NavigationSplitView(columnVisibility: .constant(.all)) {
                    StageSidebar(model: model)
                        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
                } detail: {
                    NavigationStack { stageScreen }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack { stageScreen }
            }
        }
        .animation(.default, value: model.state.showsWelcome)
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.state.errorMessage ?? "")
        }
        .backupFlows(model: model.backup)
        .dropDestination(for: DroppedBackup.self) { files, _ in
            guard let file = files.first else { return false }
            Task { await model.backup.open(file.url) }
            return true
        }
    }

    private var stageScreen: some View {
        StageScreen(model: model, showsProgress: sizeClass != .regular)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.state.errorMessage != nil }, set: { if !$0 { model.state.errorMessage = nil } })
    }
}

/// iPad: the three stages; finished stages are ticked and can be revisited.
private struct StageSidebar: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        List {
            ForEach(OnboardingStage.allCases, id: \.self) { stage in
                Button {
                    model.go(to: stage)
                } label: {
                    HStack {
                        Label(model.title(for: stage), systemImage: stage.symbol)
                            .foregroundStyle(model.canVisit(stage) ? Theme.textPrimary : Theme.textSecondary)
                        Spacer()
                        if stage < model.state.stage {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.brand)
                                .accessibilityLabel("Done")
                        }
                    }
                }
                .disabled(!model.canVisit(stage))
                .listRowBackground(stage == model.state.stage ? Theme.brandTint : Theme.surface)
                .accessibilityAddTraits(stage == model.state.stage ? .isSelected : [])
            }
        }
        .themedList()
        .navigationTitle("Set up")
    }
}

/// The current stage with Back, "Step n of 3", and Continue (Finish and Skip for now on the last stage).
private struct StageScreen: View {
    @Bindable var model: OnboardingViewModel
    let showsProgress: Bool

    var body: some View {
        content
            .background(Theme.background)
            .navigationTitle(model.title(for: model.state.stage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Back", systemImage: "chevron.backward") { model.back() }
                        .accessibilityIdentifier("onboarding.back")
                }
                ToolbarItem(placement: .principal) {
                    Text("Step \(model.stageNumber) of \(model.stageCount)")
                        .font(Theme.Fonts.subhead.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
    }

    @ViewBuilder private var content: some View {
        switch model.state.stage {
        case .whereYouWork:
            WhereYouWorkStage(model: model, showsProgress: showsProgress)
        case .yourBusiness:
            ThemedForm {
                StageHeader(model: model, showsProgress: showsProgress, title: "Tell us about your business",
                            subtitle: "This is what your clients see at the top of every invoice.")
                if let rules = model.rules {
                    BusinessDetailsSections(draft: $model.state.draft, rules: rules, issue: model.visibleIssue,
                                            taxIDFeedback: model.taxIDFeedback)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .readableWidth()
        case .gettingPaid:
            ThemedForm {
                StageHeader(model: model, showsProgress: showsProgress, title: "How do clients pay you?",
                            subtitle: "Printed on your invoices so clients know where to pay. All optional.")
                if let rules = model.rules {
                    BankSections(draft: $model.state.draft, rules: rules, issue: model.visibleIssue)
                }
                ImagesFormSections(
                    logo: model.state.logo?.data, signature: model.state.signature?.data,
                    isBusy: model.state.isProcessingImage,
                    signatureNote: model.rules?.isIndia == true
                        ? "Tax invoices need the signature of the supplier or an authorised person (GST Rule 46)." : nil,
                    onPickLogo: { await model.setLogo(imageData: $0) },
                    onRemoveLogo: { model.removeLogo() },
                    onSaveSignature: { model.setSignature($0) },
                    onRemoveSignature: { model.setSignature(nil) }
                )
            }
            .scrollDismissesKeyboard(.interactively)
            .readableWidth()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Theme.Space.xs) {
            if model.isLastStage {
                PrimaryButton(title: "Finish", isBusy: model.state.isFinishing) {
                    Task { await model.finish() }
                }
                .accessibilityIdentifier("onboarding.finish")
                Button("Skip for now") { Task { await model.skipAndFinish() } }
                    .buttonStyle(.textLink)
                    .disabled(model.state.isFinishing)
                    .accessibilityIdentifier("onboarding.skip")
            } else {
                PrimaryButton(title: "Continue") { model.continueTapped() }
                    .accessibilityIdentifier("onboarding.continue")
                if model.state.stage == .whereYouWork {
                    Text("Bank details and logo are optional. Skip them for now if you like.")
                        .font(Theme.Fonts.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Theme.Space.xs)
                }
            }
        }
        .padding(.horizontal, Theme.Layout.screenGutter)
        .padding(.top, Theme.Space.m)
        .padding(.bottom, Theme.Space.s)
        .frame(maxWidth: Theme.Layout.maxReadableWidth)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bottomBar")
    }
}

/// The stepped progress (iPhone) and the stage's question, as the first row of a form.
private struct StageHeader: View {
    let model: OnboardingViewModel
    let showsProgress: Bool
    let title: String
    let subtitle: String

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if showsProgress {
                    SteppedProgress(stages: OnboardingStage.allCases.map(model.title(for:)),
                                    current: model.state.stage.rawValue)
                }
                ScreenHeader(title: title, subtitle: subtitle)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Theme.Space.s, leading: 4, bottom: Theme.Space.s, trailing: 4))
        }
    }
}

// MARK: - Stage 1: where you work

/// Country as three cards; the registration question appears below once a country is chosen.
private struct WhereYouWorkStage: View {
    @Bindable var model: OnboardingViewModel
    let showsProgress: Bool
    @State private var showsCountries = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l + 2) {
                if showsProgress {
                    SteppedProgress(stages: OnboardingStage.allCases.map(model.title(for:)), current: 0)
                }
                ScreenHeader(title: "Where is your business based?",
                             subtitle: "This decides which tax goes on your invoices, so you never have to work it out yourself.")
                VStack(spacing: Theme.Space.s + 2) {
                    SelectableCard(title: "India", hint: "GST invoices in ₹", badge: "IN",
                                   isSelected: model.countryCard == "IN") { model.selectCountry("IN") }
                        .accessibilityIdentifier("country-IN")
                    SelectableCard(title: "United Kingdom", hint: "VAT invoices in £", badge: "UK",
                                   isSelected: model.countryCard == "GB") { model.selectCountry("GB") }
                        .accessibilityIdentifier("country-GB")
                    SelectableCard(title: "Somewhere else", hint: "Choose your country and currency",
                                   systemImage: "plus", isSelected: model.countryCard == "other") {
                        model.pickOtherCountry()
                    }
                    .accessibilityIdentifier("country-other")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Country")
                if let issue = model.visibleIssue(.country) {
                    IssueText(message: IssueMessages.text(issue, field: "country"))
                }
                if model.countryCard == "other" { otherCountry }
                if let rules = model.rules { RegistrationCard(model: model, rules: rules) }
            }
            .padding(.horizontal, Theme.Layout.screenGutter)
            .padding(.vertical, Theme.Space.l)
            .readableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showsCountries) {
            CountryPickerSheet(model: model)
        }
    }

    private var otherCountry: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Button {
                    showsCountries = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Country").font(Theme.Fonts.footnote).foregroundStyle(Theme.textSecondary)
                            Text(model.countryName ?? "Choose").font(Theme.Fonts.rowTitle)
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.chooseCountry")
                if model.rules?.asksForHomeCurrency == true {
                    Divider().overlay(Theme.surfaceMuted)
                    Picker(selection: $model.state.draft.homeCurrency) {
                        Text("Choose").tag(CurrencyCode?.none)
                        ForEach(model.currencies) { currency in
                            Text("\(currency.name) (\(currency.code.rawValue))").tag(Optional(currency.code))
                        }
                    } label: {
                        Text("Currency").font(Theme.Fonts.rowTitle)
                    }
                    .pickerStyle(.menu)
                    if let issue = model.visibleIssue(.homeCurrency) {
                        IssueText(message: IssueMessages.text(issue, field: "home currency"))
                    }
                    Text("Your invoices total in this currency. You can still bill clients in other currencies.")
                        .font(Theme.Fonts.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

/// "Are you registered for GST?" as chips, India's turnover band, or (elsewhere) the first tax rate.
private struct RegistrationCard: View {
    @Bindable var model: OnboardingViewModel
    let rules: BusinessRules

    private var taxName: String { rules.config.labels.taxName }
    private var formatter: SpecFormatter { SpecFormatter(currencies: model.dependencies.reference.currencies) }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Are you registered for \(taxName)?")
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                FlowLayout {
                    ForEach(rules.config.registrations) { registration in
                        ChoiceChip(title: Self.chipLabel(family: rules.config.family, registration: registration),
                                   isSelected: model.state.draft.taxRegistration == registration.id) {
                            model.state.draft.taxRegistration = registration.id
                        }
                        .accessibilityIdentifier("registration.\(registration.id)")
                    }
                }
                if let selected = model.state.draft.taxRegistration {
                    Text(RegistrationSections.help(family: rules.config.family, registration: selected))
                        .font(Theme.Fonts.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let issue = model.visibleIssue(.registration) {
                    IssueText(message: IssueMessages.text(issue, field: "registration type"))
                }
                if rules.showsTurnoverTier(model.state.draft) { turnover }
                if rules.asksForFirstTaxRate(model.state.draft) { firstRate }
                TipCallout("Not sure? Pick “Not registered”. You can change it later in Settings.")
            }
        }
    }

    private var turnover: some View {
        let text = TurnoverText(rules: rules, formatter: formatter)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Turnover in the last financial year")
                .font(Theme.Fonts.subhead.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, Theme.Space.xs)
            FlowLayout {
                ForEach(rules.turnoverTiers.indices, id: \.self) { index in
                    ChoiceChip(title: text.label(index), isSelected: model.state.draft.turnoverTier == index) {
                        model.state.draft.turnoverTier = index
                    }
                }
            }
            Text(text.footer(tier: model.state.draft.turnoverTier))
                .font(Theme.Fonts.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var firstRate: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            BoxedTextField(title: "Tax name", text: $model.state.draft.genericTaxName, prompt: "Sales tax",
                           issue: message(.genericTaxName, "tax name"), capitalization: .words)
            BoxedTextField(title: "Rate (%)", text: $model.state.draft.genericTaxPercent, prompt: "8.875",
                           issue: message(.genericTaxPercent, "rate"), keyboard: .decimalPad)
            Text("You can add more rates, or a second tax, later in Settings.")
                .font(Theme.Fonts.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, Theme.Space.xs)
    }

    private func message(_ field: BusinessField, _ name: String) -> String? {
        model.visibleIssue(field).map { IssueMessages.text($0, field: name) }
    }

    /// Everyday answers to "Are you registered?" (`design.md` §6.2); other configs use their own labels.
    static func chipLabel(family: String, registration: TaxRegistration) -> String {
        switch "\(family).\(registration.id)" {
        case "IN.regular": "Yes, regular GST"
        case "IN.composition": "Yes, composition"
        case "IN.unregistered", "GB.notRegistered", "GENERIC.notRegistered": "Not registered"
        case "GB.vatRegistered": "Yes, VAT registered"
        case "GENERIC.registered": "Yes"
        default: registration.label
        }
    }
}

/// "Somewhere else": every country, searchable.
private struct CountryPickerSheet: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.countries) { country in
                Button {
                    model.selectCountry(country.code)
                    dismiss()
                } label: {
                    HStack {
                        Text(country.name).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if model.state.draft.countryCode == country.code {
                            Image(systemName: "checkmark").foregroundStyle(Theme.brand).fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(Theme.surface)
                .accessibilityAddTraits(model.state.draft.countryCode == country.code ? .isSelected : [])
            }
            .themedList()
            .searchable(text: $model.state.countrySearch, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search countries")
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

extension OnboardingStage {
    var symbol: String {
        switch self {
        case .whereYouWork: "globe"
        case .yourBusiness: "briefcase"
        case .gettingPaid: "banknote"
        }
    }
}
