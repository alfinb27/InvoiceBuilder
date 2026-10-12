import Foundation
import GRDB
import InvoiceCore
import Testing
@testable import InvoiceData

/// Phase 6: a business with 1,000 issued invoices (three lines and a payment each) keeps the list and the
/// dashboard fast. Ceilings are loose so a slow CI runner passes; the measured times are printed.
@Suite("Performance")
struct PerformanceTests {
    static func filled(count: Int) async throws -> (TestStore, Business) {
        let store = try TestStore()
        let (business, _) = try await store.setUpInvoicing()
        let template = try await store.saveDraft(business, id: "template", lines: [
            TestStore.line("t1", "Design", price: 100_000), TestStore.line("t2", "Build", price: 250_000),
            TestStore.line("t3", "Hosting", price: 12_000),
        ])
        try await store.database.writer.write { db in
            for index in 1...count {
                var document = template
                document.id = String(format: "doc-%05d", index)
                document.lifecycle = .issued
                document.number = String(format: "INV/26-27/%04d", index)
                document.issueDate = LocalDate(iso: "2026-04-01")!.adding(days: index % 180)
                document.dueDate = document.issueDate.adding(days: 30)
                document.lines = template.lines.enumerated().map { offset, line in
                    var copy = line
                    copy.id = "\(document.id)-l\(offset)"
                    return copy
                }
                document.createdAt = Int64(index)
                document.updatedAt = Int64(index)
                try DocumentRecord(document).insert(db)
                for line in document.lines {
                    try LineItemRecord(line, documentID: document.id, createdAt: 1, updatedAt: 1).insert(db)
                }
                if index % 2 == 0 {
                    try PaymentRecord(Payment(id: "pay-\(index)", businessId: business.id, documentId: document.id,
                                              amountMinor: 50_000, date: document.issueDate, method: .upi))
                        .insert(db)
                }
            }
        }
        return (store, business)
    }

    @Test func theListAndDashboardStayFastWithAThousandInvoices() async throws {
        let (store, business) = try await Self.filled(count: 1_000)
        let clock = ContinuousClock()

        var summaries: [DocumentSummary] = []
        let listTime = try await clock.measure {
            summaries = try await store.database.writer.read { db in
                try GRDBDocumentRepository.summaries(businessID: business.id, db: db)
            }
        }
        #expect(summaries.count == 1_001) // 1,000 issued + the template draft
        let dashboardTime = try await clock.measure {
            _ = try await store.database.writer.read { db in
                try GRDBDocumentRepository.dashboard(businessID: business.id, homeCurrency: .inr,
                                                     today: LocalDate(iso: "2026-09-19")!, db: db)
            }
        }
        print("1,000 invoices: list \(listTime), dashboard \(dashboardTime)")
        #expect(listTime < .seconds(1))
        #expect(dashboardTime < .seconds(1))
    }
}
