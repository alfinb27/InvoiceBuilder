import InvoiceCore
import SwiftUI

/// The tabs of the "Add an item" sheet.
private enum AddItemTab: String, CaseIterable {
    case saved, new

    var label: String { self == .saved ? "My saved items" : "Something new" }
    /// At accessibility text sizes, so the segments never truncate.
    var shortLabel: String { self == .saved ? "Saved" : "New" }
}

/// Adding and editing a line (`spec/documents.md` §3.2, `docs/design/design.md` §6.5): "My saved items" adds
/// catalogue lines with a tap; "Something new" asks what was sold, how many, the price for one and the rate, shows the
/// line's total live and can save it for next time. Editing a line opens the same form without the tabs.
struct AddItemSheet: View {
    @Bindable var model: DocumentViewModel
    let session: Session
    @State private var tab: AddItemTab = .new
    @State private var tabChosen = false
    @State private var items: [CatalogItem] = []
    @State private var query = ""
    @State private var added: [String: Int] = [:]
    @State private var showsDetails = false
    @FocusState private var focus: LineItemField?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var editor: DocumentViewModel.LineEditorState? { model.state.lineEditor }
    private var isNew: Bool { editor?.isNew ?? true }
    private var document: InvoiceCore.Document { model.state.document }
    private var config: TaxConfig { model.config }
    private var taxName: String { config.labels.taxName }
    private var liveItems: [CatalogItem] { items.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if isNew {
                        Picker("Add from", selection: $tab) {
                            ForEach(AddItemTab.allCases, id: \.self) {
                                Text(typeSize.isAccessibilitySize ? $0.shortLabel : $0.label).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("addItemTabs")
                    }
                    if isNew, tab == .saved { savedItems } else { newItemForm }
                }
                .padding(Theme.Layout.screenGutter)
                .readableWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.surface)
            .navigationTitle(isNew ? "Add an item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .task { await observeItems() }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { model.cancelLineEditor() }
        }
        if !isNew, let lineID = editor?.lineID {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        if model.commitLineEditor() { model.duplicateLine(lineID) }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        model.cancelLineEditor()
                        model.deleteLine(lineID)
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("lineMenu")
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }
        }
    }

    private var bottomBar: some View {
        Group {
            if isNew, tab == .saved {
                PrimaryButton(title: added.isEmpty ? "Close" : "Done") { model.cancelLineEditor() }
                    .accessibilityIdentifier("catalogDone")
            } else {
                // ⌘↩, not plain Return: Return moves between the fields.
                PrimaryButton(title: isNew ? "Add to \(DocumentText.noun(document.docType))" : "Save") {
                    model.commitLineEditor()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("lineDone")
            }
        }
        .padding(.horizontal, Theme.Layout.screenGutter)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bottomBar")
    }

    // MARK: My saved items

    @ViewBuilder private var savedItems: some View {
        if liveItems.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("No saved items yet").font(Theme.Fonts.headline).foregroundStyle(Theme.textPrimary)
                Text("Add something new and keep “Save to my items” on, and it shows up here next time.")
                    .font(Theme.Fonts.subhead)
                    .foregroundStyle(Theme.textSecondary)
                Button("Add something new") { tab = .new }
                    .buttonStyle(.textLink)
            }
            .padding(.top, Theme.Space.s)
        } else {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                TextField("Search your saved items", text: $query,
                          prompt: Text("Name or \(config.labels.productCodeName)").foregroundStyle(Theme.textSecondary))
                    .autocorrectionDisabled()
                    .accessibilityAddTraits(.isSearchField)
            }
            .inputBox()
            VStack(spacing: 0) {
                ForEach(SetupSearch.items(liveItems, matching: query)) { item in
                    Button {
                        let needsPrice = model.addItem(item)
                        added[item.id, default: 0] += 1
                        if needsPrice { tab = .new } // the price is asked for in the form
                    } label: {
                        savedItemRow(item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("catalogItem-\(item.name)")
                    Divider().overlay(Theme.surfaceMuted)
                }
            }
        }
    }

    private func savedItemRow(_ item: CatalogItem) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(Theme.Fonts.rowTitle).foregroundStyle(Theme.textPrimary)
                Text(session.money(item.unitPriceMinor, currency: item.currency)
                     + (item.priceIncludesTax ? " incl. \(taxName)" : "")
                     + (model.chargesTax ? " · " + (session.rate(item.rateId)?.label ?? "") : ""))
                    .font(Theme.Fonts.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let count = added[item.id] {
                Tag(text: count == 1 ? "Added" : "Added ×\(count)", color: Theme.success)
            } else {
                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.brand)
                    .accessibilityLabel("Add")
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    // MARK: Something new

    @ViewBuilder private var newItemForm: some View {
        if editor?.needsPrice == true {
            TipCallout("Enter the price in \(document.currency.rawValue): there's no exchange rate to convert the "
                       + "item's saved price.")
        }
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: "What did you sell?")
            TextField("What did you sell?", text: text(\.description),
                      prompt: Text("Website design").foregroundStyle(Theme.textSecondary))
                .textInputAutocapitalization(.sentences)
                .focused($focus, equals: .description)
                .submitLabel(.next)
                .onSubmit { focus = .price }
                .inputBox(isFocused: focus == .description)
                .accessibilityIdentifier("lineDescription")
            if let issue = message(.description, "description") {
                IssueText(message: issue)
            } else {
                Text("This is what your client sees on the \(DocumentText.noun(document.docType)).")
                    .font(Theme.Fonts.caption.weight(.regular))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        quantityAndPrice
        if model.chargesTax { rateSection }
        if model.chargesTax {
            SwitchRow(title: "My price already includes \(taxName)",
                      hintOn: "On: \(taxName) is taken out of your price.",
                      hintOff: "Off: we add \(taxName) on top of your price.",
                      isOn: Binding(get: { editor?.includesTax ?? false },
                                    set: { model.state.lineEditor?.includesTax = $0 }))
                .accessibilityIdentifier("lineIncludesTax")
        }
        if let preview = model.lineEditorPreview { lineTotal(preview) }
        if model.canSaveLineToItems {
            Toggle("Save to my items so I can reuse it", isOn: Binding(
                get: { editor?.saveToItems ?? false }, set: { model.state.lineEditor?.saveToItems = $0 }))
                .toggleStyle(CheckboxToggleStyle())
                .accessibilityIdentifier("lineSaveToItems")
        }
        details
    }

    @ViewBuilder private var quantityAndPrice: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                                                  : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "How many?")
                QuantityStepper(text: text(\.quantityText), decrement: { model.stepLineQuantity(by: -1) },
                                increment: { model.stepLineQuantity(by: 1) }, accessibilityName: "How many?")
                    .focused($focus, equals: .quantity)
                    .accessibilityIdentifier("lineQuantity")
                if let issue = message(.quantity, "quantity") { IssueText(message: issue) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "Price for one")
                HStack(spacing: 6) {
                    Text(currencySymbol).foregroundStyle(Theme.textSecondary)
                    TextField("Price for one", text: text(\.priceText).decimalPadInput(),
                              prompt: Text("0").foregroundStyle(Theme.textSecondary))
                        .keyboardType(.decimalPad)
                        .fontWeight(.semibold)
                        .focused($focus, equals: .price)
                        .accessibilityIdentifier("linePrice")
                }
                .inputBox(isFocused: focus == .price)
                if let issue = message(.price, "price") { IssueText(message: issue) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func lineTotal(_ preview: DocumentViewModel.LinePreview) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(preview.text)
                .font(Theme.Fonts.subhead)
                .foregroundStyle(Theme.tipOn)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(preview.total)
                .font(Theme.Fonts.title3.monospacedDigit())
                .foregroundStyle(Theme.tipOn)
        }
        .padding(.horizontal, Theme.Space.m + 2)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.tip, in: RoundedRectangle(cornerRadius: Theme.Radius.input))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Line total \(preview.total): \(preview.text)")
        .accessibilityIdentifier("lineTotal")
    }

    private var currencySymbol: String {
        session.dependencies.reference.currencies[document.currency]?.symbol ?? document.currency.rawValue
    }

    /// The rate chips, "Other rates" and the hint (`design/rate-chips.json`).
    private var rateSection: some View {
        let choices = model.lineRateChoices
        let selected = editor?.draft.rateId ?? ""
        let chips = choices.chips + choices.others.filter { $0.id == selected }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                FieldLabel(text: "\(taxName) rate")
                Spacer()
                if !choices.others.isEmpty {
                    Menu {
                        ForEach(choices.others) { rate in
                            Button(rate.label) { model.state.lineEditor?.draft.rateId = rate.id }
                        }
                    } label: {
                        Text("Other rates").font(Theme.Fonts.footnote.weight(.semibold))
                            .frame(minWidth: Theme.Layout.minTouchTarget, minHeight: Theme.Layout.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("lineOtherRates")
                }
            }
            if chips.count <= 4, !typeSize.isAccessibilitySize {
                HStack(spacing: Theme.Space.s) { rateChips(chips, selected: selected, fills: true) }
            } else {
                FlowLayout { rateChips(chips, selected: selected, fills: false) }
            }
            if let issue = message(.rate, "rate") {
                IssueText(message: issue)
            } else if let hint = choices.hint {
                Text(hint).font(Theme.Fonts.caption.weight(.regular)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func rateChips(_ rates: [TaxRate], selected: String, fills: Bool) -> some View {
        ForEach(rates) { rate in
            ChoiceChip(title: chipTitle(rate), isSelected: rate.id == selected, fillsWidth: fills) {
                model.state.lineEditor?.draft.rateId = rate.id
            }
            .accessibilityLabel(rate.label)
            .accessibilityIdentifier("rate-\(rate.id)")
        }
    }

    /// "18%" for a plain percent rate; the rate's label otherwise ("Exempt").
    private func chipTitle(_ rate: TaxRate) -> String {
        guard rate.category == .standard || rate.category == .reduced || rate.category == .zero,
              rate.components == nil, let percent = rate.percent else { return rate.label }
        return SpecFormatter.percent(percent)
    }

    /// Unit, product code and line discount, folded away unless they are needed or already set.
    @ViewBuilder private var details: some View {
        let needsCode = config.family == "IN" && model.state.client?.isBusiness == true && model.chargesTax
        let hasDetails = editor.map { !$0.draft.productCode.isEmpty || !$0.draft.discountText.isEmpty } ?? false
        let open = showsDetails || hasDetails
        if needsCode { productCodeField }
        Button {
            withAnimation(.snappy) { showsDetails.toggle() }
        } label: {
            HStack {
                Text(needsCode ? "Unit and discount" : "More details (unit, \(config.labels.productCodeName), discount)")
                    .font(Theme.Fonts.subhead.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.down").rotationEffect(.degrees(open ? 180 : 0))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.Layout.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(open ? "Shown" : "Hidden")
        .accessibilityIdentifier("lineMoreDetails")
        if open {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Picker(selection: Binding(get: { editor?.draft.unit },
                                          set: { model.state.lineEditor?.draft.unit = $0 })) {
                    Text("No unit").tag(String?.none)
                    ForEach(session.dependencies.reference.units) { unit in
                        Text(unit.label).tag(Optional(unit.id))
                    }
                } label: {
                    Text("Unit").font(Theme.Fonts.subhead.weight(.bold))
                }
                .pickerStyle(.menu)
                if !needsCode { productCodeField }
                discountField
            }
        }
    }

    private var discountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: "Discount on this item (optional)")
            HStack {
                TextField("Discount", text: text(\.discountText).decimalPadInput(),
                          prompt: Text("0").foregroundStyle(Theme.textSecondary))
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .discount)
                    .inputBox(isFocused: focus == .discount)
                Picker("Discount type", selection: Binding(
                    get: { editor?.draft.discountIsPercent ?? true },
                    set: { model.state.lineEditor?.draft.discountIsPercent = $0 }
                )) {
                    Text("%").tag(true)
                    Text(document.currency.rawValue).tag(false)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if let issue = message(.discount, "discount") { IssueText(message: issue) }
        }
    }

    private var productCodeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: "\(config.labels.productCodeName)\(config.family == "IN" ? "" : " (optional)")")
            TextField(config.labels.productCodeName, text: text(\.productCode),
                      prompt: Text(config.family == "IN" ? "998314" : "").foregroundStyle(Theme.textSecondary))
                .keyboardType(config.family == "IN" ? .numberPad : .default)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focus, equals: .productCode)
                .inputBox(isFocused: focus == .productCode)
            if let issue = message(.productCode, config.labels.productCodeName) {
                IssueText(message: issue)
            } else if config.family == "IN" {
                Text("The code for what you sold, printed on business invoices.")
                    .font(Theme.Fonts.caption.weight(.regular))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: Helpers

    /// Keeps the saved items current; the first time, opens "My saved items" when there are any.
    private func observeItems() async {
        if editor?.needsPrice == true { focus = .price }
        do {
            for try await latest in session.dependencies.catalog.observeItems(businessID: session.business.id) {
                items = latest
                if !tabChosen {
                    tabChosen = true
                    if isNew, editor?.needsPrice != true, latest.contains(where: { !$0.isArchived }) {
                        tab = .saved
                    } else if isNew {
                        focus = .description
                    }
                }
            }
        } catch {}
    }

    private func text(_ keyPath: WritableKeyPath<LineItemDraft, String>) -> Binding<String> {
        Binding(get: { editor?.draft[keyPath: keyPath] ?? "" },
                set: { model.state.lineEditor?.draft[keyPath: keyPath] = $0 })
    }

    private func message(_ field: LineItemField, _ name: String) -> String? {
        model.visibleLineIssue(field).map { IssueMessages.text($0, field: name) }
    }
}

/// A checkbox: a 20 pt rounded square, filled with brand and ticked when on.
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: Theme.Space.s + 2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(configuration.isOn ? Theme.brand : Theme.surface)
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(configuration.isOn ? Theme.brand : Theme.control, lineWidth: 2)
                    if configuration.isOn {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Theme.brandOn)
                    }
                }
                .frame(width: 20, height: 20)
                configuration.label
                    .font(Theme.Fonts.subhead)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: Theme.Layout.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
