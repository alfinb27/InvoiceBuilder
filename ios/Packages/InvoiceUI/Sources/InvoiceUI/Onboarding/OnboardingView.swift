import InvoiceCore
import SwiftUI

/// Onboarding: one guided column on iPhone; a step sidebar beside the form on iPad (wireframe 1). The state lives
/// in the view model, so resizing an iPad window mid-way keeps every answer.
public struct OnboardingView: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(model: OnboardingViewModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView(columnVisibility: .constant(.all)) {
                    StepSidebar(model: model)
                        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
                } detail: {
                    NavigationStack { stepScreen }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack { stepScreen }
            }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.state.errorMessage ?? "")
        }
    }

    private var stepScreen: some View {
        OnboardingStepScreen(model: model, showsProgress: sizeClass != .regular)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.state.errorMessage != nil }, set: { if !$0 { model.state.errorMessage = nil } })
    }
}

/// iPad: the five steps; finished steps are ticked and can be revisited.
private struct StepSidebar: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        List {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Button {
                    model.go(to: step)
                } label: {
                    HStack {
                        Label(model.title(for: step), systemImage: step.symbol)
                            .foregroundStyle(model.canVisit(step) ? Theme.textPrimary : Theme.textTertiary)
                        Spacer()
                        if step < model.state.step {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                                .accessibilityLabel("Done")
                        }
                    }
                }
                .disabled(!model.canVisit(step))
                .listRowBackground(step == model.state.step ? Theme.brand.opacity(0.12) : nil)
                .accessibilityAddTraits(step == model.state.step ? .isSelected : [])
            }
        }
        .navigationTitle("Set up")
    }
}

/// The current step's form with Back / Continue (Finish on the last step).
private struct OnboardingStepScreen: View {
    @Bindable var model: OnboardingViewModel
    let showsProgress: Bool

    var body: some View {
        Form {
            if showsProgress {
                Section {
                    ProgressView(value: Double(model.stepNumber), total: Double(model.stepCount)) {
                        Text("Step \(model.stepNumber) of \(model.stepCount)")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityValue("Step \(model.stepNumber) of \(model.stepCount)")
                }
                .listRowBackground(Color.clear)
            }
            stepContent
        }
        .scrollDismissesKeyboard(.interactively)
        .formStyle(.grouped)
        .frame(maxWidth: Theme.Layout.maxReadableWidth)
        .frame(maxWidth: .infinity)
        .navigationTitle(model.title(for: model.state.step))
        .toolbar {
            if model.state.step != .country {
                ToolbarItem(placement: .navigation) {
                    Button("Back", systemImage: "chevron.backward") { model.back() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.s) {
                if model.isLastStep {
                    PrimaryButton(title: "Finish", isBusy: model.state.isFinishing) {
                        Task { await model.finish() }
                    }
                    Text("You can change all of this later in Settings.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    PrimaryButton(title: "Continue") { model.continueTapped() }
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: Theme.Layout.maxReadableWidth)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch model.state.step {
        case .country:
            CountryStep(model: model)
        case .registration:
            if let rules = model.rules {
                RegistrationSections(draft: $model.state.draft, rules: rules,
                                     formatter: SpecFormatter(currencies: model.dependencies.reference.currencies),
                                     issue: model.visibleIssue)
            }
        case .business:
            if let rules = model.rules {
                BusinessDetailsSections(draft: $model.state.draft, rules: rules, issue: model.visibleIssue,
                                        taxIDFeedback: model.taxIDFeedback)
            }
        case .bank:
            if let rules = model.rules {
                BankSections(draft: $model.state.draft, rules: rules, issue: model.visibleIssue)
            }
        case .images:
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
    }
}

/// Step 1: where the business is registered. India and the UK first; every other country uses the generic rules
/// with a home currency the user picks.
private struct CountryStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        if let issue = model.visibleIssue(.country) {
            Section { IssueText(message: IssueMessages.text(issue, field: "country")) }
        }
        if model.rules?.asksForHomeCurrency == true {
            Section {
                Picker("Home currency", selection: $model.state.draft.homeCurrency) {
                    Text("Choose").tag(CurrencyCode?.none)
                    ForEach(model.currencies) { currency in
                        Text("\(currency.name) (\(currency.code.rawValue))").tag(Optional(currency.code))
                    }
                }
                .pickerStyle(.navigationLink)
                if let issue = model.visibleIssue(.homeCurrency) {
                    IssueText(message: IssueMessages.text(issue, field: "home currency"))
                }
            } footer: {
                Text("Your invoices total in this currency. You can still bill clients in other currencies.")
            }
        }
        Section("Suggested") {
            ForEach(model.suggestedCountries) { country in
                CountryRow(country: country, isSelected: model.state.draft.countryCode == country.code) {
                    model.selectCountry(country.code)
                }
            }
        }
        Section {
            TextField("Search countries", text: $model.state.countrySearch)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            ForEach(model.countries) { country in
                CountryRow(country: country, isSelected: model.state.draft.countryCode == country.code) {
                    model.selectCountry(country.code)
                }
            }
        } header: {
            Text("All countries")
        } footer: {
            Text("India and the UK get their GST and VAT rules built in. Elsewhere you set your own tax rates.")
        }
    }
}

private struct CountryRow: View {
    let country: Country
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                Text(country.name).foregroundStyle(Theme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Theme.brand).fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension OnboardingStep {
    var title: String {
        switch self {
        case .country: "Country"
        case .registration: "Tax registration"
        case .business: "Your business"
        case .bank: "Bank and UPI"
        case .images: "Logo and signature"
        }
    }

    var symbol: String {
        switch self {
        case .country: "globe"
        case .registration: "building.columns"
        case .business: "briefcase"
        case .bank: "banknote"
        case .images: "signature"
        }
    }
}
