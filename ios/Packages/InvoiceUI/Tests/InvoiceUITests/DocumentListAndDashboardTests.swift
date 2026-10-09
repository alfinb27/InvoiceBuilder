import Foundation
import InvoiceCore
import Testing
@testable import InvoiceUI

/// Polls `condition` on an already-running `@Observable` model until it turns true, or fails the test after ~2s.
/// `observe()` methods stream from GRDB's `ValueObservation`, which fires asynchronously even against an in-memory
/// database, so tests that read `model.state` need to wait for the first emission.
@MainActor
func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    for _ in 0..<200 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}

@MainActor
@Suite("Document list")
struct DocumentListViewModelTests {
    /// Issues an invoice for Rao Traders with one catalogue item, via the builder (so totals come from the engine).
    func issuedInvoice(_ session: Session, id: String, itemName: String, dueDate: LocalDate? = nil) async throws
        -> Document {
        let model = DocumentViewModel(session: session, route: .new(.invoice, id: id), autosaveDelay: .zero)
        await model.load()
        let clients = try await firstValue(session.dependencies.clients.observeClients(businessID: session.business.id))
        model.chooseClient(try #require(clients?.first { $0.name == "Rao Traders" }))
        let items = try await firstValue(session.dependencies.catalog.observeItems(businessID: session.business.id))
        model.addItem(try #require(items?.first { $0.name == itemName }))
        if let dueDate { model.setDueDate(dueDate) }
        await model.requestIssue()
        await model.confirmIssue()
        return model.state.document
    }

    @Test func statusFilterNarrowsTheIssuedSection() async throws {
        let session = try await TestEnvironment.session()
        let paid = try await issuedInvoice(session, id: "doc-paid", itemName: "Website development")
        try await session.dependencies.paymentService.recordPayment(
            documentID: paid.id, amountMinor: paid.totals.totalMinor, date: session.today, method: .cash,
            reference: nil, note: nil)
        let overdue = try await issuedInvoice(session, id: "doc-overdue", itemName: "Tea leaves",
                                              dueDate: session.today.adding(days: -10))

        let list = DocumentListViewModel(session: session)
        let task = Task { await list.observe() }
        defer { task.cancel() }
        await waitUntil { list.state.documents.count >= 2 }

        let all = list.visible(docType: .invoice, query: "", statusFilter: .all, dateFilter: .allTime,
                               today: session.today)
        #expect(Set(all.issued.map(\.id)) == [paid.id, overdue.id])

        let unpaid = list.visible(docType: .invoice, query: "", statusFilter: .unpaid, dateFilter: .allTime,
                                  today: session.today)
        #expect(unpaid.issued.map(\.id) == [overdue.id])

        let overdueOnly = list.visible(docType: .invoice, query: "", statusFilter: .overdue, dateFilter: .allTime,
                                       today: session.today)
        #expect(overdueOnly.issued.map(\.id) == [overdue.id])

        let paidOnly = list.visible(docType: .invoice, query: "", statusFilter: .paid, dateFilter: .allTime,
                                    today: session.today)
        #expect(paidOnly.issued.map(\.id) == [paid.id])

        // Quotes ignore the invoice status filter entirely (it isn't even offered for them in the UI).
        let quotes = list.visible(docType: .quote, query: "", statusFilter: .paid, dateFilter: .allTime,
                                  today: session.today)
        #expect(quotes.issued.isEmpty && quotes.drafts.isEmpty)
    }

    @Test func dateFilterUsesIssueDate() async throws {
        let session = try await TestEnvironment.session()
        let recent = try await issuedInvoice(session, id: "doc-recent", itemName: "Website development")

        let list = DocumentListViewModel(session: session)
        let task = Task { await list.observe() }
        defer { task.cancel() }
        await waitUntil { !list.state.documents.isEmpty }

        let thisMonth = list.visible(docType: .invoice, query: "", statusFilter: .all, dateFilter: .thisMonth,
                                     today: session.today)
        #expect(thisMonth.issued.map(\.id) == [recent.id])

        // "This month" measured from a much later date excludes an invoice issued long before it.
        let muchLater = LocalDate(iso: "2099-01-01")!
        let excluded = list.visible(docType: .invoice, query: "", statusFilter: .all, dateFilter: .thisMonth,
                                    today: muchLater)
        #expect(excluded.issued.isEmpty)
    }
}

@MainActor
@Suite("Home dashboard")
struct HomeDashboardTests {
    @Test func dashboardReflectsPaymentsAndOverdueInvoices() async throws {
        let session = try await TestEnvironment.session()
        let model = DocumentViewModel(session: session, route: .new(.invoice, id: "doc-1"), autosaveDelay: .zero)
        await model.load()
        let clients = try await firstValue(session.dependencies.clients.observeClients(businessID: session.business.id))
        model.chooseClient(try #require(clients?.first { $0.name == "Rao Traders" }))
        let items = try await firstValue(session.dependencies.catalog.observeItems(businessID: session.business.id))
        model.addItem(try #require(items?.first { $0.name == "Website development" }))
        await model.requestIssue()
        await model.confirmIssue()
        let issued = model.state.document
        try await session.dependencies.paymentService.recordPayment(
            documentID: issued.id, amountMinor: 200_000, date: session.today, method: .cash, reference: nil,
            note: nil)

        let home = HomeViewModel(session: session)
        let task = Task { await home.observe() }
        defer { task.cancel() }
        await waitUntil { home.state.dashboard != DashboardTotals() }

        #expect(home.state.dashboard.outstandingMinor == issued.totals.totalMinor - 200_000)
        #expect(home.state.dashboard.paidThisMonthMinor == 200_000)
        #expect(home.state.dashboard.overdueMinor == 0) // due in the future (payment terms), not overdue
    }
}

@MainActor
@Suite("List performance")
struct ListPerformanceTests {
    /// Phase 6: searching 1,000 invoices returns in under 100 ms (the list filters in memory).
    @Test func searchingAThousandInvoicesIsFast() async throws {
        let session = try await TestEnvironment.session(.india)
        let model = DocumentListViewModel(session: session)
        let today = TestEnvironment.today
        // Explicit types and one value per line: Xcode 26's type checker times out on the inline arithmetic.
        let rows = (1...1_000).map { (index: Int) -> DocumentSummary in
            let age: Int = index % 300
            let client: Int = index % 40
            let total: Int64 = Int64(index) * 1_000
            let paid: Int64 = index % 3 == 0 ? 1_000 : 0
            return DocumentSummary(id: "d\(index)", docType: .invoice, number: String(format: "INV/26-27/%04d", index),
                                   lifecycle: .issued, issueDate: today.adding(days: -age),
                                   dueDate: today.adding(days: 30 - age), validUntil: nil, sentAt: nil,
                                   quoteOutcome: nil, clientId: "c\(client)", buyerName: "Client \(client)",
                                   currency: .inr, totalMinor: total, paidMinor: paid,
                                   lineCount: 3, updatedAt: Int64(index))
        }
        model.replaceForTesting(rows)
        let clock = ContinuousClock()
        var found = 0
        let elapsed = clock.measure {
            for query in ["Client 7", "0420", "inv/26", "zzz"] {
                found += model.visible(docType: .invoice, query: query, statusFilter: .unpaid,
                                       dateFilter: .last3Months, today: today).issued.count
            }
        }
        #expect(found > 0)
        #expect(elapsed < .milliseconds(100), "four searches took \(elapsed)")
    }
}
