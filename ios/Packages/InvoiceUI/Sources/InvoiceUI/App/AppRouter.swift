import InvoiceCore
import Observation

/// The app's sections: a tab bar on iPhone, a sidebar on iPad (`TabView` `.sidebarAdaptable`, ADR-0014).
public enum AppTab: String, Hashable, CaseIterable, Sendable {
    case home, documents, clients, items, settings
}

/// All navigation state. It lives here, in long-lived objects, never in views, so it survives iPad window resizing
/// and compact ↔ regular size-class changes (ADR-0014, `ios/CLAUDE.md`).
@MainActor @Observable
public final class AppRouter {
    public var selectedTab: AppTab = .home
    public let documents = DocumentsRouter()
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

/// The Invoices tab: which type the list shows, the open document and the search text.
@MainActor @Observable
public final class DocumentsRouter {
    public var docType: DocumentType = .invoice
    /// The document in the detail column (pushed on iPhone).
    public var selection: DocumentRoute?
    public var searchText = ""
    /// Meaningful for invoices only; quotes ignore it.
    public var statusFilter: InvoiceStatusFilter = .all
    public var dateFilter: DocumentDateFilter = .allTime

    public init() {}

    public func open(_ id: String) { selection = .existing(id) }

    /// After a draft was deleted: stop showing it.
    public func didRemove(_ id: String) {
        if selection?.id == id { selection = nil }
    }
}

/// The Invoices list's status segments (`docs/plan.md` Phase 4: "All / Unpaid / Overdue / Paid").
public enum InvoiceStatusFilter: String, CaseIterable, Hashable, Sendable {
    case all, unpaid, overdue, paid

    public var label: String {
        switch self {
        case .all: "All"
        case .unpaid: "Unpaid"
        case .overdue: "Overdue"
        case .paid: "Paid"
        }
    }

    /// True when an issued invoice's derived status belongs in this segment.
    public func matches(_ status: DocumentStatus) -> Bool {
        switch self {
        case .all: true
        case .unpaid: status == .issued || status == .sent || status == .partiallyPaid || status == .overdue
        case .overdue: status == .overdue
        case .paid: status == .paid
        }
    }
}

/// A quick date-range filter on `issueDate` for the Invoices/Quotes list.
public enum DocumentDateFilter: String, CaseIterable, Hashable, Sendable {
    case allTime, thisMonth, last30Days, last3Months

    public var label: String {
        switch self {
        case .allTime: "All time"
        case .thisMonth: "This month"
        case .last30Days: "Last 30 days"
        case .last3Months: "Last 3 months"
        }
    }

    /// The inclusive lower bound for `issueDate`, or nil for no lower bound.
    public func from(today: LocalDate) -> LocalDate? {
        switch self {
        case .allTime: nil
        case .thisMonth: LocalDate(year: today.year, month: today.month, day: 1) ?? today
        case .last30Days: today.adding(days: -30)
        case .last3Months: today.adding(days: -90)
        }
    }
}

/// A document in the detail column: a stored one, or a new draft that is written on its first change.
public enum DocumentRoute: Identifiable, Hashable, Sendable {
    case new(DocumentType, id: String)
    case existing(String)

    public var id: String {
        switch self {
        case .new(_, let id), .existing(let id): id
        }
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
