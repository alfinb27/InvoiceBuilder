import InvoiceCore
import SwiftUI

/// The Settings tab: a list of pages beside the selected page on iPad, a stack on iPhone.
struct SettingsSection: View {
    let session: Session
    @State private var backupDue = false

    var body: some View {
        @Bindable var router = session.router.settings
        NavigationSplitView {
            List(pages, id: \.self, selection: $router.selection) { page in
                NavigationLink(value: page) {
                    Label(page.title, systemImage: page.symbol)
                        .badge(page == .backup && backupDue ? Text("Due") : nil)
                }
            }
            .navigationTitle("Settings")
        } detail: {
            if let page = router.selection {
                SettingsPageView(session: session, page: page)
                    .id(page)
            } else {
                ContentUnavailableView("Settings", systemImage: "gearshape",
                                       description: Text("Choose what to change."))
            }
        }
        // iPad: drop a backup file onto Settings to restore it (`spec/backup.md` §6).
        .dropDestination(for: DroppedBackup.self) { files, _ in
            guard let file = files.first else { return false }
            router.restore(from: file.url)
            return true
        }
        .task { await observeBackupDue() }
    }

    private func observeBackupDue() async {
        do {
            for try await status in session.dependencies.backup.observeStatus() {
                backupDue = status.isDue(today: session.today)
            }
        } catch {}
    }

    /// Tax rates appear only for businesses that define their own (GENERIC).
    private var pages: [SettingsPage] {
        SettingsPage.allCases.filter { $0 != .taxRates || session.config.ratesFrom == .business }
    }
}

private struct SettingsPageView: View {
    let session: Session
    let page: SettingsPage

    var body: some View {
        switch page {
        case .profile: BusinessProfilePage(session: session)
        case .images: BusinessImagesPage(session: session)
        case .numbering: NumberingPage(session: session)
        case .defaults: DefaultsPage(session: session)
        case .taxRates: TaxRatesPage(session: session)
        case .sync: SyncPage(session: session)
        case .backup: BackupPage(session: session)
        case .about: AboutPage(session: session)
        }
    }
}

extension SettingsPage {
    var title: String {
        switch self {
        case .profile: "Business profile"
        case .images: "Logo and signature"
        case .numbering: "Invoice numbering"
        case .defaults: "Invoice defaults"
        case .taxRates: "Tax rates"
        case .sync: "iCloud sync"
        case .backup: "Backup"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .profile: "building.2"
        case .images: "signature"
        case .numbering: "number"
        case .defaults: "doc.text"
        case .taxRates: "percent"
        case .sync: "icloud"
        case .backup: "externaldrive"
        case .about: "info.circle"
        }
    }
}

// MARK: - Business profile

private struct BusinessProfilePage: View {
    let session: Session
    @State private var model: BusinessProfileViewModel

    init(session: Session) {
        self.session = session
        _model = State(initialValue: BusinessProfileViewModel(session: session))
    }

    var body: some View {
        Form {
            if model.state.attemptedSave, !model.issues.isEmpty {
                Section { IssueText(message: "Check the highlighted fields.") }
            }
            Section {
                LabeledContent("Country", value: session.countryName(session.business.countryCode))
                LabeledContent("Currency", value: session.business.homeCurrency.rawValue)
            } footer: {
                Text("Country and currency are fixed once your business is set up.")
            }
            RegistrationSections(draft: $model.state.draft, rules: model.rules, formatter: session.formatter,
                                 issue: model.visibleIssue, asksForFirstRate: false)
            BusinessDetailsSections(draft: $model.state.draft, rules: model.rules, issue: model.visibleIssue,
                                    taxIDFeedback: model.taxIDFeedback)
            if model.rules.showsLUT(model.state.draft) {
                LUTSection(draft: $model.state.draft)
            }
            BankSections(draft: $model.state.draft, rules: model.rules, issue: model.visibleIssue)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Business profile")
        .navigationBarTitleDisplayMode(.inline)
        .profileToolbar(model: model)
    }
}

/// India: Letter of Undertaking for exports without IGST.
private struct LUTSection: View {
    @Binding var draft: BusinessDraft

