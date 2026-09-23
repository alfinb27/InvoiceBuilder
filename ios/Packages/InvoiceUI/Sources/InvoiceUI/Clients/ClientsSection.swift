import InvoiceCore
import SwiftUI

/// The Clients tab: list and detail side by side on iPad, a stack on iPhone (wireframe 6). Selection, search and
/// the open editor live in `session.router.clients`.
struct ClientsSection: View {
    let session: Session
    @State private var list: ClientListViewModel

    init(session: Session) {
        self.session = session
        _list = State(initialValue: ClientListViewModel(session: session))
    }

    var body: some View {
        @Bindable var router = session.router.clients
        NavigationSplitView {
            ClientList(model: list, router: router, session: session)
                .navigationTitle("Clients")
        } detail: {
            if let id = router.selection {
                ClientDetailView(session: session, clientID: id)
                    .id(id)
            } else {
                ContentUnavailableView("Select a client", systemImage: "person.2",
                                       description: Text("Their details appear here."))
            }
        }
        .sheet(item: $router.editor) { route in
            ClientEditorView(session: session, route: route)
        }
        .task { await list.observe() }
    }
}

private struct ClientList: View {
    let model: ClientListViewModel
    @Bindable var router: ListDetailRouter
    let session: Session
    @State private var pendingDelete: Client?

    var body: some View {
        let clients = model.visibleClients(query: router.searchText, archived: router.showArchived)
        List(selection: $router.selection) {
            ForEach(clients) { client in
                NavigationLink(value: client.id) {
                    ClientRow(client: client, session: session)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = client }
                    archiveButton(client).tint(Theme.warning)
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { router.edit(client.id) }
                    archiveButton(client)
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = client }
                }
            }
        }
        .overlay {
            if model.state.isLoading {
                ProgressView()
            } else if clients.isEmpty {
                emptyState
            }
        }
        .searchable(text: $router.searchText, prompt: "Name, \(session.config.labels.taxIdName), email or phone")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add client", systemImage: "plus") { router.editor = .new }
            }
            ToolbarItem(placement: .secondaryAction) {
                Toggle("Show archived", systemImage: "archivebox", isOn: $router.showArchived)
            }
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "client")?", isPresented: deleteBinding,
                            titleVisibility: .visible, presenting: pendingDelete) { client in
            Button("Delete", role: .destructive) { Task { await model.delete(client) } }
        } message: { _ in
            Text("Invoices already sent to this client keep their details.")
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.state.errorMessage ?? "")
        }
    }

    private func archiveButton(_ client: Client) -> some View {
        Button(client.isArchived ? "Restore" : "Archive",
               systemImage: client.isArchived ? "tray.and.arrow.up" : "archivebox") {
            Task { await model.setArchived(!client.isArchived, client) }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !router.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: router.searchText)
        } else if router.showArchived {
            ContentUnavailableView("No archived clients", systemImage: "archivebox",
                                   description: Text("Archived clients are hidden from pickers but kept for old invoices."))
        } else {
            ContentUnavailableView {
                Label("No clients yet", systemImage: "person.2")
            } description: {
                Text("Add the people and businesses you invoice.")
            } actions: {
                Button("Add client") { router.editor = .new }
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

private struct ClientRow: View {
    let client: Client
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(spacing: Theme.Space.s) {
                Text(client.name).font(.body).foregroundStyle(.primary)
                if client.isBusiness { Tag(text: "B2B") }
            }
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, Theme.Space.xxs)
        .accessibilityElement(children: .combine)
    }

    /// `GSTIN 29AABCR1234C1ZU`; a foreign client's country (and tax ID); else the state or city.
    private var detail: String? {
        if client.countryCode != session.business.countryCode {
            return [session.countryName(client.countryCode), client.taxId].compactMap { $0 }.joined(separator: " · ")
        }
        if let taxId = client.taxId { return "\(session.config.labels.taxIdName) \(taxId)" }
        return session.regionName(client.regionCode) ?? client.billingAddress?.city
    }
}

