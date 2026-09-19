import Observation

/// The app's sections: a tab bar on iPhone, a sidebar on iPad (`TabView` `.sidebarAdaptable`, ADR-0014).
public enum AppTab: String, Hashable, CaseIterable, Sendable {
    case home, clients, items, settings
}

/// All navigation state. It lives here, in long-lived objects, never in views, so it survives iPad window resizing
/// and compact ↔ regular size-class changes (ADR-0014, `ios/CLAUDE.md`).
@MainActor @Observable
public final class AppRouter {
    public var selectedTab: AppTab = .home
    public let clients = ListDetailRouter()
    public let items = ListDetailRouter()
    public let settings = SettingsRouter()

    public init() {}

    /// Home's quick actions.
    public func startNewClient() {
        selectedTab = .clients
        clients.editor = .new
    }

    public func startNewItem() {
        selectedTab = .items
        items.editor = .new
    }
}

/// A list/detail section (clients, items): the selected row, the open editor sheet and the list filters.
@MainActor @Observable
public final class ListDetailRouter {
    /// The row shown in the detail column (pushed on iPhone).
    public var selection: String?
    public var editor: EditorRoute?
    public var searchText = ""
    public var showArchived = false

    public init() {}

    public func edit(_ id: String) { editor = .edit(id) }

    /// After the editor saved: show what was saved.
    public func didSave(_ id: String) {
        editor = nil
        selection = id
    }

    /// After a delete or archive: stop showing a row that left the current list.
    public func didRemove(_ id: String) {
        if selection == id { selection = nil }
    }
}

public enum EditorRoute: Identifiable, Hashable, Sendable {
    case new
    case edit(String)

    public var id: String {
        switch self {
        case .new: "new"
        case .edit(let id): "edit-\(id)"
        }
    }
}

public enum SettingsPage: String, Hashable, CaseIterable, Sendable {
    case profile, images, numbering, defaults, taxRates, about
}

@MainActor @Observable
public final class SettingsRouter {
    public var selection: SettingsPage?

    public init() {}
}