    var body: some View {
        Section {
            FormTextField(title: "LUT ARN (optional)", text: $draft.lutReference, prompt: "AD2903260123456",
                          capitalization: .characters, autocorrect: false)
            Toggle("Valid until", isOn: hasValidity)
            if let date = draft.lutValidUntil {
                DatePicker("Valid until", selection: validity(default: date), displayedComponents: .date)
                    .labelsHidden()
            }
        } header: {
            Text("Exports under LUT")
        } footer: {
            Text("Needed to invoice exports without IGST. Printed on those invoices.")
        }
    }

    private var hasValidity: Binding<Bool> {
        Binding(get: { draft.lutValidUntil != nil }, set: { on in
            draft.lutValidUntil = on ? LocalDate.today().adding(days: 365) : nil
        })
    }

    private func validity(default date: LocalDate) -> Binding<Date> {
        Binding(get: { date.startOfDayDate }, set: { draft.lutValidUntil = LocalDate.today(at: $0) })
    }
}

// MARK: - Defaults

private struct DefaultsPage: View {
    let session: Session
    @State private var model: BusinessProfileViewModel

    init(session: Session) {
        self.session = session
        _model = State(initialValue: BusinessProfileViewModel(session: session))
    }

    var body: some View {
        Form {
            Section {
                Stepper(value: $model.state.draft.paymentTermsDays, in: BusinessRules.paymentTermsRange) {
                    LabeledContent("Payment due", value: dueText)
                }
            } footer: {
                Text("New invoices are due this many days after their date.")
            }
            Section {
                Picker("Remind me", selection: $model.state.draft.reminderDaysAfterDue) {
                    Text("Never").tag(Int?.none)
                    ForEach([0, 1, 3, 7, 14, 30], id: \.self) { days in
                        Text(days == 0 ? "On the due date" : "\(days) days after the due date").tag(Optional(days))
                    }
                }
            } header: {
                Text("Overdue reminders")
            } footer: {
                Text("A reminder on this device for unpaid invoices. You can change it on each invoice.")
            }
            Section("Invoice design") {
                Picker("Template", selection: $model.state.draft.templateId) {
                    ForEach(TemplateID.known, id: \.self) { template in
                        Text(template.rawValue.capitalized).tag(template)
                    }
                }
                AccentPicker(selection: $model.state.draft.accentColor)
            }
            Section("Notes printed on new invoices") {
                FormTextField(title: "Notes", text: $model.state.draft.defaultNotes, prompt: "Thank you for your business.",
                              axis: .vertical)
                FormTextField(title: "Terms", text: $model.state.draft.defaultTerms,
                              prompt: "Payment by bank transfer within the due date.", axis: .vertical)
            }
        }
        .navigationTitle("Invoice defaults")
        .navigationBarTitleDisplayMode(.inline)
        .profileToolbar(model: model)
    }

    private var dueText: String {
        let days = model.state.draft.paymentTermsDays
        return days == 0 ? "On receipt" : "\(days) days"
    }
}

/// The accent colour presets from the design tokens.
private struct AccentPicker: View {
    @Binding var selection: String?

    /// Spoken names for the token presets (VoiceOver).
    static let names = ["#1F6FEB": "Blue", "#0F766E": "Teal", "#7C3AED": "Violet", "#B91C1C": "Red",
                        "#C2410C": "Orange", "#111827": "Charcoal"]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Accent colour")
            HStack(spacing: Theme.Space.m) {
                ForEach(Theme.accentPresets, id: \.self) { hex in
                    let isSelected = (selection ?? Theme.accentPresets.first) == hex
                    Button {
                        selection = hex == Theme.accentPresets.first ? nil : hex
                    } label: {
                        Circle()
                            .fill(Theme.color(hex: hex))
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(Theme.textPrimary, lineWidth: isSelected ? 3 : 0).padding(-4))
                            .frame(minWidth: Theme.Layout.minTouchTarget, minHeight: Theme.Layout.minTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.names[hex] ?? hex)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

private extension View {
    /// Save / Revert for pages backed by `BusinessProfileViewModel`.
    func profileToolbar(model: BusinessProfileViewModel) -> some View {
        toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await model.save() } }
                    .disabled(!model.hasChanges || model.state.isSaving)
            }
            ToolbarItem(placement: .cancellationAction) {
                if model.hasChanges {
                    Button("Revert") { model.discardChanges() }
                }
            }
        }
        .sensoryFeedback(.success, trigger: model.state.didSave) { _, saved in saved }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.state.errorMessage != nil }, set: { if !$0 { model.state.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.state.errorMessage ?? "")
        }
    }
}

