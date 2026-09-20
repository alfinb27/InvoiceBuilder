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

    /// Drafts and issued documents of one type matching the search (client name or number).
    func visible(docType: DocumentType, query: String) -> (drafts: [DocumentSummary], issued: [DocumentSummary]) {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = state.documents.filter { summary in
            summary.docType == docType && (needle.isEmpty
                || summary.buyerName?.range(of: needle, options: .caseInsensitive) != nil
                || summary.number?.range(of: needle, options: .caseInsensitive) != nil)
        }
        return (rows.filter { $0.lifecycle == .draft }, rows.filter { $0.lifecycle != .draft })
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

    var body: some View {
        let rows = model.visible(docType: router.docType, query: router.searchText)
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
            Picker("Show", selection: $router.docType) {
                Text("Invoices").tag(DocumentType.invoice)
                Text("Quotes").tag(DocumentType.quote)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
            .background(.bar)
            .accessibilityIdentifier("documentTypePicker")
        }
        .overlay {
            if model.state.isLoading {
                ProgressView()
            } else if rows.drafts.isEmpty, rows.issued.isEmpty {
                emptyState
            }
        }
        .searchable(text: $router.searchText, prompt: "Client or number")
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
