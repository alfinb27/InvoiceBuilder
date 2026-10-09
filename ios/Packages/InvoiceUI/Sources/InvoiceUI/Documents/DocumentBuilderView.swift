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

    // Split in three: as one expression the body was too much for Xcode 26's type checker (CI).
    var body: some View {
        lifecycle
            .focusedSceneValue(\.documentEditor, model)
            .sheet(item: $model.preview) { DocumentPreviewView(model: $0) }
            // Review & send (`documents.md` §6.1): sending happens once the sheet is gone, so the PDF can open.
            .sheet(isPresented: $model.state.confirmingIssue, onDismiss: { Task { await model.sendAfterReview() } }) {
                ReviewSendView(model: model, session: session)
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) { model.dismissError() }
            } message: {
                Text(model.state.errorMessage ?? "")
            }
    }

    /// Loading, saving when the screen goes away or the app leaves the foreground, and the send haptic.
    private var lifecycle: some View {
        content
            .task { await model.load() }
            // A success tap when a draft becomes an issued document.
            .sensoryFeedback(.success, trigger: model.state.document.lifecycle) { old, new in
                Self.becameIssued(old, new)
            }
            .onDisappear { Task { await model.close() } }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { Task { await model.flush() } }
            }
    }

    @ViewBuilder private var content: some View {
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

    private static func becameIssued(_ old: DocumentLifecycle, _ new: DocumentLifecycle) -> Bool {
        old == .draft && new == .issued
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.state.errorMessage != nil }, set: { if !$0 { model.dismissError() } })
    }
}

/// What the wide layout's right pane shows.
private enum BuilderPane: String, CaseIterable {
    case preview, totals

    var label: String { rawValue.capitalized }
}

/// The guided builder (`docs/design/design.md` §6.4): who, what and when as three numbered cards, everything else
/// under More options, and the totals with Review & send pinned at the bottom. On wide iPads the live PDF preview
/// sits beside it.
struct DocumentBuilderView: View {
    @Bindable var model: DocumentViewModel
    let session: Session
    @State private var width: CGFloat = 0
    @State private var choosingClient = false
    @State private var confirmingDelete = false
    @State private var showsBreakdown = false
    @State private var pane: BuilderPane = .preview
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// iPad only, and only where the detail column is wide enough: it is the third of three columns, so that
    /// means a large iPad in landscape, Stage Manager, or the list collapsed. An iPhone in landscape is wide
    /// enough but stays compact, where the form needs the whole screen.
    private var twoPane: Bool { width >= 700 && sizeClass == .regular }
    private var paneWidth: CGFloat { width >= 900 ? 400 : 340 }

    var body: some View {
        HStack(spacing: 0) {
            GuidedBuilderForm(model: model, session: session, choosingClient: $choosingClient)
                .safeAreaInset(edge: .bottom) {
                    TotalsBar(model: model, session: session, showsBreakdown: $showsBreakdown)
                }
            if twoPane {
                Divider()
                sidePane
                    .frame(width: paneWidth)
                    .background(Theme.surfaceMuted)
            }
        }
        .background(Theme.background)
        // iPhone: the builder has the screen to itself, as in the design; the tab bar returns when it closes.
        .toolbar(sizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle(DocumentText.title(model.state.document, isPersisted: model.state.isPersisted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $choosingClient) {
            ClientPickerSheet(session: session, selectedID: model.state.document.clientId) { client in
                model.chooseClient(client)
            }
        }
        .sheet(item: lineEditorBinding) { _ in
            AddItemSheet(model: model, session: session)
        }
        .sheet(isPresented: $showsBreakdown) {
            TotalsBreakdownSheet(model: model, session: session)
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

    /// The "Add an item" sheet follows `state.lineEditor`; swiping it away cancels, as Cancel does.
    private var lineEditorBinding: Binding<DocumentViewModel.LineEditorState?> {
        Binding(get: { model.state.lineEditor }, set: { if $0 == nil { model.cancelLineEditor() } })
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
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text(DocumentText.title(model.state.document, isPersisted: model.state.isPersisted))
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.textPrimary)
                saveStatus
            }
            .accessibilityElement(children: .combine)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Preview") { Task { await model.openPreview() } }
                .fontWeight(.bold)
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
                Button("Duplicate item", systemImage: "square.on.square") { model.duplicateSelectedLine() }
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

    /// "Draft saved" under the title once autosave has written the draft (`documents.md` §5).
    @ViewBuilder private var saveStatus: some View {
        if model.state.saveFailed {
            Text("Not saved yet").font(Theme.Fonts.caption).foregroundStyle(Theme.danger)
        } else if model.state.isPersisted {
            Label("Draft saved", systemImage: "checkmark")
                .font(Theme.Fonts.caption.weight(.regular))
                .foregroundStyle(Theme.textSecondary)
                .labelStyle(SmallIconLabelStyle())
        }
    }
}

/// An icon and title with a 4 pt gap, the icon in brand ("✓ Draft saved").
private struct SmallIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(Theme.brand).font(.system(size: 10, weight: .heavy))
            configuration.title
        }
    }
}

