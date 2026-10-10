import InvoiceCore
import Observation
import SwiftUI

/// Home: until the first invoice is sent, a checklist and a big "Create an invoice" (`spec/setup.md` §3.2); then
/// what's owed and quick actions for invoices and quotes.
@MainActor @Observable
final class HomeViewModel {
    struct State: Equatable {
        var clientCount = 0
        var itemCount = 0
        var documents: [DocumentSummary] = []
        var documentsLoaded = false
        var dashboard = DashboardTotals()
        /// Issued documents sharing a number (`spec/sync.md` §4); normally empty.
        var duplicateNumbers: [DuplicateNumbers.Group] = []

        var checklist: FirstRunChecklist {
            FirstRunChecklist(clientCount: clientCount, itemCount: itemCount, documents: documents)
        }
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
        async let documents: Void = observeDocuments()
        async let dashboard: Void = observeDashboard()
        async let duplicates: Void = observeDuplicates()
        _ = await (clients, items, documents, dashboard, duplicates)
    }

    private func observeDocuments() async {
        do {
            for try await documents in session.dependencies.documents.observeDocuments(
                businessID: session.business.id) {
                state.documents = documents
                state.documentsLoaded = true
            }
        } catch {}
    }

    private func observeDuplicates() async {
        do {
            for try await groups in session.dependencies.numbering.observeDuplicateNumbers(
                businessID: session.business.id) {
                state.duplicateNumbers = groups
            }
        } catch {}
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
    @Environment(\.dynamicTypeSize) private var typeSize

    init(session: Session) {
        self.session = session
        _model = State(initialValue: HomeViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    HomeHeader(session: session)
                    if session.isDemo { DemoBanner(session: session) }
                    if !session.entitlement.isUnlocked, session.entitlement.state != .unknown,
                       session.entitlement.remaining <= 3 {
                        FreeTierBanner(session: session)
                    }
                    ForEach(model.state.duplicateNumbers, id: \.self) { group in
                        DuplicateNumberWarning(group: group, session: session)
                    }
                    if model.state.documentsLoaded {
                        if model.state.checklist.isShown { firstRun } else { dashboard }
                    }
                    if session.config.reviewStatus != "reviewed" {
                        Label("\(session.config.labels.taxName) rules in this build are awaiting review by a professional.",
                              systemImage: "info.circle")
                            .font(Theme.Fonts.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.vertical, Theme.Space.xl)
                .readableWidth()
            }
            .background(Theme.background)
            .navigationTitle("Home")
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await model.observe() }
    }

    // MARK: Before the first invoice

    @ViewBuilder private var firstRun: some View {
        let checklist = model.state.checklist
        SurfaceCard(padding: Theme.Space.l + 2) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                // One element for VoiceOver: the heading and how far along it is.
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Get ready to send your first invoice")
                        .font(Theme.Fonts.title3)
                        .foregroundStyle(Theme.textPrimary)
                    ProgressBar(value: checklist.doneCount, total: FirstRunChecklist.Item.allCases.count)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, Theme.Space.xs)
                VStack(spacing: 0) {
                    ForEach(FirstRunChecklist.Item.allCases, id: \.self) { item in
                        ChecklistRow(title: title(item), hint: hint(item), isDone: checklist.isDone(item),
                                     action: action(item))
                            .accessibilityIdentifier("checklist.\(item.rawValue)")
                        if item != FirstRunChecklist.Item.allCases.last { Divider().overlay(Theme.surfaceMuted) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.checklist")
        VStack(spacing: Theme.Space.s) {
            PrimaryButton(title: "Create an invoice", systemImage: "plus") { session.startNewDocument(.invoice) }
                .accessibilityIdentifier("homeNewInvoice")
            Text("You can jump straight in. We'll ask for the client and items as you go.")
                .font(Theme.Fonts.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            Overline(text: "Once you start sending")
            moneyTiles(empty: true)
        }
        .padding(.top, Theme.Space.xs)
    }

    private func title(_ item: FirstRunChecklist.Item) -> String {
        switch item {
        case .setUpBusiness: "Set up your business"
        case .addClient: "Add your first client"
        case .saveItem: "Save something you sell"
        case .sendInvoice: "Send your first invoice"
        }
    }

    private func hint(_ item: FirstRunChecklist.Item) -> String? {
        switch item {
        case .setUpBusiness: nil
        case .addClient: "The person or shop you're billing"
        case .saveItem: "Add it once, reuse it on every invoice"
        case .sendInvoice: "\(FreeTier.limit) invoices free, no sign-up"
        }
    }

    private func action(_ item: FirstRunChecklist.Item) -> (() -> Void)? {
        switch item {
        case .setUpBusiness: nil
        case .addClient: { session.router.startNewClient() }
        case .saveItem: { session.router.startNewItem() }
        case .sendInvoice: { session.startNewDocument(.invoice) }
        }
    }

    // MARK: After the first invoice

    @ViewBuilder private var dashboard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            Overline(text: "Money")
            moneyTiles(empty: false)
        }
        .accessibilityIdentifier("homeDashboard")
        VStack(spacing: Theme.Space.s) {
            PrimaryButton(title: "New invoice", systemImage: "plus") { session.startNewDocument(.invoice) }
                .accessibilityIdentifier("homeNewInvoice")
            Button {
                session.startNewDocument(.quote)
            } label: {
                Label("New quote", systemImage: "doc.text.magnifyingglass").frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("homeNewQuote")
        }
        if session.business.logoAssetId == nil || session.business.signatureAssetId == nil {
            Button {
                session.router.settings.selection = .images
                session.router.selectedTab = .settings
            } label: {
                TipCallout("Add your logo and signature so your invoices look like yours.", systemImage: "signature")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Settings")
        }
    }

    private func moneyTiles(empty: Bool) -> some View {
        let totals = model.state.dashboard
        let tiles: [(String, Int64, Bool)] = [
            ("Waiting to be paid", totals.outstandingMinor, false),
            ("Past due date", totals.overdueMinor, totals.overdueMinor > 0),
            ("Paid this month", totals.paidThisMonthMinor, false),
        ]
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Theme.Space.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.s))
        return layout { tileViews(tiles, empty: empty) }
    }

    @ViewBuilder
    private func tileViews(_ tiles: [(String, Int64, Bool)], empty: Bool) -> some View {
        ForEach(tiles, id: \.0) { label, minor, alert in
            if empty {
                EmptyStatTile(amount: session.money(0), label: label)
            } else {
                StatTile(amount: session.money(minor), label: label, emphasis: alert ? Theme.danger : nil)
            }
        }
    }
}

/// "Good morning", the business name, and its logo or initials.
private struct HomeHeader: View {
    let session: Session
    @State private var logo: Data?

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(Theme.Fonts.subhead).foregroundStyle(Theme.textSecondary)
                Text(session.business.name)
                    .font(Theme.Fonts.title)
                    .tracking(Theme.Fonts.tracking("title"))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let logo, let image = UIImage(data: logo) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            } else {
                Avatar(name: session.business.name, size: 44)
            }
        }
        .accessibilityElement(children: .combine)
        .modifier(StoredAssetLoader(assetID: session.business.logoAssetId, assets: session.dependencies.assets,
                                    data: $logo))
    }

    private var greeting: String {
        let date = Date(timeIntervalSince1970: TimeInterval(session.dependencies.time.now()) / 1000)
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

/// Two issued documents share a number (`spec/sync.md` §4): say so and link to them; nothing is renumbered.
private struct DuplicateNumberWarning: View {
    let group: DuplicateNumbers.Group
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Label("\(group.ids.count) \(DocumentText.noun(group.docType))s share the number \(group.number)",
                  systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Fonts.subhead.weight(.semibold))
                .foregroundStyle(Theme.warning)
            Text("Void one of them and send it again, so each number is used once.")
                .font(Theme.Fonts.footnote)
                .foregroundStyle(Theme.textSecondary)
            HStack {
                ForEach(Array(group.ids.enumerated()), id: \.element) { index, id in
                    Button("Open \(index + 1)") { session.openDocument(id, docType: group.docType) }
                        .buttonStyle(.secondary)
                }
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.warning.opacity(0.5)))
        .accessibilityElement(children: .contain)
    }
}

