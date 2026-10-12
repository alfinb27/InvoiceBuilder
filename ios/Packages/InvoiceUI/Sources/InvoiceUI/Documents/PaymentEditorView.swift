import InvoiceCore
import SwiftUI

/// Record a payment sheet (`spec/documents.md` §10).
struct PaymentEditorView: View {
    let session: Session
    let documentID: String
    let currency: CurrencyCode
    var onSaved: (Payment) -> Void
    @State private var model: PaymentEditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(session: Session, documentID: String, currency: CurrencyCode, onSaved: @escaping (Payment) -> Void) {
        self.session = session
        self.documentID = documentID
        self.currency = currency
        self.onSaved = onSaved
        _model = State(initialValue: PaymentEditorViewModel(session: session, documentID: documentID,
                                                             currency: currency))
    }

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        LabeledContent("Amount") {
                            TextField("0", text: Binding(
                                get: { model.state.draft.amountText },
                                set: { model.state.draft.amountText = DecimalPadText.normalized($0) }))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("paymentAmountField")
                        }
                        if let issue = model.visibleAmountIssue() {
                            IssueText(message: IssueMessages.text(issue, field: "amount"))
                        }
                    }
                    DatePicker("Date", selection: Binding(get: { model.state.draft.date.date },
                                                          set: { model.state.draft.date = LocalDate(date: $0) }),
                              displayedComponents: .date)
                    Picker("Method", selection: Binding(get: { model.state.draft.method },
                                                        set: { model.state.draft.method = $0 })) {
                        ForEach(PaymentMethodText.all, id: \.self) { Text(PaymentMethodText.label($0)).tag($0) }
                    }
                }
                Section {
                    TextField("Reference (optional)", text: Binding(get: { model.state.draft.reference },
                                                                     set: { model.state.draft.reference = $0 }))
                    TextField("Note (optional)", text: Binding(get: { model.state.draft.note },
                                                                set: { model.state.draft.note = $0 }))
                }
            }
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if let saved = await model.save() {
                                onSaved(saved)
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.state.isSaving)
                    .accessibilityIdentifier("savePayment")
                }
            }
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
