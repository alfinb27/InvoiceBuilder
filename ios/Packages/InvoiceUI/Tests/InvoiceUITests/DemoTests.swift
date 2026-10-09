import Foundation
import InvoiceCore
import Testing
@testable import InvoiceUI

@MainActor
@Suite("Sample business")
struct DemoTests {
    @Test func tryingTheSampleBusinessNeverTouchesTheRealDatabase() async throws {
        let real = try TestEnvironment.dependencies()
        let app = AppModel(dependencies: real)
        await app.start()
        guard case .onboarding = app.phase else {
            Issue.record("expected onboarding")
            return
        }

        await app.startDemo(.uk)
        guard case .ready(let demo) = app.phase else {
            Issue.record("expected the demo shell, got \(app.phase)")
            return
        }
        #expect(demo.isDemo && demo.business.name == "Thames Design Ltd")
        let documents = try #require(try await firstValue(demo.dependencies.documents.observeDocuments(
            businessID: demo.business.id)))
        #expect(documents.count == 4) // three invoices and a quote
        #expect(documents.contains { $0.status(today: demo.today) == .overdue })
        #expect(documents.contains { $0.status(today: demo.today) == .paid })
        #expect(try await real.businesses.fetchBusinesses().isEmpty)

        // "Set up my business" goes back to onboarding on the real database.
        await demo.reloadApp()
        guard case .onboarding = app.phase else {
            Issue.record("expected onboarding after leaving the demo, got \(app.phase)")
            return
        }
    }
}