/// Three or fewer free invoices left (`spec/billing.md`): say so, once, without blocking anything.
private struct FreeTierBanner: View {
    let session: Session
    @State private var showsPaywall = false

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            Image(systemName: "infinity").foregroundStyle(Theme.brandPressed).accessibilityHidden(true)
            Text(session.entitlement.remaining == 0
                 ? "You've used your \(FreeTier.limit) free invoices"
                 : "\(session.entitlement.remaining) free invoice\(session.entitlement.remaining == 1 ? "" : "s") left")
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Unlock") { showsPaywall = true }
                .buttonStyle(.secondary)
        }
        .padding(Theme.Space.m + 2)
        .background(Theme.brandTint, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
        .sheet(isPresented: $showsPaywall) { PaywallView(session: session) }
        .accessibilityIdentifier("home.freeTier")
    }
}

/// The sample business is not saved; leaving it goes back to setting up the real one.
private struct DemoBanner: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Label("This is a sample business", systemImage: "sparkles")
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(Theme.textPrimary)
            Text("Look around and try anything: nothing here is saved.")
                .font(Theme.Fonts.footnote)
                .foregroundStyle(Theme.textSecondary)
            Button("Set up my business") { Task { await session.reloadApp() } }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("demo.leave")
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.brandTint, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}
