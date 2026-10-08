import InvoiceCore
import SwiftUI

/// The detail column of the Invoices tab: the builder for drafts, the read-only view once issued.
struct DocumentScreen: View {
    let session: Session
    @State private var model: DocumentViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(session: Session, route: DocumentRoute) {
        self.session = session
        _model = State(initialValue: DocumentViewModel(session: session, route: route))
    }

    var body: some View {
        Group {
            if !model.state.isLoaded {
                ProgressView()
            } else if model.state.notFound {
                ContentUnavailableView("This document no longer exists", systemImage: "doc.questionmark")
            } else if model.isDraft {
                DocumentBuilderView(model: model, session: session)
            } else {
                IssuedDocumentView(model: model, session: session)
            }
        }
        .task { await model.load() }
        .onDisappear { Task { await model.close() } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await model.flush() } }
        }
        .focusedSceneValue(\.documentEditor, model)
        .sheet(item: $model.preview) { DocumentPreviewView(model: $0) }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.state.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.state.errorMessage != nil }, set: { if !$0 { model.dismissError() } })
    }
}

/// Which sheet the builder shows.
private enum BuilderSheet: String, Identifiable {
    case client, catalog
    var id: String { rawValue }
}

/// What the wide layout's right pane shows.
private enum BuilderPane: String, CaseIterable {
    case preview, totals

    var label: String { rawValue.capitalized }
}

/// The invoice / quote builder (wireframe 8): a form, and on wide screens the live PDF preview beside it, with the
/// totals and tax panel a tap away.
struct DocumentBuilderView: View {
    @Bindable var model: DocumentViewModel
    let session: Session
    @State private var width: CGFloat = 0
    @State private var sheet: BuilderSheet?
    @State private var confirmingDelete = false
    @State private var pane: BuilderPane = .preview
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// iPad only, and only where the detail column is wide enough: it is the third of three columns, so that
    /// means a large iPad in landscape, Stage Manager, or the list collapsed. An iPhone in landscape is wide
    /// enough but stays compact, where the form needs the whole screen.
    private var twoPane: Bool { width >= 700 && sizeClass == .regular }
    private var paneWidth: CGFloat { width >= 900 ? 400 : 340 }

