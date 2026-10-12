import Foundation
import GRDB
import InvoiceBilling
import InvoiceCore
import InvoiceData
import Testing
@testable import InvoiceUI

@MainActor
@Suite("Free tier and unlock")
struct EntitlementTests {
    /// A seeded Indian business whose free-tier counter already stands at `issued`.
    static func session(issued: Int) async throws -> Session {
        let database = try AppDatabase.inMemory()
        let dependencies = try AppDependencies.make(
            database: database, time: .fixed(now: 1_789_800_000_000, today: TestEnvironment.today), ids: .sequential())
        let device = try await dependencies.deviceState.loadOrCreate(deviceName: "Test")
        let business = try await SampleData.seed(.india, dependencies: dependencies, deviceID: device.id)
        try await database.writer.write { db in
            try db.execute(sql: "INSERT INTO app_state (key, value) VALUES ('issued_invoice_count', ?)",
                           arguments: [String(issued)])
        }
        await dependencies.entitlements.start()
        let session = try Session(dependencies: dependencies, business: business, deviceID: device.id,
                                  pdfDirectory: TestEnvironment.pdfDirectory())
        let observing = Task { await session.observeEntitlements() }
        while session.entitlement.state == .unknown { await Task.yield() }
        observing.cancel()
        return session
    }

    static func draft(_ docType: DocumentType, session: Session) async throws -> DocumentViewModel {
        let model = DocumentViewModel(session: session, route: .new(docType, id: "new-\(docType.rawValue)"))
        await model.load()
        let items = try #require(try await firstValue(
            session.dependencies.catalog.observeItems(businessID: session.business.id)))
        model.addItem(try #require(items.first))
        await model.flush()
        return model
    }

    @Test func belowTheLimitIssuingWorks() async throws {
        let session = try await Self.session(issued: 14)
        #expect(session.entitlement.state == .free && session.entitlement.remaining == 1)
        let model = try await Self.draft(.invoice, session: session)
        await model.requestIssue()
        #expect(!model.state.showsPaywall && model.state.confirmingIssue)
        await model.confirmIssue()
        #expect(model.state.document.lifecycle == .issued)
        // The fifteenth invoice used the last free one.
        var statuses = session.dependencies.entitlements.observeStatus().makeAsyncIterator()
        #expect(await statuses.next()?.state == .limitReached)
    }

    @Test func atTheLimitOnlyIssuingAnInvoiceIsLocked() async throws {
        let session = try await Self.session(issued: 15)
        #expect(session.entitlement.state == .limitReached)

        let invoice = try await Self.draft(.invoice, session: session)
        await invoice.requestIssue()
        #expect(invoice.state.showsPaywall && !invoice.state.confirmingIssue)

        // Quotes are never counted or locked.
        let quote = try await Self.draft(.quote, session: session)
        await quote.requestIssue()
        #expect(!quote.state.showsPaywall && quote.state.confirmingIssue)
    }
}
