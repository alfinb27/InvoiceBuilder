import Foundation
import InvoiceCore
import Observation

/// The item catalogue list.
@MainActor @Observable
final class CatalogListViewModel {
    struct State: Equatable {
        var items: [CatalogItem] = []
        var isLoading = true
        var errorMessage: String?
    }

    private(set) var state = State()
    private let session: Session

    init(session: Session) {
        self.session = session
    }

    func observe() async {
        do {
            for try await items in session.dependencies.catalog.observeItems(businessID: session.business.id) {
                state.items = items
                state.isLoading = false
            }
        } catch {
            state.errorMessage = "Your items couldn't be loaded."
        }
    }

    /// Search results (`spec/setup.md` §10): active items, or only archived ones.
    func visibleItems(query: String, archived: Bool) -> [CatalogItem] {
        SetupSearch.items(state.items.filter { $0.isArchived == archived }, matching: query)
    }

    func setArchived(_ archived: Bool, _ item: CatalogItem) async {
        do {
            try await session.dependencies.catalog.setArchived(archived, itemID: item.id)
            session.router.items.didRemove(item.id)
        } catch {
            state.errorMessage = "The item couldn't be \(archived ? "archived" : "restored")."
        }
    }

    func delete(_ item: CatalogItem) async {
        do {
            try await session.dependencies.catalog.delete(itemID: item.id)
            session.router.items.didRemove(item.id)
        } catch {
            state.errorMessage = "The item couldn't be deleted."
        }
    }

    func dismissError() { state.errorMessage = nil }
}

/// Creating or editing a catalogue item (`spec/setup.md` §10).
@MainActor @Observable
final class CatalogItemEditorViewModel {
    struct State: Equatable {
        var draft: CatalogItemDraft
        var original: CatalogItem?
        var isLoaded: Bool
        var attemptedSave = false
        var isSaving = false
        var errorMessage: String?
    }

    var state: State
    let route: EditorRoute
    private let session: Session

    init(session: Session, route: EditorRoute) {
        self.session = session
        self.route = route
        state = State(draft: CatalogItemDraft(), isLoaded: route == .new)
    }

    func load() async {
        guard case .edit(let id) = route, !state.isLoaded else { return }
        if let item = try? await session.dependencies.catalog.fetchItem(id: id) {
            state.original = item
            state.draft = CatalogItemDraft(item: item, exponent: rules.exponent)
        } else {
            state.errorMessage = "This item no longer exists."
        }
        state.isLoaded = true
    }

    var rules: CatalogItemRules { session.catalogRules }
    var isNew: Bool { route == .new }
    var issues: [CatalogItemField: FieldIssue] { rules.issues(state.draft) }

    func visibleIssue(_ field: CatalogItemField) -> FieldIssue? {
        state.attemptedSave ? issues[field] : nil
    }

    var rateChoices: [TaxRate] { rules.rateChoices(selected: state.draft.rateId) }

    /// The saved rate is no longer in force (e.g. GST 12% after 22 September 2025).
    var rateWarning: String? {
        guard let id = state.draft.rateId, !rules.isInForce(rateID: id) else { return nil }
        return "This rate isn't in force today. Choose a current rate."
    }

    /// "4 digits needed on B2B invoices" (IN), from the business's turnover tier.
    var productCodeHint: String? {
        guard let digits = rules.requiredProductCodeDigits else { return nil }
        switch (digits.b2b, digits.b2c) {
        case (0, 0): return nil
        case (let b2b, 0): return "At least \(b2b) digits needed on B2B invoices."
        case (let b2b, let b2c) where b2b == b2c: return "At least \(b2b) digits needed on every invoice."
        case (let b2b, let b2c): return "At least \(b2b) digits on B2B invoices, \(b2c) on others."
        }
    }

    var currencySymbol: String {
        session.dependencies.reference.currencies[rules.currency]?.symbol ?? rules.currency.rawValue
    }

    func save() async -> CatalogItem? {
        state.attemptedSave = true
        guard issues.isEmpty, state.isLoaded else { return nil }
        state.isSaving = true
        defer { state.isSaving = false }
        let dependencies = session.dependencies
        let item = if let original = state.original {
            rules.updating(original, from: state.draft)
        } else {
            rules.makeItem(from: state.draft, id: dependencies.ids.make(), now: dependencies.time.now())
        }
        do {
            let saved = try await dependencies.catalog.save(item)
            session.router.items.didSave(saved.id)
            return saved
        } catch {
            state.errorMessage = "The item couldn't be saved."
            return nil
        }
    }
}