// MARK: - Logo and signature

private struct BusinessImagesPage: View {
    let session: Session
    @State private var model: BusinessImagesViewModel

    init(session: Session) {
        self.session = session
        _model = State(initialValue: BusinessImagesViewModel(session: session))
    }

    var body: some View {
        Form {
            ImagesFormSections(
                logo: model.state.logo, signature: model.state.signature, isBusy: model.state.isBusy,
                signatureNote: session.config.family == "IN"
                    ? "Tax invoices need the signature of the supplier or an authorised person (GST Rule 46)." : nil,
                onPickLogo: { await model.setLogo(imageData: $0) },
                onRemoveLogo: { await model.removeLogo() },
                onSaveSignature: { await model.setSignature($0) },
                onRemoveSignature: { await model.setSignature(nil) }
            )
        }
        .navigationTitle("Logo and signature")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.state.errorMessage != nil }, set: { if !$0 { model.dismissError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.state.errorMessage ?? "")
        }
    }
}

// MARK: - Numbering

private struct NumberingPage: View {
    let session: Session
    @State private var model: NumberingSettingsViewModel

    init(session: Session) {
        self.session = session
        _model = State(initialValue: NumberingSettingsViewModel(session: session))
    }

    var body: some View {
        Form {
            ForEach(model.state.series) { series in
                Section {
                    LabeledContent("Next number", value: model.nextNumber(series))
                        .monospacedDigit()
                    LabeledContent("Pattern", value: series.pattern)
                    LabeledContent("Starts again", value: series.reset.label)
                    if model.rules.isEditable(series) {
                        Button("Change numbering") { model.edit(series) }
                    } else {
                        Text("Numbered on another device. Only that device changes it.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } header: {
                    Text(series.label)
                }
            }
            Section {
            } footer: {
                Text("Numbers are given when a document is issued, never to drafts, so there are no gaps.")
            }
        }
        .navigationTitle("Invoice numbering")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.observe() }
        .sheet(isPresented: editingBinding) {
            NumberingEditor(model: model, config: session.config)
        }
    }

    private var editingBinding: Binding<Bool> {
        Binding(get: { model.state.draft != nil }, set: { if !$0 { model.cancelEditing() } })
    }
}

private struct NumberingEditor: View {
    @Bindable var model: NumberingSettingsViewModel
    let config: TaxConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let draft = Binding($model.state.draft) {
                Form {
                    Section {
                        LabeledContent("Next number") {
                            Text(model.preview ?? "—").monospacedDigit().fontWeight(.semibold)
                        }
                    } footer: {
                        Text("Preview for a document issued today.")
                    }
                    Section {
                        FormTextField(title: "Name", text: draft.label, issue: message(.label, "name"))
                        FormTextField(title: "Pattern", text: draft.pattern, prompt: "INV/{fy}/{seq:4}",
                                      issue: message(.pattern, "pattern"), capitalization: .characters,
                                      autocorrect: false)
                        Picker("Start again at 1", selection: draft.reset) {
                            ForEach(NumberingReset.known, id: \.self) { reset in
                                Text(reset.label).tag(reset)
                            }
                        }
                        FormTextField(title: "Next number in this period", text: draft.nextNumberText,
                                      issue: message(.nextNumber, "next number"), keyboard: .numberPad)
                    } footer: {
                        Text(tokenHelp)
                    }
                }
                .navigationTitle("Change numbering")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.cancelEditing() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { if await model.saveEditing() { dismiss() } } }
                    }
                }
            }
        }
    }

    private var tokenHelp: String {
        var help = "{seq:4} is the sequence (0001), {fy} the financial year (26-27), {yyyy}, {yy} and {mm} the date."
        if let maxLength = config.numbering.maxLength {
            help += " Numbers can be up to \(maxLength) characters: letters, digits, / and -."
        }
        help += " Moving from another tool? Set the next number to continue where you left off."
        return help
    }

    private func message(_ field: NumberingSeriesField, _ name: String) -> String? {
        model.visibleIssue(field).map {
            IssueMessages.text($0, field: name, maxLength: config.numbering.maxLength)
        }
    }
}

