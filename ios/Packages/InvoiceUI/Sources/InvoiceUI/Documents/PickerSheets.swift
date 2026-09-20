import InvoiceCore
import SwiftUI

/// Choosing the client of a document: search, "no client" (a walk-in customer) or a new client added on the spot.
struct ClientPickerSheet: View {
    let session: Session
    let selectedID: String?
    let onPick: (Client?) -> Void
    @State private var clients: [Client] = []
    @State private var query = ""
    @State private var addingClient = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        pick(nil)
                    } label: {
                        row(title: "No client", detail: "A walk-in customer", selected: selectedID == nil)
                    }
                }
                Section {
                    ForEach(SetupSearch.clients(clients.filter { !$0.isArchived }, matching: query)) { client in
                        Button {
                            pick(client)
                        } label: {
                            row(title: client.name, detail: detail(client), selected: client.id == selectedID)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Name, \(session.config.labels.taxIdName), email or phone")
            .navigationTitle("Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New client", systemImage: "plus") { addingClient = true }
                }
            }
            .sheet(isPresented: $addingClient) {
                ClientEditorView(session: session, route: .new) { client in
                    pick(client)
                }
            }
            .task {
                do {
                    for try await latest in session.dependencies.clients.observeClients(
                        businessID: session.business.id) {
                        clients = latest
                    }
                } catch {}
            }
        }
    }

    private func pick(_ client: Client?) {
        onPick(client)
        dismiss()
    }

    private func detail(_ client: Client) -> String? {
        if client.countryCode != session.business.countryCode { return session.countryName(client.countryCode) }
        if let taxId = client.taxId { return "\(session.config.labels.taxIdName) \(taxId)" }
        return client.billingAddress?.city
    }

    private func row(title: String, detail: String?, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).foregroundStyle(Theme.textPrimary)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary) }
            }
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Theme.brand) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Adding catalogue items to a document: each tap adds a line; Done closes.
struct CatalogPickerSheet: View {
    let session: Session
    /// Adds the item and returns true when the builder needs the price typed in (no exchange rate).
    let onAdd: (CatalogItem) -> Bool
    @State private var items: [CatalogItem] = []
    @State private var query = ""
    @State private var added: [String: Int] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(SetupSearch.items(items.filter { !$0.isArchived }, matching: query)) { item in
                Button {
                    let needsPrice = onAdd(item)
                    added[item.id, default: 0] += 1
                    if needsPrice { dismiss() } // the line editor opens behind this sheet otherwise
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(item.name).foregroundStyle(Theme.textPrimary)
                            Text(session.money(item.unitPriceMinor, currency: item.currency)
                                 + (item.priceIncludesTax ? " incl. \(session.config.labels.taxName)" : ""))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if let count = added[item.id] {
                            Tag(text: count == 1 ? "Added" : "Added ×\(count)", color: Theme.success)
                        } else {
                            Image(systemName: "plus.circle").foregroundStyle(Theme.brand)
                        }
                    }
                }
                .accessibilityIdentifier("catalogItem-\(item.name)")
            }
            .overlay {
                if items.filter({ !$0.isArchived }).isEmpty {
                    ContentUnavailableView("No items yet", systemImage: "shippingbox",
                                           description: Text("Add goods and services in the Items tab, or add a one-off line."))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Name or \(session.config.labels.productCodeName)")
            .navigationTitle("Add items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("catalogDone")
                }
            }
            .task {
                do {
                    for try await latest in session.dependencies.catalog.observeItems(businessID: session.business.id) {
                        items = latest
                    }
                } catch {}
            }
        }
    }
}