// MARK: - The form

/// The three numbered cards, More options and the save state.
private struct GuidedBuilderForm: View {
    @Bindable var model: DocumentViewModel
    let session: Session
    @Binding var choosingClient: Bool
    @State private var showsMore = false

    private var document: InvoiceCore.Document { model.state.document }
    private var config: TaxConfig { model.config }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Three quick parts. We handle the tax maths.")
                    .font(Theme.Fonts.subhead)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Space.xs)
                banner
                clientCard
                linesCard
                whenCard
                MoreOptionsSection(model: model, session: session, isExpanded: $showsMore)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.l)
            .readableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            showsMore = model.isForeignCurrency || document.reverseCharge || document.pricesIncludeTax
                || document.placeOfSupply != nil || document.supplyDate != nil || document.discount != nil
                || document.shippingMinor != 0 || document.supplyType != config.supplyTypes.first?.id
        }
    }

    // MARK: Problems

    @ViewBuilder private var banner: some View {
        let problems = model.state.issueProblems.map {
            DocumentText.message($0, config: config, homeCurrency: model.homeCurrency, docType: document.docType)
        }
        let blocking = model.state.issueProblems.contains { if case .blockingIssue = $0 { true } else { false } }
        let warnings = model.engineIssues
            .filter { !blocking || $0.severity != .error }
            .map { DocumentText.message($0, config: config, homeCurrency: model.homeCurrency) }
        if !problems.isEmpty || !warnings.isEmpty {
            DocumentBanner(problems: problems, warnings: warnings.filter { !problems.contains($0) })
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder((problems.isEmpty ? Theme.warning : Theme.danger).opacity(0.5)))
        }
    }

    // MARK: 1 Who is it for?

    private var clientCard: some View {
        NumberedCard(number: 1, title: "Who is it for?") {
            if clientName != nil {
                Button("Change") { choosingClient = true }
                    .buttonStyle(.textLink)
                    .accessibilityLabel("Change client")
            }
        } content: {
            if let name = clientName {
                Button {
                    choosingClient = true
                } label: {
                    HStack(spacing: Theme.Space.m) {
                        Avatar(name: name, style: .tip)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(Theme.Fonts.rowTitle).foregroundStyle(Theme.textPrimary)
                            if let detail = clientDetail {
                                Text(detail).font(Theme.Fonts.footnote).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chooseClient")
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Button {
                        choosingClient = true
                    } label: {
                        Label("Choose a client", systemImage: "person.crop.circle.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("chooseClient")
                    Text("Or leave it empty for a walk-in customer.")
                        .font(Theme.Fonts.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if model.state.clientMissing {
                Text("This client was deleted. The \(DocumentText.noun(document.docType)) keeps their last details.")
                    .font(Theme.Fonts.footnote)
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    private var clientName: String? {
        model.state.client?.name ?? (document.clientId != nil ? document.buyerSnapshot?.name : nil)
    }

    /// "Bengaluru, Karnataka · GSTIN added"; abroad, the country.
    private var clientDetail: String? {
        guard let client = model.state.client else { return document.buyerSnapshot?.address }
        if client.countryCode != session.business.countryCode { return session.countryName(client.countryCode) }
        let place = [client.billingAddress?.city?.trimmedOrNil,
                     client.regionCode.flatMap { config.region($0)?.name }].compactMap { $0 }.joined(separator: ", ")
        let taxID = client.taxId?.trimmedOrNil != nil ? "\(config.labels.taxIdName) added" : nil
        let parts = [place.isEmpty ? nil : place, taxID].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: 2 What are you charging for?

    private var linesCard: some View {
        NumberedCard(number: 2, title: "What are you charging for?") {
            VStack(spacing: 0) {
                ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                    Button {
                        model.editLine(line.id)
                    } label: {
                        LineRow(line: line, computed: model.computed?.lines[safe: index], currency: document.currency,
                                chargesTax: model.chargesTax, session: session)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { lineMenu(line, index: index) }
                    .accessibilityHint("Opens the item to change it")
                    Divider().overlay(Theme.surfaceMuted)
                }
            }
            Button {
                model.addLine()
            } label: {
                Label("Add an item", systemImage: "plus")
                    .font(Theme.Fonts.callout.weight(.bold))
                    .foregroundStyle(Theme.brand)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.input)
                        .strokeBorder(Theme.brand.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.input))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addItem")
        }
    }

    @ViewBuilder
    private func lineMenu(_ line: LineItem, index: Int) -> some View {
        Button("Edit", systemImage: "pencil") { model.editLine(line.id) }
        Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateLine(line.id) }
        if index > 0 {
            Button("Move up", systemImage: "arrow.up") { model.moveLines(from: IndexSet(integer: index), to: index - 1) }
        }
        if index < document.lines.count - 1 {
            Button("Move down", systemImage: "arrow.down") {
                model.moveLines(from: IndexSet(integer: index), to: index + 2)
            }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { model.deleteLine(line.id) }
    }

    // MARK: 3 When should they pay?

    private var whenCard: some View {
        let isQuote = document.docType == .quote
        return NumberedCard(number: 3, title: isQuote ? "How long is this quote valid?" : "When should they pay?") {
            FlowLayout {
                ForEach(model.termChoices, id: \.self) { days in
                    ChoiceChip(title: days == 0 ? "Right away" : "\(days) days",
                               isSelected: model.selectedTermDays == days) {
                        model.setTerm(days: days)
                    }
                    .accessibilityIdentifier("term-\(days)")
                }
            }
            if let date = isQuote ? document.validUntil : document.dueDate {
                (Text(isQuote ? "Valid until " : "Due ") + Text(dueText(date)).bold().foregroundStyle(Theme.textPrimary))
                    .font(Theme.Fonts.subhead)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("dueText")
            }
        }
    }

    private func dueText(_ date: LocalDate) -> String {
        date == session.today ? "today, \(date.displayText)" : date.displayText
    }
}

// MARK: - More options

/// Everything most invoices never need, folded away: dates, discount and shipping, tax and currency, notes.
private struct MoreOptionsSection: View {
    @Bindable var model: DocumentViewModel
    let session: Session
    @Binding var isExpanded: Bool

    private var document: InvoiceCore.Document { model.state.document }
    private var config: TaxConfig { model.config }

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Theme.Space.s + 2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("More options").font(Theme.Fonts.rowTitle).foregroundStyle(Theme.textPrimary)
                        Text("Discount, notes, currency. Most invoices don't need these.")
                            .font(Theme.Fonts.caption.weight(.regular))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Theme.Space.l)
                .frame(minHeight: 52)
                .background(Theme.surfaceSubtle, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Shown" : "Hidden")
            .accessibilityIdentifier("moreOptions")
            if isExpanded {
                OptionGroup(title: "Dates") { dates }
                OptionGroup(title: "Discount and shipping") { adjustments }
                OptionGroup(title: "Tax and currency") { taxAndCurrency }
                    .accessibilityIdentifier("taxAndCurrency")
                OptionGroup(title: "Notes and terms") { notes }
            }
        }
    }

    // MARK: Dates

    @ViewBuilder private var dates: some View {
        OptionRow {
            Picker("Type", selection: Binding(get: { document.docType }, set: { model.setDocType($0) })) {
                Text("Invoice").tag(DocumentType.invoice)
                Text("Quote").tag(DocumentType.quote)
            }
            .pickerStyle(.segmented)
        }
        OptionRow {
            DatePicker("\(DocumentText.noun(document.docType).capitalized) date",
                       selection: Binding(get: { document.issueDate.date },
                                          set: { model.setIssueDate(LocalDate(date: $0)) }),
                       displayedComponents: .date)
        }
        if document.docType == .quote {
            OptionRow {
                DatePicker("Valid until", selection: Binding(
                    get: { (document.validUntil ?? document.issueDate).date },
                    set: { model.setValidUntil(LocalDate(date: $0)) }
                ), in: document.issueDate.date..., displayedComponents: .date)
            }
        } else {
            OptionRow {
                DatePicker("Due date", selection: Binding(
                    get: { (document.dueDate ?? document.issueDate).date },
                    set: { model.setDueDate(LocalDate(date: $0)) }
                ), in: document.issueDate.date..., displayedComponents: .date)
            }
            OptionRow(divider: false) {
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

    // MARK: Discount and shipping

    @ViewBuilder private var adjustments: some View {
        let symbol = session.dependencies.reference.currencies[document.currency]?.symbol ?? document.currency.rawValue
        OptionRow {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack {
                    Text("Discount")
                    Spacer()
                    TextField("0", text: Binding(get: { model.state.discountText },
                                                 set: { model.setDiscountText(DecimalPadText.normalized($0)) }))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .accessibilityLabel("Discount")
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
        }
        OptionRow(divider: false) {
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

    // MARK: Tax and currency

    @ViewBuilder private var taxAndCurrency: some View {
        if model.showsSupplyType {
            OptionRow {
                Picker("Supply", selection: Binding(get: { document.supplyType }, set: { model.setSupplyType($0) })) {
                    ForEach(config.supplyTypes) { Text($0.label).tag($0.id) }
                }
            }
        }
        if model.showsPlaceOfSupply { OptionRow { placeOfSupplyPicker } }
        OptionRow {
            Toggle("Different supply date", isOn: Binding(
                get: { document.supplyDate != nil },
                set: { model.setSupplyDate($0 ? document.issueDate : nil) }
            ))
        }
        if let supplyDate = document.supplyDate {
            OptionRow {
                DatePicker("Supply date", selection: Binding(get: { supplyDate.date },
                                                             set: { model.setSupplyDate(LocalDate(date: $0)) }),
                           displayedComponents: .date)
            }
        }
        if model.showsReverseCharge {
            OptionRow {
                Toggle("Reverse charge", isOn: Binding(get: { document.reverseCharge },
                                                       set: { model.setReverseCharge($0) }))
            }
        }
        if model.showsPricesIncludeTax {
            OptionRow {
                Toggle("Prices include \(config.labels.taxName)", isOn: Binding(
                    get: { document.pricesIncludeTax }, set: { model.setPricesIncludeTax($0) }))
            }
        }
        OptionRow(divider: model.isForeignCurrency || model.showsRoundOff) {
            Picker("Currency", selection: Binding(get: { document.currency }, set: { model.setCurrency($0) })) {
                ForEach(session.dependencies.reference.currencies.all) { currency in
                    Text("\(currency.code.rawValue) – \(currency.name)").tag(currency.code)
                }
            }
        }
        if model.isForeignCurrency {
            OptionRow(divider: model.showsRoundOff) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    LabeledContent("1 \(document.currency.rawValue) =") {
                        HStack {
                            TextField("Exchange rate", text: Binding(
                                get: { model.state.exchangeRateText },
                                set: { model.setExchangeRateText(DecimalPadText.normalized($0)) }))
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
        if model.showsRoundOff {
            OptionRow(divider: false) {
                Toggle(config.rounding.grandTotal?.label ?? "Round off", isOn: Binding(
                    get: { model.roundOffOn }, set: { model.setRoundOff($0) }))
            }
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

    // MARK: Notes and terms

    @ViewBuilder private var notes: some View {
        OptionRow {
            TextField("Notes", text: Binding(get: { model.state.notesText }, set: { model.setNotesText($0) }),
                      axis: .vertical)
                .lineLimit(2...6)
        }
        OptionRow(divider: false) {
            TextField("Terms", text: Binding(get: { model.state.termsText }, set: { model.setTermsText($0) }),
                      axis: .vertical)
                .lineLimit(2...6)
        }
    }
}

/// A titled white group of option rows.
private struct OptionGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Overline(text: title).padding(.horizontal, Theme.Space.xs)
            VStack(spacing: 0) { content }
                .padding(.horizontal, Theme.Space.l)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.border))
        }
    }
}

/// One control row of an option group, with a hairline under it.
private struct OptionRow<Content: View>: View {
    var divider = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: Theme.Layout.minTouchTarget + 4, alignment: .leading)
                .padding(.vertical, Theme.Space.xs)
            if divider { Divider().overlay(Theme.surfaceMuted) }
        }
    }
}

// MARK: - Totals

/// The pinned totals: subtotal, the tax "added for you", the total and Review & send.
private struct TotalsBar: View {
    @Bindable var model: DocumentViewModel
    let session: Session
    @Binding var showsBreakdown: Bool

    private var currency: CurrencyCode { model.state.document.currency }

    var body: some View {
        VStack(spacing: 6) {
            summary
            PrimaryButton(title: "Review & send", isBusy: model.state.isWorking,
                          isEnabled: model.canRequestIssue) {
                Task { await model.requestIssue() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("reviewAndSend")
            .padding(.top, 6)
        }
        .padding(.horizontal, Theme.Layout.screenGutter)
        .padding(.top, Theme.Space.m + 2)
        .padding(.bottom, Theme.Space.s)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        .shadow(color: Theme.shadow.opacity(0.06), radius: 9, y: -6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bottomBar")
    }

    @ViewBuilder private var summary: some View {
        if let computed = model.computed, !model.state.document.lines.isEmpty {
            Button {
                showsBreakdown = true
            } label: {
                VStack(spacing: 6) {
                    let totals = computed.totals
                    row("Subtotal", totals.subtotal)
                    if totals.discount != 0 { row("Discount", -totals.discount) }
                    if totals.shipping != 0 { row("Shipping", totals.shipping) }
                    if computed.chargesTax, totals.tax != 0 {
                        HStack(spacing: 6) {
                            Text(taxLabel(computed))
                            Badge(text: computed.inclusive ? "included" : "added for you")
                            Spacer()
                            Text(money(totals.tax)).monospacedDigit()
                        }
                        .font(Theme.Fonts.subhead)
                        .foregroundStyle(Theme.textSecondary)
                    }
                    if totals.roundOff != 0 {
                        row(model.config.rounding.grandTotal?.label ?? "Round off", totals.roundOff)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Total").font(Theme.Fonts.headline).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(money(totals.total))
                            .font(Theme.Fonts.amountLarge)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .accessibilityIdentifier("totalAmount")
                    }
                    .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Shows the full tax breakdown")
            .accessibilityIdentifier("totals")
        } else if let error = model.engineError, !model.state.document.lines.isEmpty {
            IssueText(message: DocumentText.message(error, config: model.config))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Add an item to see the total.")
                .font(Theme.Fonts.subhead)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "GST 18%" when every line has the same rate, else "GST".
    private func taxLabel(_ computed: ComputedDocument) -> String {
        let rates = Set(computed.lines.map(\.rate))
        let name = model.config.labels.taxName
        guard rates.count == 1, let rate = rates.first else { return name }
        return "\(name) \(SpecFormatter.percent(rate))"
    }

    private func row(_ title: String, _ minor: Int64) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(money(minor)).monospacedDigit()
        }
        .font(Theme.Fonts.subhead)
        .foregroundStyle(Theme.textSecondary)
    }

    private func money(_ minor: Int64) -> String { session.money(minor, currency: currency) }
}

/// The full totals and tax breakdown, a tap away from the totals bar.
private struct TotalsBreakdownSheet: View {
    let model: DocumentViewModel
    let session: Session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                TotalsView(computed: model.computed, error: model.engineError,
                           currency: model.state.document.currency, config: model.config, session: session)
                    .padding(Theme.Space.l)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .padding(Theme.Space.l)
            }
            .background(Theme.background)
            .navigationTitle("Tax breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// One document line: description, quantity × price · rate, and the amount.
struct LineRow: View {
    let line: LineItem
    let computed: ComputedLine?
    let currency: CurrencyCode
    let chargesTax: Bool
    let session: Session

    var body: some View {
        AdaptiveRow(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.description.isEmpty ? "No description" : line.description)
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(line.description.isEmpty ? Theme.danger : Theme.textPrimary)
                Text(detailText)
                    .font(Theme.Fonts.footnote)
                    .foregroundStyle(chargesTax && line.rateId.isEmpty ? Theme.danger : Theme.textSecondary)
            }
        } value: {
            Text(computed.map { session.money($0.amount, currency: currency) } ?? "—")
                .font(Theme.Fonts.rowTitle.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, Theme.Space.s)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    /// "2 × ₹2,500 · GST 18%", with the unit and any line discount.
    private var detailText: String {
        let unit = line.unit.map { " " + session.unitLabel($0) } ?? ""
        var text = SpecFormatter.quantity(line.quantity) + unit + " × "
            + session.money(line.unitPriceMinor, currency: currency)
        switch line.discount {
        case .percent(let value)?: text += " − \(SpecFormatter.percent(value))"
        case .amount(let minor)?: text += " − " + session.money(minor, currency: currency)
        case nil: break
        }
        if chargesTax {
            text += " · " + (session.rate(line.rateId)?.label ?? (line.rateId.isEmpty ? "Choose a rate" : line.rateId))
        }
        return text
    }
}
