import InvoiceCore
import SwiftUI

/// The Items tab (wireframe 7): list and detail, with the editor in a sheet.
struct CatalogSection: View {
    let session: Session
    @State private var list: CatalogListViewModel

    init(session: Session) {
        self.session = session
        _list = State(initialValue: CatalogListViewModel(session: session))
    }

    var body: some View {
        @Bindable var router = session.router.items
        NavigationSplitView {
            CatalogList(model: list, router: router, session: session)
                .navigationTitle("Items")
        } detail: {
            if let id = router.selection {
                CatalogItemDetailView(session: session, itemID: id)
                    .id(id)
            } else {
                ContentUnavailableView("Select an item", systemImage: "shippingbox",
                                       description: Text("Its price and tax details appear here."))
            }
        }
        .sheet(item: $router.editor) { route in
            CatalogItemEditorView(session: session, route: route)
        }
        .task { await list.observe() }
    }
}

private struct CatalogList: View {
    let model: CatalogListViewModel
    @Bindable var router: ListDetailRouter
    let session: Session
    @State private var pendingDelete: CatalogItem?

    var body: some View {
        let items = model.visibleItems(query: router.searchText, archived: router.showArchived)
        List(selection: $router.selection) {
            ForEach(items) { item in
                NavigationLink(value: item.id) {
                    CatalogRow(item: item, session: session)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = item }
                    archiveButton(item).tint(Theme.warning)
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { router.edit(item.id) }
                    archiveButton(item)
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = item }
                }
            }
        }
        .themedList()
        .overlay {
            if model.state.isLoading {
                ProgressView()
            } else if items.isEmpty {
                emptyState
            }
        }
        .searchable(text: $router.searchText, prompt: "Name or \(session.config.labels.productCodeName)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add item", systemImage: "plus") { router.editor = .new }
            }
            ToolbarItem(placement: .secondaryAction) {
                Toggle("Show archived", systemImage: "archivebox", isOn: $router.showArchived)
            }
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "item")?", isPresented: deleteBinding,
                            titleVisibility: .visible, presenting: pendingDelete) { item in
            Button("Delete", role: .destructive) { Task { await model.delete(item) } }
        } message: { _ in
            Text("Invoices that already include this item keep their lines.")
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.state.errorMessage ?? "")
        }
    }

    private func archiveButton(_ item: CatalogItem) -> some View {
        Button(item.isArchived ? "Restore" : "Archive",
               systemImage: item.isArchived ? "tray.and.arrow.up" : "archivebox") {
            Task { await model.setArchived(!item.isArchived, item) }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !router.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: router.searchText)
        } else if router.showArchived {
            ContentUnavailableView("No archived items", systemImage: "archivebox",
                                   description: Text("Archived items are hidden from pickers but kept for old invoices."))
        } else {
            ContentUnavailableView {
                Label("No items yet", systemImage: "shippingbox")
            } description: {
                Text("Save the goods and services you sell, with their prices and tax rates.")
            } actions: {
                Button("Add item") { router.editor = .new }
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

private struct CatalogRow: View {
    let item: CatalogItem
    let session: Session

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(item.name).foregroundStyle(.primary)
                if let code = item.productCode {
                    Text("\(session.config.labels.productCodeName) \(code)")
                        .font(Theme.Fonts.subhead)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                Text(session.money(item.unitPriceMinor, currency: item.currency))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(session.rate(item.rateId)?.label ?? item.rateId)
                    .font(Theme.Fonts.subhead)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.Space.xxs)
        .accessibilityElement(children: .combine)
    }
}

/// An item's details; Edit opens the editor sheet.
struct CatalogItemDetailView: View {
    let session: Session
    let itemID: String
    @State private var item: CatalogItem?
    @State private var loaded = false

    var body: some View {
        Group {
            if let item {
                ThemedForm {
                    Section {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Text(item.name).font(Theme.Fonts.title3.weight(.semibold))
                            HStack {
                                Tag(text: item.kind == .goods ? "Goods" : "Service")
                                if item.isArchived { Tag(text: "Archived", color: Theme.textSecondary) }
                            }
                            if let description = item.description {
                                Text(description).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .padding(.vertical, Theme.Space.xs)
                    }
                    Section("Price") {
                        LabeledContent("Price", value: session.money(item.unitPriceMinor, currency: item.currency))
                            .monospacedDigit()
                        LabeledContent("Unit", value: "\(session.unitLabel(item.unit)) (\(item.unit))")
                        if session.chargesTax {
                            LabeledContent("Price includes \(session.config.labels.taxName)",
                                           value: item.priceIncludesTax ? "Yes" : "No")
                        }
                    }
                    Section(session.config.labels.taxName) {
                        LabeledContent("Rate", value: session.rate(item.rateId)?.label ?? item.rateId)
                        if let code = item.productCode {
                            LabeledContent(session.config.labels.productCodeName, value: code)
                        }
                    }
                }
            } else if loaded {
                ContentUnavailableView("Item not found", systemImage: "shippingbox")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(item?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if item != nil {
                Button("Edit") { session.router.items.edit(itemID) }
            }
        }
        .task(id: itemID) {
            do {
                for try await latest in session.dependencies.catalog.observeItem(id: itemID) {
                    item = latest
                    loaded = true
                }
            } catch {
                loaded = true
            }
        }
    }
}
