import InvoiceCore
import SwiftUI

/// New / edit item sheet (wireframe 7, `spec/setup.md` §10).
struct CatalogItemEditorView: View {
    let session: Session
    @State private var model: CatalogItemEditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(session: Session, route: EditorRoute) {
        self.session = session
        _model = State(initialValue: CatalogItemEditorViewModel(session: session, route: route))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.state.isLoaded {
                    CatalogItemForm(model: model, session: session)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(model.isNew ? "New item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.save() != nil { dismiss() }
                        }
                    }
                    .disabled(model.state.isSaving || !model.state.isLoaded)
                }
            }
            .task { await model.load() }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.state.errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(model.state.isSaving)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.state.errorMessage != nil }, set: { if !$0 { model.state.errorMessage = nil } })
    }
}

private struct CatalogItemForm: View {
    @Bindable var model: CatalogItemEditorViewModel
    let session: Session

    private var labels: TaxLabels { session.config.labels }

    var body: some View {
        ThemedForm {
            if model.state.attemptedSave, !model.issues.isEmpty {
                Section { IssueText(message: "Check the highlighted fields.") }
            }
            Section {
                FormTextField(title: "Name", text: $model.state.draft.name, prompt: "As it appears on invoices",
                              issue: message(.name, "name"))
                FormTextField(title: "Description (optional)", text: $model.state.draft.description, axis: .vertical)
                Picker("Type", selection: kindBinding) {
                    Text("Service").tag(ItemKind.service)
                    Text("Goods").tag(ItemKind.goods)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Item type")
            }

            Section("Price") {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Price per unit").font(Theme.Fonts.footnote).foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                    HStack(spacing: Theme.Space.xs) {
                        Text(model.currencySymbol).foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                        TextField("Price per unit", text: $model.state.draft.priceText.decimalPadInput(),
                                  prompt: Text("0.00"))
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                            .accessibilityLabel("Price per unit in \(model.rules.currency.rawValue)")
                    }
                    if let issue = message(.price, "price") { IssueText(message: issue) }
                }
                Picker("Unit", selection: $model.state.draft.unit) {
                    ForEach(session.dependencies.reference.units) { unit in
                        Text("\(unit.label) (\(unit.id))").tag(unit.id)
                    }
                }
                .pickerStyle(.navigationLink)
                if model.rules.showsInclusivePrice {
                    Toggle("Price includes \(labels.taxName)", isOn: $model.state.draft.priceIncludesTax)
                }
            }

            Section {
                Picker("Rate", selection: $model.state.draft.rateId) {
                    if model.state.draft.rateId == nil { Text("Choose").tag(String?.none) }
                    ForEach(model.rateChoices) { rate in
                        Text(rate.label).tag(Optional(rate.id))
                    }
                }
                .pickerStyle(.navigationLink)
                if let issue = message(.rate, "rate") { IssueText(message: issue) }
                if let warning = model.rateWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Fonts.footnote)
                        .foregroundStyle(Theme.warning)
                }
            } header: {
                Text(labels.taxName)
            } footer: {
                if !session.chargesTax {
                    Text("You don't charge \(labels.taxName) now, so this rate isn't applied. It's kept in case you register later.")
                }
            }

            Section {
                FormTextField(title: "\(labels.productCodeName) (optional)", text: $model.state.draft.productCode,
                              prompt: session.config.family == "IN" ? "e.g. 998314" : nil,
                              issue: message(.productCode, labels.productCodeName),
                              keyboard: session.config.family == "IN" ? .numberPad : .default,
                              capitalization: .characters, autocorrect: false)
            } footer: {
                if let hint = model.productCodeHint { Text(hint) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var kindBinding: Binding<ItemKind> {
        Binding(get: { model.state.draft.kind }, set: { model.state.draft.setKind($0) })
    }

    private func message(_ field: CatalogItemField, _ name: String) -> String? {
        model.visibleIssue(field).map { IssueMessages.text($0, field: name) }
    }
}