/// A client's details (read-only); Edit opens the editor sheet.
struct ClientDetailView: View {
    let session: Session
    let clientID: String
    @State private var client: Client?
    @State private var documents: [DocumentSummary] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if let client {
                ClientDetailContent(client: client, documents: documents, session: session)
            } else if loaded {
                ContentUnavailableView("Client not found", systemImage: "person.crop.circle.badge.questionmark")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(client?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if client != nil {
                Button("Edit") { session.router.clients.edit(clientID) }
            }
        }
        .task(id: clientID) {
            async let clientTask: Void = loadClient()
            async let documentsTask: Void = loadDocuments()
            _ = await (clientTask, documentsTask)
        }
    }

    private func loadClient() async {
        do {
            for try await latest in session.dependencies.clients.observeClient(id: clientID) {
                client = latest
                loaded = true
            }
        } catch {
            loaded = true
        }
    }

    /// Client-side filter, matching how the Invoices tab already loads the business's documents in one stream.
    private func loadDocuments() async {
        do {
            for try await all in session.dependencies.documents.observeDocuments(businessID: session.business.id) {
                documents = all.filter { $0.clientId == clientID }
            }
        } catch {}
    }
}

private struct ClientDetailContent: View {
    let client: Client
    let documents: [DocumentSummary]
    let session: Session

    private var outstandingByCurrency: [(currency: CurrencyCode, minor: Int64)] {
        documents.outstandingByCurrency(today: session.today)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(client.name).font(.title2.weight(.semibold))
                    HStack {
                        Tag(text: client.isBusiness ? "Business (B2B)" : "Consumer (B2C)")
                        if client.isArchived { Tag(text: "Archived", color: Theme.textSecondary) }
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }
            Section("Tax") {
                if let taxId = client.taxId {
                    LabeledContent(client.countryCode == session.business.countryCode
                                   ? session.config.labels.taxIdName : "Tax ID", value: taxId)
                        .textSelection(.enabled)
                }
                if let region = session.regionName(client.regionCode) {
                    LabeledContent(session.config.labels.regionName ?? "State", value: region)
                }
                LabeledContent("Country", value: session.countryName(client.countryCode))
                LabeledContent("Currency", value: (client.defaultCurrency ?? session.business.homeCurrency).rawValue)
            }
            if client.contactName != nil || client.email != nil || client.phone != nil {
                Section("Contact") {
                    if let name = client.contactName { LabeledContent("Contact", value: name) }
                    if let email = client.email { LabeledContent("Email", value: email).textSelection(.enabled) }
                    if let phone = client.phone { LabeledContent("Phone", value: phone).textSelection(.enabled) }
                }
            }
            if let billing = client.billingAddress {
                Section("Billing address") { AddressText(address: billing, session: session) }
            }
            if let shipping = client.shippingAddress {
                Section("Shipping address") { AddressText(address: shipping, session: session) }
            }
            if let notes = client.notes {
                Section("Notes") { Text(notes) }
            }
            if !outstandingByCurrency.isEmpty {
                Section("Outstanding") {
                    ForEach(outstandingByCurrency, id: \.currency) { entry in
                        LabeledContent(entry.currency.rawValue, value: session.money(entry.minor, currency: entry.currency))
                            .monospacedDigit()
                    }
                }
            }
            Section {
                if documents.isEmpty {
                    Text("Invoices and quotes for this client will appear here.")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(documents) { document in
                        Button { session.openDocument(document.id, docType: document.docType) } label: {
                            ClientDocumentRow(summary: document, session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Documents")
            }
        }
    }
}

private struct ClientDocumentRow: View {
    let summary: DocumentSummary
    let session: Session

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(summary.number ?? "Draft \(DocumentText.noun(summary.docType))")
                    .foregroundStyle(summary.number == nil ? .secondary : .primary)
                Text(summary.issueDate.displayText).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                Text(session.money(summary.totalMinor, currency: summary.currency)).monospacedDigit()
                StatusTag(status: summary.status(today: session.today))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A multi-line postal address.
struct AddressText: View {
    let address: Address
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(address.line1)
            if let line2 = address.line2 { Text(line2) }
            let cityLine = [address.city, address.postalCode].compactMap { $0 }.joined(separator: " ")
            if !cityLine.isEmpty { Text(cityLine) }
            if let region = session.regionName(address.regionCode) { Text(region) }
            if address.countryCode != session.business.countryCode { Text(session.countryName(address.countryCode)) }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}