    var body: some View {
        HStack(spacing: 0) {
            BuilderForm(model: model, session: session, showsTotals: !twoPane, sheet: $sheet)
            if twoPane {
                Divider()
                sidePane
                    .frame(width: paneWidth)
                    .background(Theme.surfaceMuted)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle(DocumentText.title(model.state.document, isPersisted: model.state.isPersisted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .client:
                ClientPickerSheet(session: session, selectedID: model.state.document.clientId) { client in
                    model.chooseClient(client)
                }
            case .catalog:
                CatalogPickerSheet(session: session) { item in model.addItem(item) }
            }
        }
        .confirmationDialog(issueTitle, isPresented: $model.state.confirmingIssue, titleVisibility: .visible) {
            Button("Issue \(DocumentText.noun(model.state.document.docType))") {
                Task { await model.confirmIssue() }
            }
        } message: {
            Text(issueMessage)
        }
        .sheet(isPresented: $model.state.showsPaywall) {
            PaywallView(session: session)
        }
        .sheet(item: $model.state.seriesChoice) { choice in
            SeriesChoiceSheet(choice: choice, docType: model.state.document.docType,
                              startOwn: { Task { await model.startOwnSeries() } },
                              takeOver: { id in Task { await model.takeOver(seriesID: id) } },
                              cancel: { model.state.seriesChoice = nil })
        }
        .confirmationDialog("Delete this draft?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete draft", role: .destructive) { Task { await model.deleteDraft() } }
        }
    }

    /// The preview of the draft as it is edited, or the totals and tax panel.
    private var sidePane: some View {
        VStack(spacing: 0) {
            Picker("Pane", selection: $pane) {
                ForEach(BuilderPane.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(Theme.Space.m)
            .accessibilityIdentifier("builderPane")
            Divider()
            switch pane {
            case .preview:
                DocumentPreviewPane(session: session, document: model.documentToRender, computed: model.computed)
                    .accessibilityIdentifier("builderPreview")
            case .totals:
                ScrollView {
                    TotalsView(computed: model.computed, error: model.engineError,
                               currency: model.state.document.currency, config: model.config, session: session)
                        .padding(Theme.Space.l)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model.requestIssue() }
            } label: {
                if model.state.isWorking { ProgressView() } else { Text("Issue") }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canRequestIssue)
            .accessibilityIdentifier("issueButton")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Preview", systemImage: "doc.richtext") { Task { await model.openPreview() } }
                .disabled(!model.canPreview)
                .accessibilityIdentifier("previewButton")
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button("Duplicate \(DocumentText.noun(model.state.document.docType))",
                       systemImage: "plus.square.on.square") {
                    Task { await model.duplicate() }
                }
                .disabled(!model.state.isPersisted && model.state.document.lines.isEmpty)
                Button("Duplicate line", systemImage: "square.on.square") { model.duplicateSelectedLine() }
                    .disabled(!model.canDuplicateSelectedLine)
                Divider()
                Button("Delete draft", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil,
                                                for: nil)
            }
        }
    }

    private var issueTitle: String {
        "Issue this \(DocumentText.noun(model.state.document.docType))?"
    }

    private var issueMessage: String {
        let number = model.state.numberPreview.map { "It will be numbered \($0). " } ?? ""
        return number + "Issued documents keep their number and can't be deleted."
    }
}

/// The builder's form sections.
private struct BuilderForm: View {
    @Bindable var model: DocumentViewModel
    let session: Session
    let showsTotals: Bool
    @Binding var sheet: BuilderSheet?
    @State private var showsTaxAndCurrency = false

    private var document: InvoiceCore.Document { model.state.document }
    private var config: TaxConfig { model.config }

    var body: some View {
        Form {
            banner
            clientSection
            detailsSection
            linesSection
            adjustmentsSection
            taxAndCurrencySection
            if showsTotals {
                Section("Totals") {
                    TotalsView(computed: model.computed, error: model.engineError, currency: document.currency,
                               config: config, session: session)
                }
            }
            notesSection
        }
        .onAppear {
            showsTaxAndCurrency = model.isForeignCurrency || document.reverseCharge || document.pricesIncludeTax
                || document.placeOfSupply != nil || document.supplyDate != nil
                || document.supplyType != config.supplyTypes.first?.id
        }
    }

    // MARK: Sections

    @ViewBuilder private var banner: some View {
        let problems = model.state.issueProblems.map {
            DocumentText.message($0, config: config, homeCurrency: model.homeCurrency, docType: document.docType)
        }
        let blocking = model.state.issueProblems.contains { if case .blockingIssue = $0 { true } else { false } }
        let warnings = model.engineIssues
            .filter { !blocking || $0.severity != .error }
            .map { DocumentText.message($0, config: config, homeCurrency: model.homeCurrency) }
        if !problems.isEmpty || !warnings.isEmpty {
            Section {
                DocumentBanner(problems: problems, warnings: warnings.filter { !problems.contains($0) })
            }
        }
    }

    private var clientSection: some View {
        Section("Client") {
            Button {
                sheet = .client
            } label: {
                if let name = clientName {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(name).foregroundStyle(Theme.textPrimary)
                        if let detail = clientDetail {
                            Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }
                    }
                } else {
                    Label("Choose client", systemImage: "person.crop.circle.badge.plus")
                }
            }
            .accessibilityIdentifier("chooseClient")
            if model.state.clientMissing {
                Text("This client was deleted. The \(DocumentText.noun(document.docType)) keeps their last details.")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    private var clientName: String? {
        model.state.client?.name ?? (document.clientId != nil ? document.buyerSnapshot?.name : nil)
    }

    private var clientDetail: String? {
        if let client = model.state.client {
            if client.countryCode != session.business.countryCode { return session.countryName(client.countryCode) }
            if let taxId = client.taxId { return "\(config.labels.taxIdName) \(taxId)" }
            return client.billingAddress?.singleLine
        }
        return document.buyerSnapshot?.address
    }

    private var detailsSection: some View {
        Section("Details") {
            Picker("Type", selection: Binding(get: { document.docType }, set: { model.setDocType($0) })) {
                Text("Invoice").tag(DocumentType.invoice)
                Text("Quote").tag(DocumentType.quote)
            }
            .pickerStyle(.segmented)
            DatePicker("Issue date", selection: Binding(get: { document.issueDate.date },
                                                        set: { model.setIssueDate(LocalDate(date: $0)) }),
                       displayedComponents: .date)
            if document.docType == .quote {
                DatePicker("Valid until", selection: Binding(
                    get: { (document.validUntil ?? document.issueDate).date },
                    set: { model.setValidUntil(LocalDate(date: $0)) }
                ), in: document.issueDate.date..., displayedComponents: .date)
            } else {
                HStack {
                    DatePicker("Due date", selection: Binding(
                        get: { (document.dueDate ?? document.issueDate).date },
                        set: { model.setDueDate(LocalDate(date: $0)) }
                    ), in: document.issueDate.date..., displayedComponents: .date)
                    Menu {
                        ForEach([0, 7, 15, 30, 45, 60], id: \.self) { days in
                            Button(days == 0 ? "Due on receipt" : "\(days) days") { model.setDue(daysAfterIssue: days) }
                        }
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                            .accessibilityLabel("Payment terms")
                    }
                }
                Picker("Remind me", selection: Binding(get: { document.reminderDaysAfterDueOverride },
                                                        set: { model.setReminderOverride($0) })) {
                    Text("Business default").tag(Int?.none)
                    ForEach([0, 1, 3, 7, 14, 30], id: \.self) { days in
                        Text(days == 0 ? "On the due date" : "\(days) days after the due date").tag(Optional(days))
                    }
                }
                .accessibilityIdentifier("reminderOverridePicker")
            }
        }
    }

    private var linesSection: some View {
        Section {
            ForEach(document.lines) { line in
                let index = document.lines.firstIndex { $0.id == line.id }
                Button {
                    model.editLine(line.id)
                } label: {
                    LineRow(line: line, computed: index.flatMap { model.computed?.lines[safe: $0] },
                            currency: document.currency, chargesTax: model.chargesTax, session: session)
                }
                .foregroundStyle(Theme.textPrimary)
                .popover(item: editorBinding(for: line.id)) { _ in
                    LineEditorView(model: model, session: session)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) { model.deleteLine(line.id) }
                    Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateLine(line.id) }
                        .tint(Theme.info)
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { model.editLine(line.id) }
                    Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateLine(line.id) }
                    Button("Delete", systemImage: "trash", role: .destructive) { model.deleteLine(line.id) }
                }
            }
            .onMove { model.moveLines(from: $0, to: $1) }
            Button {
                sheet = .catalog
            } label: {
                Label("Add from items", systemImage: "shippingbox")
            }
            .accessibilityIdentifier("addFromItems")
            Button {
                model.addLine()
            } label: {
                Label("Add line", systemImage: "plus")
            }
            .accessibilityIdentifier("addLine")
            .popover(item: newLineBinding) { _ in
                LineEditorView(model: model, session: session)
            }
        } header: {
            HStack {
                Text("Items")
                Spacer()
                if document.lines.count > 1 {
                    EditButton()
                        .font(.footnote)
                        .accessibilityLabel("Reorder items")
                }
            }
        }
    }

    @ViewBuilder private var adjustmentsSection: some View {
        let symbol = session.dependencies.reference.currencies[document.currency]?.symbol ?? document.currency.rawValue
        Section("Discount and shipping") {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack {
                    TextField("Discount", text: Binding(
                        get: { model.state.discountText },
                        set: { model.setDiscountText(DecimalPadText.normalized($0)) }
                    ))
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("discountField")
                    Picker("Discount type", selection: Binding(get: { model.state.discountIsPercent },
                                                               set: { model.setDiscountIsPercent($0) })) {
                        Text("%").tag(true)
                        Text(document.currency == model.homeCurrency ? symbol : document.currency.rawValue).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                if let issue = model.discountIssue {
                    IssueText(message: IssueMessages.text(issue, field: "discount"))
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                LabeledContent("Shipping") {
                    TextField("0", text: Binding(get: { model.state.shippingText },
                                                 set: { model.setShippingText(DecimalPadText.normalized($0)) }))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("shippingField")
                }
                if let issue = model.shippingIssue {
                    IssueText(message: IssueMessages.text(issue, field: "shipping"))
                }
            }
        }
    }

    private var taxAndCurrencySection: some View {
        Section {
            DisclosureGroup("Tax and currency", isExpanded: $showsTaxAndCurrency) {
                if model.showsSupplyType {
                    Picker("Supply", selection: Binding(get: { document.supplyType },
                                                        set: { model.setSupplyType($0) })) {
                        ForEach(config.supplyTypes) { Text($0.label).tag($0.id) }
                    }
                }
                if model.showsPlaceOfSupply { placeOfSupplyPicker }
                Toggle("Different supply date", isOn: Binding(
                    get: { document.supplyDate != nil },
                    set: { model.setSupplyDate($0 ? document.issueDate : nil) }
                ))
                if let supplyDate = document.supplyDate {
                    DatePicker("Supply date", selection: Binding(get: { supplyDate.date },
                                                                 set: { model.setSupplyDate(LocalDate(date: $0)) }),
                               displayedComponents: .date)
                }
                if model.showsReverseCharge {
                    Toggle("Reverse charge", isOn: Binding(get: { document.reverseCharge },
                                                           set: { model.setReverseCharge($0) }))
                }
                if model.showsPricesIncludeTax {
                    Toggle("Prices include \(config.labels.taxName)", isOn: Binding(
                        get: { document.pricesIncludeTax }, set: { model.setPricesIncludeTax($0) }))
                }
                currencyRows
                if model.showsRoundOff {
                    Toggle(config.rounding.grandTotal?.label ?? "Round off", isOn: Binding(
                        get: { model.roundOffOn }, set: { model.setRoundOff($0) }))
                }
            }
            .accessibilityIdentifier("taxAndCurrency")
        }
    }

    private var placeOfSupplyPicker: some View {
        let automatic = model.derivedPlaceOfSupply.map { code in
            "Automatic (\(config.region(code)?.name ?? code))"
        } ?? "Automatic"
        return Picker(config.labels.placeOfSupply ?? "Place of supply", selection: Binding(
            get: { document.placeOfSupply }, set: { model.setPlaceOfSupply($0) }
        )) {
            Text(automatic).tag(String?.none)
            ForEach(config.activeRegionsByName) { region in
                Text(region.name).tag(Optional(region.code))
            }
        }
    }

    @ViewBuilder private var currencyRows: some View {
        Picker("Currency", selection: Binding(get: { document.currency }, set: { model.setCurrency($0) })) {
            ForEach(session.dependencies.reference.currencies.all) { currency in
                Text("\(currency.code.rawValue) – \(currency.name)").tag(currency.code)
            }
        }
        if model.isForeignCurrency {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                LabeledContent("1 \(document.currency.rawValue) =") {
                    HStack {
                        TextField("Exchange rate", text: Binding(get: { model.state.exchangeRateText },
                                                                 set: { model.setExchangeRateText(
                                                                     DecimalPadText.normalized($0)) }))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(model.homeCurrency.rawValue).foregroundStyle(Theme.textSecondary)
                    }
                }
                if let issue = model.exchangeRateIssue {
                    IssueText(message: IssueMessages.text(issue, field: "exchange rate"))
                }
            }
        }
    }

    private var notesSection: some View {
        Section {
            TextField("Notes", text: Binding(get: { model.state.notesText }, set: { model.setNotesText($0) }),
                      axis: .vertical)
                .lineLimit(2...6)
            TextField("Terms", text: Binding(get: { model.state.termsText }, set: { model.setTermsText($0) }),
                      axis: .vertical)
                .lineLimit(2...6)
        } header: {
            Text("Notes and terms")
        } footer: {
            Text(model.state.saveFailed ? "Couldn't save the latest changes. They'll be saved again with your next change."
                                        : "Drafts save automatically.")
                .foregroundStyle(model.state.saveFailed ? Theme.danger : Theme.textSecondary)
        }
    }

    // MARK: Line editor presentation (a popover in regular width, a sheet in compact width)

    private func editorBinding(for lineID: String) -> Binding<DocumentViewModel.LineEditorState?> {
        Binding(
            get: { model.state.lineEditor.flatMap { !$0.isNew && $0.lineID == lineID ? $0 : nil } },
            set: { if $0 == nil { closeEditor() } }
        )
    }

    private var newLineBinding: Binding<DocumentViewModel.LineEditorState?> {
        Binding(
            get: { model.state.lineEditor.flatMap { $0.isNew ? $0 : nil } },
            set: { if $0 == nil { closeEditor() } }
        )
    }

    /// Dismissed by tapping outside or swiping down: keeps a valid line, drops an invalid one.
    private func closeEditor() {
        guard model.state.lineEditor != nil else { return }
        if !model.commitLineEditor() { model.cancelLineEditor() }
    }
}

/// One document line: description, quantity × price, rate and amount.
struct LineRow: View {
    let line: LineItem
    let computed: ComputedLine?
    let currency: CurrencyCode
    let chargesTax: Bool
    let session: Session

    var body: some View {
        AdaptiveRow {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(line.description.isEmpty ? "No description" : line.description)
                    .foregroundStyle(line.description.isEmpty ? Theme.danger : Theme.textPrimary)
                Text(quantityText).font(.subheadline).foregroundStyle(Theme.textSecondary)
                if chargesTax {
                    Text(session.rate(line.rateId)?.label ?? (line.rateId.isEmpty ? "Choose a rate" : line.rateId))
                        .font(.caption)
                        .foregroundStyle(line.rateId.isEmpty ? Theme.danger : Theme.textTertiary)
                }
            }
        } value: {
            Text(computed.map { session.money($0.amount, currency: currency) } ?? "—")
                .monospacedDigit()
        }
        .padding(.vertical, Theme.Space.xxs)
        .accessibilityElement(children: .combine)
    }

    private var quantityText: String {
        let unit = line.unit.map { " " + session.unitLabel($0) } ?? ""
        var text = SpecFormatter.quantity(line.quantity) + unit + " × "
            + session.money(line.unitPriceMinor, currency: currency)
        switch line.discount {
        case .percent(let value)?: text += " − \(SpecFormatter.percent(value))"
        case .amount(let minor)?: text += " − " + session.money(minor, currency: currency)
        case nil: break
        }
        return text
    }
}
