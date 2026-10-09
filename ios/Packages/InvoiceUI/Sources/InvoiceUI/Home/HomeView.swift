import InvoiceCore
import Observation
import SwiftUI

/// Home: the business at a glance, what's owed, what to set up next and quick actions for invoices and quotes.
@MainActor @Observable
final class HomeViewModel {
    struct State: Equatable {
        var clientCount = 0
        var itemCount = 0
        var dashboard = DashboardTotals()
    }

    private(set) var state = State()
    private let session: Session

    init(session: Session) {
        self.session = session
    }

    func observe() async {
        let dependencies = session.dependencies
        let businessID = session.business.id
        async let clients: Void = observeCount(dependencies.clients.observeClients(businessID: businessID)) {
            self.state.clientCount = $0
        }
        async let items: Void = observeCount(dependencies.catalog.observeItems(businessID: businessID)) {
            self.state.itemCount = $0
        }
        async let dashboard: Void = observeDashboard()
        _ = await (clients, items, dashboard)
    }

    private func observeDashboard() async {
        do {
            for try await totals in session.dependencies.documents.observeDashboard(
                businessID: session.business.id, homeCurrency: session.business.homeCurrency) {
                state.dashboard = totals
            }
        } catch {}
    }

    private func observeCount<Row: Sendable>(_ stream: AsyncThrowingStream<[Row], any Error>,
                                             update: @MainActor (Int) -> Void) async {
        do {
            for try await rows in stream { update(rows.count) }
        } catch {}
    }
}

struct HomeView: View {
    let session: Session
    @State private var model: HomeViewModel

    init(session: Session) {
        self.session = session
        _model = State(initialValue: HomeViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    BusinessCard(session: session)
                    if model.state.dashboard != DashboardTotals() { dashboard }
                    checklist
                    comingNext
                    if session.config.reviewStatus != "reviewed" {
                        Label("\(session.config.labels.taxName) rules in this build are awaiting review by a professional.",
                              systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(Theme.Space.l)
                .readableWidth()
            }
            .background(Theme.background)
            .navigationTitle("Home")
        }
        .task { await model.observe() }
    }

    private var dashboard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Label("Money", systemImage: "banknote")
                    .font(.headline)
                HStack(spacing: Theme.Space.l) {
                    DashboardTile(title: "Outstanding", value: session.money(model.state.dashboard.outstandingMinor))
                    DashboardTile(title: "Overdue", value: session.money(model.state.dashboard.overdueMinor),
                                 emphasis: model.state.dashboard.overdueMinor > 0 ? Theme.danger : nil)
                    DashboardTile(title: "Paid this month",
                                 value: session.money(model.state.dashboard.paidThisMonthMinor))
                }
            }
        }
        .accessibilityIdentifier("homeDashboard")
    }

    private var checklist: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Get ready to invoice").font(.headline)
                ChecklistRow(done: true, title: "Set up your business")
                ChecklistRow(done: model.state.clientCount > 0,
                             title: model.state.clientCount > 0 ? "\(model.state.clientCount) client\(model.state.clientCount == 1 ? "" : "s")" : "Add your first client",
                             action: ("Add client", { session.router.startNewClient() }))
                ChecklistRow(done: model.state.itemCount > 0,
                             title: model.state.itemCount > 0 ? "\(model.state.itemCount) item\(model.state.itemCount == 1 ? "" : "s") in your catalogue" : "Add the goods or services you sell",
                             action: ("Add item", { session.router.startNewItem() }))
                ChecklistRow(done: session.business.logoAssetId != nil && session.business.signatureAssetId != nil,
                             title: "Add your logo and signature",
                             action: ("Open", {
                                 session.router.settings.selection = .images
                                 session.router.selectedTab = .settings
                             }))
            }
        }
    }

    private var comingNext: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Label("Invoices and quotes", systemImage: "doc.text")
                    .font(.headline)
                HStack(spacing: Theme.Space.m) {
                    Button("New invoice", systemImage: "doc.badge.plus") { session.startNewDocument(.invoice) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("homeNewInvoice")
                    Button("New quote") { session.startNewDocument(.quote) }
                        .buttonStyle(.bordered)
                }
                Text("PDFs and sharing arrive in the next test build.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

private struct BusinessCard: View {
    let session: Session
    @State private var logo: Data?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(session.business.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let registration = session.registration {
                        Text(registration.label).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    if let taxId = session.business.taxId {
                        Text("\(session.config.labels.taxIdName) \(taxId)")
                            .font(.subheadline.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let address = session.business.address {
                        Text(address.singleLine).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if logo != nil {
                    ImageWell(data: logo, placeholder: "photo", label: "Logo")
                }
            }
            .accessibilityElement(children: .combine)
        }
        .modifier(StoredAssetLoader(assetID: session.business.logoAssetId, assets: session.dependencies.assets,
                                    data: $logo))
    }
}

private struct DashboardTile: View {
    let title: String
    let value: String
    var emphasis: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(emphasis ?? Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ChecklistRow: View {
    let done: Bool
    let title: String
    var action: (String, () -> Void)?

    var body: some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Theme.success : Theme.textTertiary)
                .accessibilityHidden(true)
            Text(title).foregroundStyle(Theme.textPrimary)
            Spacer()
            if let action, !done {
                Button(action.0, action: action.1)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not done")
    }
}

/// A rounded surface for Home's content.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l).stroke(Theme.border.opacity(0.6)))
    }
}
