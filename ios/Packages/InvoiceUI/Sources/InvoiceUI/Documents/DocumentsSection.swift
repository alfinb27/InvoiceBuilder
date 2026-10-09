import InvoiceCore
import Observation
import SwiftUI

/// The documents list: every live draft and issued document of the business.
@MainActor @Observable
final class DocumentListViewModel {
    struct State: Equatable {
        var documents: [DocumentSummary] = []
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
            for try await documents in session.dependencies.documents.observeDocuments(
                businessID: session.business.id) {
                state.documents = documents
                state.isLoading = false
            }
        } catch {
            state.errorMessage = "Your invoices couldn't be loaded."
        }
    }

    /// Drafts and issued documents of one type matching the search (client name or number), the date range and,
    /// for invoices, the status segment. Drafts ignore the status filter (they have their own section) but not the
    /// search or date range.
    func visible(docType: DocumentType, query: String, statusFilter: InvoiceStatusFilter,
                dateFilter: DocumentDateFilter, today: LocalDate) -> (drafts: [DocumentSummary], issued: [DocumentSummary]) {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let from = dateFilter.from(today: today)
        let rows = state.documents.filter { summary in
            summary.docType == docType
                && (needle.isEmpty
                    || summary.buyerName?.range(of: needle, options: .caseInsensitive) != nil
                    || summary.number?.range(of: needle, options: .caseInsensitive) != nil)
                && (from == nil || summary.issueDate >= from!)
        }
        let issued = rows.filter { $0.lifecycle != .draft }
        let filteredIssued = docType == .invoice
            ? issued.filter { statusFilter.matches($0.status(today: today)) }
            : issued
        return (rows.filter { $0.lifecycle == .draft }, filteredIssued)
    }

    func deleteDraft(_ summary: DocumentSummary) async {
        do {
            try await session.dependencies.documentService.deleteDraft(documentID: summary.id)
            session.router.documents.didRemove(summary.id)
        } catch {
            state.errorMessage = "The draft couldn't be deleted."
        }
    }

    func duplicate(_ summary: DocumentSummary) async {
        do {
            let copy = try await session.dependencies.documentService.duplicate(documentID: summary.id)
            session.router.documents.open(copy.id)
        } catch {
            state.errorMessage = "The \(DocumentText.noun(summary.docType)) couldn't be duplicated."
        }
    }

    func dismissError() { state.errorMessage = nil }

    /// Tests fill the list directly (performance tests with 1,000 rows).
    func replaceForTesting(_ documents: [DocumentSummary]) {
        state.documents = documents
        state.isLoading = false
    }
}

/// The Invoices tab: invoices or quotes on the left, the builder or the issued document on the right (pushed on
/// iPhone). Navigation state lives in `session.router.documents`.
struct DocumentsSection: View {
    let session: Session
    @State private var list: DocumentListViewModel

    init(session: Session) {
        self.session = session
        _list = State(initialValue: DocumentListViewModel(session: session))
    }

    var body: some View {
        @Bindable var router = session.router.documents
        NavigationSplitView {
            DocumentList(model: list, router: router, session: session)
                .navigationTitle(router.docType == .quote ? "Quotes" : "Invoices")
        } detail: {
            if let route = router.selection {
                DocumentScreen(session: session, route: route)
                    .id(route.id)
            } else {
                ContentUnavailableView("Select an invoice", systemImage: "doc.text",
                                       description: Text("Or create one with New invoice."))
            }
        }
        .task { await list.observe() }
    }
}

private struct DocumentList: View {
    let model: DocumentListViewModel
    @Bindable var router: DocumentsRouter
    let session: Session
    @State private var pendingDelete: DocumentSummary?
    @FocusState private var searchFocused: Bool

