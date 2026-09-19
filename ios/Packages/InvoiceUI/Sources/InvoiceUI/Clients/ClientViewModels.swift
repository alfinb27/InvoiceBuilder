import Foundation
import InvoiceCore
import Observation

/// The client list: every live client of the business, filtered by the router's search text and archive toggle.
@MainActor @Observable
final class ClientListViewModel {
    struct State: Equatable {
        var clients: [Client] = []
        var isLoading = true
        var errorMessage: String?
    }

    private(set) var state = State()
    private let session: Session

    init(session: Session) {
        self.session = session
    }

    /// Streams the business's clients until the view disappears.
    func observe() async {
        do {
            for try await clients in session.dependencies.clients.observeClients(businessID: session.business.id) {
                state.clients = clients
                state.isLoading = false
            }
        } catch {
            state.errorMessage = "Your clients couldn't be loaded."
        }
    }

    /// Search results (`spec/setup.md` §5): active clients, or only archived ones.
    func visibleClients(query: String, archived: Bool) -> [Client] {
        SetupSearch.clients(state.clients.filter { $0.isArchived == archived }, matching: query)
    }

    var hasArchived: Bool { state.clients.contains(where: \.isArchived) }

    func setArchived(_ archived: Bool, _ client: Client) async {
        do {
            try await session.dependencies.clients.setArchived(archived, clientID: client.id)
            session.router.clients.didRemove(client.id)
        } catch {
            state.errorMessage = "The client couldn't be \(archived ? "archived" : "restored")."
        }
    }

    func delete(_ client: Client) async {
        do {
            try await session.dependencies.clients.delete(clientID: client.id)
            session.router.clients.didRemove(client.id)
        } catch {
            state.errorMessage = "The client couldn't be deleted."
        }
    }

    func dismissError() { state.errorMessage = nil }
}

/// Creating or editing a client (`spec/setup.md` §5).
@MainActor @Observable
final class ClientEditorViewModel {
    struct State: Equatable {
        var draft: ClientDraft
        /// The stored client being edited; nil for a new one.
        var original: Client?
        /// False until an edited client has been read from the database.
        var isLoaded: Bool
        /// Save was pressed: every problem is shown, not only live tax ID feedback.
        var attemptedSave = false
        var isSaving = false
        var errorMessage: String?
        var otherClients: [Client] = []
    }

    var state: State
    let route: EditorRoute
    private let session: Session

    init(session: Session, route: EditorRoute) {
        self.session = session
        self.route = route
        state = State(draft: ClientDraft(countryCode: session.business.countryCode), isLoaded: route == .new)
    }

    /// Reads the client being edited and the other clients (for the duplicate tax ID warning).
    func load() async {
        let dependencies = session.dependencies
        let others = try? await firstValue(dependencies.clients.observeClients(businessID: session.business.id))
        state.otherClients = others ?? []
        if case .edit(let id) = route, !state.isLoaded {
            if let client = try? await dependencies.clients.fetchClient(id: id) {
                state.original = client
                state.draft = ClientDraft(client: client)
            } else {
                state.errorMessage = "This client no longer exists."
            }
            state.isLoaded = true
        }
    }

    var rules: ClientRules { session.clientRules }
    var isNew: Bool { route == .new }
    var issues: [ClientField: FieldIssue] { rules.issues(state.draft) }

    func visibleIssue(_ field: ClientField) -> FieldIssue? {
        state.attemptedSave ? issues[field] : nil
    }

    var taxIDFeedback: TaxIDFeedback? {
        guard let validation = rules.taxIDValidation(state.draft) else { return nil }
        if validation.valid {
            return .valid(validation.region.flatMap { session.config.region($0)?.name })
        }
        guard state.attemptedSave || validation.normalized.count >= 15, let error = validation.error else { return nil }
        let name = session.config.labels.taxIdName
        return .invalid(IssueMessages.text(.invalidTaxID(error), field: name, taxIDName: name))
    }

    var duplicate: Client? {
        rules.duplicate(of: state.draft, editingID: state.original?.id, among: state.otherClients)
    }

    /// Saves and returns the stored client; nil when a problem blocks saving.
    func save() async -> Client? {
        state.attemptedSave = true
        guard issues.isEmpty, state.isLoaded else { return nil }
        state.isSaving = true
        defer { state.isSaving = false }
        let dependencies = session.dependencies
        let client = if let original = state.original {
            rules.updating(original, from: state.draft)
        } else {
            rules.makeClient(from: state.draft, id: dependencies.ids.make(), businessID: session.business.id,
                             now: dependencies.time.now())
        }
        do {
            let saved = try await dependencies.clients.save(client)
            session.router.clients.didSave(saved.id)
            return saved
        } catch {
            state.errorMessage = "The client couldn't be saved."
            return nil
        }
    }
}

/// The first element of a stream (a one-off read through an observation).
func firstValue<Element: Sendable>(_ stream: AsyncThrowingStream<Element, any Error>) async throws -> Element? {
    for try await value in stream { return value }
    return nil
}
