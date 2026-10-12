import Foundation
import GRDB
import InvoiceCore
import Testing
@testable import InvoiceData

@Suite("Payments")
struct PaymentTests {
    @Test func recordingAPaymentOnAnIssuedInvoice() async throws {
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()
        try await store.saveDraft(business, lines: [TestStore.line("l1", "Website", price: 1_000_000)])
        let issued = try await store.documentService.issue(documentID: "d1", deviceID: device.id)
        #expect(issued.totals.totalMinor == 1_180_000)

        let payment = try await store.paymentService.recordPayment(
            documentID: issued.id, amountMinor: 500_000, date: store.time.today(), method: .upi,
            reference: " REF123 ", note: nil)
        #expect(payment.reference == "REF123" && payment.businessId == business.id)

        let stored = try await store.payments.fetchPayments(documentID: issued.id)
        #expect(stored.map(\.amountMinor) == [500_000])
        let paid = stored.reduce(0) { $0 + $1.amountMinor }
        #expect(issued.status(today: store.time.today(), paid: paid) == .partiallyPaid)

        // A second payment that fully covers the rest.
        try await store.paymentService.recordPayment(documentID: issued.id, amountMinor: 680_000,
                                                      date: store.time.today(), method: .cash, reference: nil,
                                                      note: nil)
        let total = try await store.payments.fetchPayments(documentID: issued.id).reduce(0) { $0 + $1.amountMinor }
        #expect(issued.status(today: store.time.today(), paid: total) == .paid)
    }

    @Test func overpaymentIsStoredAsGivenNotClamped() async throws {
        // documents.md §10: amountMinor may exceed the outstanding amount; storage never clamps or rejects it.
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()
        try await store.saveDraft(business, lines: [TestStore.line("l1", "Website", price: 100_000)])
        let issued = try await store.documentService.issue(documentID: "d1", deviceID: device.id)
        let payment = try await store.paymentService.recordPayment(
            documentID: issued.id, amountMinor: 999_999, date: store.time.today(), method: .cash, reference: nil,
            note: nil)
        #expect(payment.amountMinor == 999_999)
        let paid = try await store.payments.fetchPayments(documentID: issued.id).reduce(0) { $0 + $1.amountMinor }
        #expect(paid == 999_999)
        #expect(issued.status(today: store.time.today(), paid: paid) == .paid) // ENGINE.md §6: paid >= total
    }

    @Test func onlyLiveIssuedInvoicesArePayable() async throws {
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()

        // A draft.
        try await store.saveDraft(business, id: "d1", lines: [TestStore.line("l1", "Website", price: 100_000)])
        await #expect(throws: PaymentServiceError.notPayable) {
            try await store.paymentService.recordPayment(documentID: "d1", amountMinor: 1, date: store.time.today(),
                                                          method: .cash, reference: nil, note: nil)
        }

        // A quote.
        try await store.saveDraft(business, docType: .quote, id: "q1",
                                  lines: [TestStore.line("l2", "Audit", price: 100_000)])
        let quote = try await store.documentService.issue(documentID: "q1", deviceID: device.id)
        await #expect(throws: PaymentServiceError.notPayable) {
            try await store.paymentService.recordPayment(documentID: quote.id, amountMinor: 1,
                                                          date: store.time.today(), method: .cash, reference: nil,
                                                          note: nil)
        }

        // A void invoice.
        let issued = try await store.documentService.issue(documentID: "d1", deviceID: device.id)
        let voided = try await store.documentService.voidDocument(documentID: issued.id, reason: "Duplicate")
        await #expect(throws: PaymentServiceError.notPayable) {
            try await store.paymentService.recordPayment(documentID: voided.id, amountMinor: 1,
                                                          date: store.time.today(), method: .cash, reference: nil,
                                                          note: nil)
        }

        // A missing document.
        await #expect(throws: PaymentServiceError.documentNotFound) {
            try await store.paymentService.recordPayment(documentID: "missing", amountMinor: 1,
                                                          date: store.time.today(), method: .cash, reference: nil,
                                                          note: nil)
        }
    }

    @Test func voidingAnInvoiceKeepsItsPaymentsAsHistory() async throws {
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()
        try await store.saveDraft(business, lines: [TestStore.line("l1", "Website", price: 500_000)])
        let issued = try await store.documentService.issue(documentID: "d1", deviceID: device.id)
        try await store.paymentService.recordPayment(documentID: issued.id, amountMinor: 200_000,
                                                      date: store.time.today(), method: .bank, reference: nil,
                                                      note: nil)
        let voided = try await store.documentService.voidDocument(documentID: issued.id, reason: "Wrong client")
        let stored = try await store.payments.fetchPayments(documentID: issued.id)
        #expect(stored.map(\.amountMinor) == [200_000]) // untouched by voiding
        #expect(voided.status(today: store.time.today(), paid: 200_000) == .void) // ENGINE.md §6: void wins
    }

    @Test func correctingAPaymentIsDeleteAndReAdd() async throws {
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()
        try await store.saveDraft(business, lines: [TestStore.line("l1", "Website", price: 500_000)])
        let issued = try await store.documentService.issue(documentID: "d1", deviceID: device.id)
        let wrong = try await store.paymentService.recordPayment(documentID: issued.id, amountMinor: 100_000,
                                                                  date: store.time.today(), method: .cash,
                                                                  reference: nil, note: nil)
        try await store.payments.softDelete(paymentID: wrong.id)
        try await store.paymentService.recordPayment(documentID: issued.id, amountMinor: 250_000,
                                                      date: store.time.today(), method: .cash, reference: nil,
                                                      note: nil)
        let stored = try await store.payments.fetchPayments(documentID: issued.id)
        #expect(stored.map(\.amountMinor) == [250_000]) // the tombstoned one is invisible

        var updates = store.payments.observePayments(documentID: issued.id).makeAsyncIterator()
        #expect(try await updates.next()?.map(\.amountMinor) == [250_000])
    }
}
