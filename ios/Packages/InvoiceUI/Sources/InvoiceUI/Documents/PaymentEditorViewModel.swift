import Foundation
import InvoiceCore
import Observation

/// A payment being typed: plain text fields, validated live (`spec/documents.md` §10, typed input per
/// `spec/setup.md` §11).
struct PaymentDraft: Equatable {
    var amountText = ""
    var date: LocalDate
    var method: PaymentMethod = .cash
    var reference = ""
    var note = ""
}

/// Recording a payment against an issued invoice. There is no edit: a correction is delete-and-re-add
/// (`spec/documents.md` §10), so this view model only ever records a new one.
@MainActor @Observable
final class PaymentEditorViewModel {
    struct State: Equatable {
        var draft: PaymentDraft
        var attemptedSave = false
        var isSaving = false
        var errorMessage: String?
    }

    var state: State
    let documentID: String
    let currency: CurrencyCode
    private let session: Session

    init(session: Session, documentID: String, currency: CurrencyCode) {
        self.session = session
        self.documentID = documentID
        self.currency = currency
        state = State(draft: PaymentDraft(date: session.today))
    }

    private var exponent: Int { session.dependencies.reference.currencies.exponent(of: currency) }

    var amountIssue: FieldIssue? {
        if case .failure(let issue) = DocumentInput.paymentAmount(state.draft.amountText, exponent: exponent) {
            return issue
        }
        return nil
    }

    func visibleAmountIssue() -> FieldIssue? { state.attemptedSave ? amountIssue : nil }

    /// Saves and returns the recorded payment; nil when a problem blocks saving.
    func save() async -> Payment? {
        state.attemptedSave = true
        guard case .success(let amountMinor) = DocumentInput.paymentAmount(state.draft.amountText, exponent: exponent)
        else { return nil }
        state.isSaving = true
        defer { state.isSaving = false }
        do {
            return try await session.dependencies.paymentService.recordPayment(
                documentID: documentID, amountMinor: amountMinor, date: state.draft.date,
                method: state.draft.method, reference: state.draft.reference.trimmedOrNil,
                note: state.draft.note.trimmedOrNil)
        } catch {
            state.errorMessage = "The payment couldn't be recorded."
            return nil
        }
    }
}