    var body: some View {
        let rows = model.visible(docType: router.docType, query: router.searchText, statusFilter: router.statusFilter,
                                 dateFilter: router.dateFilter, today: session.today)
        List(selection: selection) {
            if !rows.drafts.isEmpty {
                Section("Drafts") {
                    ForEach(rows.drafts) { row($0) }
                }
            }
            if !rows.issued.isEmpty {
                Section(router.docType == .quote ? "Quotes" : "Issued") {
                    ForEach(rows.issued) { row($0) }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: Theme.Space.s) {
                Picker("Show", selection: $router.docType) {
                    Text("Invoices").tag(DocumentType.invoice)
                    Text("Quotes").tag(DocumentType.quote)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("documentTypePicker")
                if router.docType == .invoice {
                    Picker("Status", selection: $router.statusFilter) {
                        ForEach(InvoiceStatusFilter.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("invoiceStatusFilter")
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
            .background(.bar)
        }
        .overlay {
            if model.state.isLoading {
                ProgressView()
            } else if rows.drafts.isEmpty, rows.issued.isEmpty {
                emptyState
            }
        }
        .searchable(text: $router.searchText, prompt: "Client or number")
        .searchFocused($searchFocused)
        .onChange(of: router.isSearchFocused, initial: true) { _, wanted in
            // ⌘F asks through the router (the command has no view to focus); the field takes it from there.
            guard wanted else { return }
            searchFocused = true
            router.isSearchFocused = false
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New invoice", systemImage: "doc.badge.plus") { session.startNewDocument(.invoice) }
                    Button("New quote", systemImage: "doc.text.magnifyingglass") { session.startNewDocument(.quote) }
                } label: {
                    Label("New", systemImage: "plus")
                } primaryAction: {
                    session.startNewDocument(router.docType)
                }
                .accessibilityIdentifier("newDocument")
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Picker("Date range", selection: $router.dateFilter) {
                        ForEach(DocumentDateFilter.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label("Date range", systemImage: "calendar")
                }
                .accessibilityIdentifier("documentDateFilter")
            }
        }
        .confirmationDialog("Delete this draft?", isPresented: deleteBinding, titleVisibility: .visible,
                            presenting: pendingDelete) { summary in
            Button("Delete draft", role: .destructive) { Task { await model.deleteDraft(summary) } }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.state.errorMessage ?? "")
        }
    }

    private func row(_ summary: DocumentSummary) -> some View {
        NavigationLink(value: summary.id) {
            DocumentRow(summary: summary, session: session)
        }
        .swipeActions(edge: .trailing) {
            if summary.lifecycle == .draft {
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = summary }
            }
        }
        .contextMenu {
            Button("Duplicate", systemImage: "plus.square.on.square") { Task { await model.duplicate(summary) } }
            if summary.lifecycle != .draft {
                Button("Share", systemImage: "square.and.arrow.up") { router.open(summary.id, then: .share) }
            }
            if summary.docType == .invoice, summary.lifecycle == .issued,
               summary.status(today: session.today) != .paid {
                Button("Record payment", systemImage: "banknote") { router.open(summary.id, then: .recordPayment) }
            }
            if summary.lifecycle == .issued {
                Button("Void", systemImage: "nosign", role: .destructive) { router.open(summary.id, then: .void) }
            }
            if summary.lifecycle == .draft {
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = summary }
            }
        }
    }

    /// The list highlights the open document, including a new draft once it has been saved.
    private var selection: Binding<String?> {
        Binding(get: { router.selection?.id }, set: { id in router.selection = id.map(DocumentRoute.existing) })
    }

    @ViewBuilder private var emptyState: some View {
        let noun = DocumentText.noun(router.docType)
        if !router.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: router.searchText)
        } else if router.statusFilter != .all || router.dateFilter != .allTime,
                  model.state.documents.contains(where: { $0.docType == router.docType }) {
            ContentUnavailableView("No matching \(noun)s", systemImage: "line.3.horizontal.decrease.circle",
                                   description: Text("Try a different status or date range."))
        } else {
            ContentUnavailableView {
                Label("No \(noun)s yet", systemImage: "doc.text")
            } description: {
                Text(router.docType == .quote ? "Quotes you send appear here. Convert one to an invoice when it's accepted."
                                              : "Create an invoice: pick a client, add items and issue it.")
            } actions: {
                Button("New \(noun)") { session.startNewDocument(router.docType) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.state.errorMessage != nil }, set: { if !$0 { model.dismissError() } })
    }
}

private struct DocumentRow: View {
    let summary: DocumentSummary
    let session: Session

    var body: some View {
        AdaptiveRow {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                // Hierarchical styles, so the text stays readable on a selected (highlighted) row.
                Text(summary.number ?? "Draft")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(summary.number == nil ? .secondary : .primary)
                Text(summary.buyerName ?? "No client").font(.subheadline).foregroundStyle(.secondary)
                Text(summary.issueDate.displayText).font(.caption).foregroundStyle(.tertiary)
            }
        } value: {
            VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                Text(session.money(summary.totalMinor, currency: summary.currency)).monospacedDigit()
                StatusTag(status: summary.status(today: session.today))
            }
        }
        .padding(.vertical, Theme.Space.xxs)
        .accessibilityElement(children: .combine)
    }
}
