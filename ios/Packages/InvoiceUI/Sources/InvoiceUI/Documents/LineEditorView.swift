import InvoiceCore
import SwiftUI

/// Editing one line (`spec/documents.md` §3): a popover on iPad, a sheet on iPhone. Done applies it; an invalid line
/// shows its problems instead.
struct LineEditorView: View {
    @Bindable var model: DocumentViewModel
    let session: Session
    @FocusState private var focus: LineItemField?

    private var editor: DocumentViewModel.LineEditorState? { model.state.lineEditor }
    private var document: InvoiceCore.Document { model.state.document }
    private var config: TaxConfig { model.config }

    var body: some View {
        NavigationStack {
            Form {
                if editor?.needsPrice == true {
                    Section {
                        Label("Enter the price in \(document.currency.rawValue): there's no exchange rate to convert the item's price.",
                              systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.info)
                    }
                }
                Section {
                    FormTextField(title: "Description", text: text(\.description), prompt: "What you're charging for",
                                  issue: message(.description, "description"))
                        .focused($focus, equals: .description)
                        .submitLabel(.next)
                        .onSubmit { focus = .quantity }
                        .accessibilityIdentifier("lineDescription")
                    HStack(alignment: .top) {
                        FormTextField(title: "Quantity", text: text(\.quantityText),
                                      issue: message(.quantity, "quantity"), keyboard: .decimalPad)
                            .focused($focus, equals: .quantity)
                            .accessibilityIdentifier("lineQuantity")
                        Picker("Unit", selection: unitBinding) {
                            Text("No unit").tag(String?.none)
                            ForEach(session.dependencies.reference.units) { unit in
                                Text(unit.label).tag(Optional(unit.id))
                            }
                        }
                        .labelsHidden()
                    }
                    FormTextField(title: priceTitle, text: text(\.priceText), prompt: "0.00",
                                  issue: message(.price, "price"), keyboard: .decimalPad)
                        .focused($focus, equals: .price)
                        .accessibilityIdentifier("linePrice")
                    discountRow
                }
                if model.chargesTax {
                    Section {
                        Picker("\(config.labels.taxName) rate", selection: text(\.rateId)) {
                            if editor?.draft.rateId.isEmpty ?? true { Text("Choose").tag("") }
                            ForEach(model.rateChoices(selected: editor?.draft.rateId)) { rate in
                                Text(rate.label).tag(rate.id)
                            }
                        }
                        .accessibilityIdentifier("lineRate")
                        if let issue = message(.rate, "rate") { IssueText(message: issue) }
                    }
                }
                Section {
                    FormTextField(title: "\(config.labels.productCodeName) (optional)", text: text(\.productCode),
                                  issue: message(.productCode, config.labels.productCodeName),
                                  keyboard: config.family == "IN" ? .numberPad : .default, capitalization: .characters,
                                  autocorrect: false)
                }
                if editor?.isNew == false, let lineID = editor?.lineID {
                    Section {
                        Button("Duplicate line", systemImage: "plus.square.on.square") {
                            if model.commitLineEditor() { model.duplicateLine(lineID) }
                        }
                        Button("Delete line", systemImage: "trash", role: .destructive) {
                            model.cancelLineEditor()
                            model.deleteLine(lineID)
                        }
                    }
                }
            }
            .navigationTitle(editor?.isNew == true ? "New line" : "Edit line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancelLineEditor() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // ⌘↩, not plain Return: Return moves between the fields (Description → Quantity → …), and
                    // binding it here would close the line from the first field on some iOS versions.
                    Button("Done") { model.commitLineEditor() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("lineDone")
                }
            }
            .onAppear {
                if editor?.isNew == true || editor?.needsPrice == true {
                    focus = editor?.needsPrice == true ? .price : .description
                }
            }
        }
        .frame(minWidth: 340, idealWidth: 420, minHeight: 460, idealHeight: 560)
        .interactiveDismissDisabled(false)
    }

    private var discountRow: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack {
                TextField("Line discount (optional)", text: text(\.discountText).decimalPadInput())
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .discount)
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

    private var priceTitle: String {
        let basis = model.chargesTax ? (document.pricesIncludeTax ? " incl. \(config.labels.taxName)"
                                                                  : " excl. \(config.labels.taxName)") : ""
        return "Price (\(document.currency.rawValue))" + basis
    }

    private var unitBinding: Binding<String?> {
        Binding(get: { editor?.draft.unit }, set: { model.state.lineEditor?.draft.unit = $0 })
    }

    private func text(_ keyPath: WritableKeyPath<LineItemDraft, String>) -> Binding<String> {
        Binding(get: { editor?.draft[keyPath: keyPath] ?? "" },
                set: { model.state.lineEditor?.draft[keyPath: keyPath] = $0 })
    }

    private func message(_ field: LineItemField, _ name: String) -> String? {
        model.visibleLineIssue(field).map { IssueMessages.text($0, field: name) }
    }
}