extension NumberingReset {
    var label: String {
        switch self {
        case .fiscalYear: "Every financial year"
        case .calendarYear: "Every calendar year"
        case .never: "Never"
        default: rawValue
        }
    }
}

// MARK: - Tax rates (GENERIC)

private struct TaxRatesPage: View {
    let session: Session
    @State private var model: TaxRatesViewModel

    init(session: Session) {
        self.session = session
        _model = State(initialValue: TaxRatesViewModel(session: session))
    }

    var body: some View {
        Form {
            Section {
                ForEach(model.rates) { rate in
                    Button {
                        if rate.id != CustomRates.noTax.id { model.edit(rate) }
                    } label: {
                        LabeledContent(rate.label) {
                            if rate.id != CustomRates.noTax.id {
                                Image(systemName: "chevron.forward").foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .swipeActions {
                        if rate.id != CustomRates.noTax.id {
                            Button("Remove", role: .destructive) { Task { await model.remove(rate) } }
                        }
                    }
                }
                Button("Add rate", systemImage: "plus") { model.startNew() }
            } footer: {
                Text("\"No tax\" is always available. A rate used by an item can't be removed.")
            }
        }
        .navigationTitle("Tax rates")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { model.state.draft != nil }, set: { if !$0 { model.cancelEditing() } })) {
            TaxRateEditor(model: model)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.state.errorMessage != nil }, set: { if !$0 { model.state.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.state.errorMessage ?? "")
        }
    }
}

private struct TaxRateEditor: View {
    @Bindable var model: TaxRatesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let draft = Binding($model.state.draft) {
                Form {
                    Section {
                        FormTextField(title: "Tax name", text: draft.name, prompt: "Sales tax",
                                      issue: message(.name, "tax name"), capitalization: .words)
                        FormTextField(title: "Rate (%)", text: draft.percent, prompt: "8.875",
                                      issue: message(.percent, "rate"), keyboard: .decimalPad)
                    }
                    Section {
                        Toggle("Add a second tax", isOn: draft.hasSecondComponent)
                        if draft.wrappedValue.hasSecondComponent {
                            FormTextField(title: "Second tax name", text: draft.secondName,
                                          issue: message(.secondName, "tax name"), capitalization: .words)
                            FormTextField(title: "Second rate (%)", text: draft.secondPercent,
                                          issue: message(.secondPercent, "rate"), keyboard: .decimalPad)
                            Toggle("Charged on top of the first tax (compound)", isOn: draft.secondIsCompound)
                        }
                    } footer: {
                        Text("Some places charge two taxes on the same line, sometimes one on top of the other.")
                    }
                }
                .navigationTitle(model.state.editingID == nil ? "New rate" : "Edit rate")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.cancelEditing() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { if await model.saveEditing() { dismiss() } } }
                    }
                }
            }
        }
    }

    private func message(_ field: CustomRateField, _ name: String) -> String? {
        model.visibleIssue(field).map { IssueMessages.text($0, field: name) }
    }
}

// MARK: - About

private struct AboutPage: View {
    let session: Session

    var body: some View {
        Form {
            Section("App") {
                LabeledContent("Version", value: Self.version)
                LabeledContent("Your data", value: "On this device")
            }
            Section {
                LabeledContent("Tax rules", value: session.config.ref)
                LabeledContent("Status", value: session.config.reviewStatus == "reviewed"
                               ? "Professionally reviewed" : "Awaiting professional review")
            } header: {
                Text("\(session.config.labels.taxName) rules")
            } footer: {
                Text("Tax rules are built into the app and updated with it. Check invoices with your accountant.")
            }
            Section("This device") {
                LabeledContent("Device ID") {
                    Text(session.deviceID).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }
}

extension LocalDate {
    /// Midnight at the start of this date in the device's time zone (for `DatePicker`).
    var startOfDayDate: Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components) ?? Date()
    }
}
