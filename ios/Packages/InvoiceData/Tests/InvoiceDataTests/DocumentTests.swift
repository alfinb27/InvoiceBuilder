import Foundation
import GRDB
import InvoiceCore
import Testing
@testable import InvoiceData

extension TestStore {
    static let configs = try! TaxConfigStore.bundled()
    static let currencies = try! ReferenceData.bundled().currencies

    var documents: GRDBDocumentRepository { GRDBDocumentRepository(database: database, time: time) }
    var documentService: GRDBDocumentService {
        GRDBDocumentService(database: database, time: time, ids: ids, configs: Self.configs,
                            currencies: Self.currencies)
    }
    var payments: GRDBPaymentRepository { GRDBPaymentRepository(database: database, time: time) }
    var paymentService: GRDBPaymentService { GRDBPaymentService(database: database, time: time, ids: ids) }

    /// The sample business with its default series owned by this device, plus one B2B client.
    func setUpInvoicing(logo: ImagePayload? = nil) async throws -> (business: Business, device: DeviceState) {
        let device = try await self.device.loadOrCreate(deviceName: "iPhone")
        let config = try #require(Self.configs.latest(family: "IN"))
        let series = BusinessSetup.defaultSeries(businessID: Self.fullBusiness.id, config: config,
                                                 ownerDeviceID: device.id, now: 0, newID: ids.make)
        let business = try await setup.createBusiness(Self.fullBusiness, series: series, logo: logo, signature: nil,
                                                      deviceID: device.id)
        try await clients.save(Client(
            id: "c1", businessId: business.id, name: "Rao Traders",
            billingAddress: Address(line1: "5 Residency Road", city: "Bengaluru", regionCode: "29",
                                    countryCode: "IN"),
            countryCode: "IN", regionCode: "29", taxId: "29AABCR1234C1ZU", isBusiness: true
        ))
        return (business, device)
    }

    func rules(_ business: Business) throws -> DocumentRules {
        try DocumentRules(configs: Self.configs, business: business, currencies: Self.currencies)
    }

    /// A saved draft for client c1 with the given lines.
    func saveDraft(_ business: Business, docType: DocumentType = .invoice, id: String = "d1",
                   lines: [LineItem]) async throws -> Document {
        let rules = try rules(business)
        let client = try await clients.fetchClient(id: "c1")
        var document = rules.newDocument(docType: docType, id: id, today: time.today(), client: client, now: 0)
        document.lines = lines
        return try await documents.saveDraft(rules.preparedDraft(document, client: client))
    }

    static func line(_ id: String, _ description: String, quantity: String = "1", price: Int64,
                     rate: String = "gst_18") -> LineItem {
        LineItem(id: id, description: description, productCode: "998314", quantity: quantity, unitPriceMinor: price,
                 rateId: rate)
    }
}

@Suite("Documents")
struct DocumentTests {
    @Test func draftsSaveTheirLinesAndTombstoneRemovedOnes() async throws {
        let store = try TestStore()
        let (business, _) = try await store.setUpInvoicing()
        var draft = try await store.saveDraft(business, lines: [
            TestStore.line("l1", "Website", quantity: "2", price: 500_000),
            TestStore.line("l2", "Hosting", price: 120_000),
        ])
        #expect(draft.totals.totalMinor == 1_321_600 && draft.buyerSnapshot?.name == "Rao Traders")
        let fetched = try #require(try await store.documents.fetchDocument(id: "d1"))
        #expect(fetched == draft)
        #expect(fetched.lines.map(\.id) == ["l1", "l2"])

        let l2Stamp = try await store.database.writer.read { db in try LineItemRecord.fetchOne(db, key: "l2") }
        draft.lines = [draft.lines[1], TestStore.line("l3", "Domain", price: 90_000)]
        draft.lines[0].position = 0
        draft.lines[1].position = 1
        draft = try await store.documents.saveDraft(draft)
        #expect(try await store.documents.fetchDocument(id: "d1")?.lines.map(\.id) == ["l2", "l3"])
        let (removed, l2) = try await store.database.writer.read { db in
            (try LineItemRecord.fetchOne(db, key: "l1"), try LineItemRecord.fetchOne(db, key: "l2"))
        }
        #expect(removed?.deletedAt != nil) // a tombstone, not a SQL DELETE
        #expect(l2?.updatedAt != l2Stamp?.updatedAt) // its position changed

        // Saving the same lines again leaves unchanged rows alone.
        let before = try await store.database.writer.read { db in try LineItemRecord.fetchOne(db, key: "l3") }
        try await store.documents.saveDraft(draft)
        let after = try await store.database.writer.read { db in try LineItemRecord.fetchOne(db, key: "l3") }
        #expect(before == after)
    }

    @Test func listShowsDraftsAndIssuedDocuments() async throws {
        let store = try TestStore()
        let (business, _) = try await store.setUpInvoicing()
        var updates = store.documents.observeDocuments(businessID: business.id).makeAsyncIterator()
        #expect(try await updates.next() == [])
        try await store.saveDraft(business, lines: [TestStore.line("l1", "Website", price: 100_000)])
        let rows = try #require(try await updates.next())
        #expect(rows.count == 1)
        #expect(rows[0].buyerName == "Rao Traders" && rows[0].lineCount == 1 && rows[0].totalMinor == 118_000)
        #expect(rows[0].status(today: store.time.today()) == .draft)
    }

    @Test func issuingNumbersFreezesAndCounts() async throws {
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()
        try await store.saveDraft(business, lines: [TestStore.line("l1", "Website", quantity: "2", price: 500_000)])
        let issued = try await store.documentService.issue(documentID: "d1", deviceID: device.id)
        #expect(issued.lifecycle == .issued && issued.number == "INV/26-27/0001" && issued.sequence == 1)
        #expect(issued.revision == 1 && issued.computed?.title == "Tax Invoice")
        #expect(try await store.documents.fetchDocument(id: "d1") == issued)

        let (taxLines, series, count, mirror) = try await store.database.writer.read { db in
            (try TaxLineRecord.filter(Column("document_id") == "d1").fetchAll(db),
             try NumberingSeriesRecord.filter(Column("doc_type") == "invoice").fetchOne(db)?.series(),
             try FreeTierCounter.count(db),
             try DeviceStateRecord.current(db)?.freeCounterMirror)
        }
        #expect(taxLines.map(\.component) == ["CGST", "SGST"] && taxLines.allSatisfy { $0.lineId == nil })
        #expect(taxLines.map(\.taxMinor) == [90_000, 90_000])
        #expect(series?.counters == ["FY2026": 2])
        #expect(count == 1 && mirror == 1)
        #expect(try await store.documents.highestIssuedSequence(seriesID: issued.seriesId!, periodKey: "FY2026") == 1)

        // Issued documents are not drafts any more.
        await #expect(throws: DocumentServiceError.notADraft) {
            try await store.documentService.issue(documentID: "d1", deviceID: device.id)
        }
        await #expect(throws: DocumentServiceError.notADraft) { try await store.documents.saveDraft(issued) }
        await #expect(throws: DocumentServiceError.notADraft) {
            try await store.documentService.deleteDraft(documentID: "d1")
        }

        // Quotes use their own series and never count toward the free tier.
        try await store.saveDraft(business, docType: .quote, id: "q1",
                                  lines: [TestStore.line("l9", "Audit", price: 100_000)])
        let quote = try await store.documentService.issue(documentID: "q1", deviceID: device.id)
        #expect(quote.number == "QT/26-27/0001")
        #expect(try await store.database.writer.read(FreeTierCounter.count) == 1)
    }

    @Test func blockedIssuesWriteNothing() async throws {
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()
        try await store.saveDraft(business, lines: [])
        await #expect(throws: DocumentServiceError.blocked([.noLines])) {
            try await store.documentService.issue(documentID: "d1", deviceID: device.id)
        }
        try await store.saveDraft(business, id: "d2", lines: [TestStore.line("l1", "Website", price: 100_000)])
        await #expect(throws: DocumentServiceError.blocked([.noSeries])) {
            try await store.documentService.issue(documentID: "d2", deviceID: "another-device")
        }
        let (d2, count) = try await store.database.writer.read { db in
            (try DocumentRecord.fetchOne(db, key: "d2"), try FreeTierCounter.count(db))
        }
        #expect(d2?.lifecycle == "draft" && d2?.number == nil && count == 0)
    }

    @Test func duplicateConvertAndDelete() async throws {
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()
        try await store.saveDraft(business, docType: .quote, id: "q1",
                                  lines: [TestStore.line("l1", "Website", price: 500_000)])
        await #expect(throws: DocumentServiceError.notConvertible) {
            try await store.documentService.convertQuote(documentID: "q1") // still a draft
        }
        let quote = try await store.documentService.issue(documentID: "q1", deviceID: device.id)

        let invoice = try await store.documentService.convertQuote(documentID: quote.id)
        #expect(invoice.docType == .invoice && invoice.convertedFromId == "q1" && invoice.isDraft)
        #expect(invoice.lines.count == 1 && invoice.lines[0].id != "l1" && invoice.totals.totalMinor == 590_000)
        #expect(try await store.documents.fetchDocument(id: "q1")?.quoteOutcome == .converted)
        await #expect(throws: DocumentServiceError.notConvertible) {
            try await store.documentService.convertQuote(documentID: "q1")
        }

        // Deleting the converted draft makes the quote convertible again.
        try await store.documentService.deleteDraft(documentID: invoice.id)
        #expect(try await store.documents.fetchDocument(id: invoice.id) == nil)
        #expect(try await store.documents.fetchDocument(id: "q1")?.quoteOutcome == nil)

        let copy = try await store.documentService.duplicate(documentID: "q1")
        #expect(copy.docType == .quote && copy.number == nil && copy.isDraft && copy.convertedFromId == nil)
        #expect(copy.validUntil == LocalDate(iso: "2026-10-19") && copy.totals.totalMinor == 590_000)
        #expect(try await store.documents.fetchDocument(id: copy.id) == copy)
    }

    @Test func aDeletedDraftComesBackWhenItIsEditedAgain() async throws {
        // The builder deletes an emptied draft when it closes and keeps editing the same id; saving again must
        // revive it rather than fail for ever (spec/documents.md §5, §9).
        let store = try TestStore()
        let (business, _) = try await store.setUpInvoicing()
        var draft = try await store.saveDraft(business, lines: [TestStore.line("l1", "Website", price: 100_000)])
        try await store.documentService.deleteDraft(documentID: draft.id)
        #expect(try await store.documents.fetchDocument(id: draft.id) == nil)

        draft.lines = [TestStore.line("l2", "Hosting", price: 50_000)]
        draft.lines[0].position = 0
        let revived = try await store.documents.saveDraft(draft)
        #expect(revived.deletedAt == nil)
        let stored = try #require(try await store.documents.fetchDocument(id: draft.id))
        #expect(stored.lines.map(\.id) == ["l2"] && stored.isDraft)
    }

    @Test func reminderOverrideRoundTrips() async throws {
        let store = try TestStore()
        let (business, _) = try await store.setUpInvoicing()
        var draft = try await store.saveDraft(business, lines: [TestStore.line("l1", "Website", price: 100_000)])
        #expect(draft.reminderDaysAfterDueOverride == nil)
        draft.reminderDaysAfterDueOverride = 5
        draft = try await store.documents.saveDraft(draft)
        #expect(try await store.documents.fetchDocument(id: draft.id)?.reminderDaysAfterDueOverride == 5)
    }

    @Test func summariesCarryPaidAmounts() async throws {
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()
        try await store.saveDraft(business, lines: [TestStore.line("l1", "Website", price: 500_000)])
        let issued = try await store.documentService.issue(documentID: "d1", deviceID: device.id)
        try await store.paymentService.recordPayment(documentID: issued.id, amountMinor: 200_000,
                                                      date: store.time.today(), method: .cash, reference: nil,
                                                      note: nil)
        var updates = store.documents.observeDocuments(businessID: business.id).makeAsyncIterator()
        let row = try #require(try await updates.next()?.first { $0.id == issued.id })
        #expect(row.paidMinor == 200_000)
        #expect(row.status(today: store.time.today()) == .partiallyPaid)
        #expect(row.outstanding() == issued.totals.totalMinor - 200_000)
    }

    @Test func dashboardTotalsAreHomeCurrencyOnly() async throws {
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()

        // Fully paid: counts toward paid-this-month, not outstanding.
        try await store.saveDraft(business, id: "paid1", lines: [TestStore.line("l1", "Website", price: 100_000)])
        let paidInvoice = try await store.documentService.issue(documentID: "paid1", deviceID: device.id)
        try await store.paymentService.recordPayment(
            documentID: paidInvoice.id, amountMinor: paidInvoice.totals.totalMinor, date: store.time.today(),
            method: .cash, reference: nil, note: nil)

        // Overdue and unpaid.
        try await store.saveDraft(business, id: "overdue1", lines: [TestStore.line("l2", "Hosting", price: 50_000)])
        let overdueInvoice = try await store.documentService.issue(documentID: "overdue1", deviceID: device.id)
        _ = try await store.database.writer.write { db in
            try DocumentRecord.live.filter(key: overdueInvoice.id)
                .updateAll(db, Column("due_date").set(to: "2020-01-01"))
        }

        // Not yet due: outstanding, but not overdue.
        try await store.saveDraft(business, id: "open1", lines: [TestStore.line("l3", "Consulting", price: 80_000)])
        let openInvoice = try await store.documentService.issue(documentID: "open1", deviceID: device.id)

        // Voided: never contributes.
        try await store.saveDraft(business, id: "void1", lines: [TestStore.line("l4", "Design", price: 60_000)])
        let voidSource = try await store.documentService.issue(documentID: "void1", deviceID: device.id)
        try await store.documentService.voidDocument(documentID: voidSource.id, reason: "Wrong client")

        // Foreign currency: excluded from v1's home-currency-only dashboard, even though it has a payment.
        try await store.saveDraft(business, id: "usd1", lines: [TestStore.line("l5", "Export", price: 40_000)])
        let usdInvoice = try await store.documentService.issue(documentID: "usd1", deviceID: device.id)
        _ = try await store.database.writer.write { db in
            try DocumentRecord.live.filter(key: usdInvoice.id).updateAll(db, Column("currency").set(to: "USD"))
        }
        try await store.paymentService.recordPayment(documentID: usdInvoice.id, amountMinor: 1_000,
                                                      date: store.time.today(), method: .cash, reference: nil,
                                                      note: nil)

        var updates = store.documents.observeDashboard(businessID: business.id, homeCurrency: business.homeCurrency)
            .makeAsyncIterator()
        let totals = try #require(try await updates.next())
        #expect(totals.outstandingMinor == overdueInvoice.totals.totalMinor + openInvoice.totals.totalMinor)
        #expect(totals.overdueMinor == overdueInvoice.totals.totalMinor)
        #expect(totals.paidThisMonthMinor == paidInvoice.totals.totalMinor)
    }

    @Test func reminderCandidatesCarryDerivedStatusAndOverride() async throws {
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()

        try await store.saveDraft(business, id: "overdue1", lines: [TestStore.line("l1", "Website", price: 100_000)])
        let overdue = try await store.documentService.issue(documentID: "overdue1", deviceID: device.id)
        _ = try await store.database.writer.write { db in
            try DocumentRecord.live.filter(key: overdue.id).updateAll(
                db, Column("due_date").set(to: "2020-01-01"),
                Column("reminder_days_after_due_override").set(to: 3))
        }

        try await store.saveDraft(business, id: "paid1", lines: [TestStore.line("l2", "Hosting", price: 50_000)])
        let paid = try await store.documentService.issue(documentID: "paid1", deviceID: device.id)
        try await store.paymentService.recordPayment(documentID: paid.id, amountMinor: paid.totals.totalMinor,
                                                      date: store.time.today(), method: .cash, reference: nil,
                                                      note: nil)

        // A draft and a quote never appear as candidates.
        try await store.saveDraft(business, id: "draft1", lines: [TestStore.line("l3", "Design", price: 10_000)])
        try await store.saveDraft(business, docType: .quote, id: "quote1",
                                  lines: [TestStore.line("l4", "Audit", price: 10_000)])
        _ = try await store.documentService.issue(documentID: "quote1", deviceID: device.id)

        let candidates = try await store.documents.fetchReminderCandidates(businessID: business.id)
        #expect(Set(candidates.map(\.documentId)) == [overdue.id, paid.id])
        let overdueCandidate = try #require(candidates.first { $0.documentId == overdue.id })
        #expect(overdueCandidate.status == .overdue && overdueCandidate.overrideDays == 3)
        #expect(overdueCandidate.dueDate == LocalDate(iso: "2020-01-01"))
        let paidCandidate = try #require(candidates.first { $0.documentId == paid.id })
        #expect(paidCandidate.status == .paid && paidCandidate.overrideDays == nil)
    }

    @Test func voidingALiveIssuedDocument() async throws {
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()
        try await store.saveDraft(business, lines: [TestStore.line("l1", "Website", price: 100_000)])
        await #expect(throws: DocumentServiceError.notVoidable) {
            try await store.documentService.voidDocument(documentID: "d1", reason: "Wrong client") // still a draft
        }
        let issued = try await store.documentService.issue(documentID: "d1", deviceID: device.id)

        await #expect(throws: DocumentServiceError.voidReasonRequired) {
            try await store.documentService.voidDocument(documentID: issued.id, reason: "   ")
        }

        let voided = try await store.documentService.voidDocument(documentID: issued.id, reason: " Duplicate invoice ")
        #expect(voided.lifecycle == .void && voided.voidReason == "Duplicate invoice" && voided.voidedAt != nil)
        #expect(voided.number == issued.number) // the number is never reclaimed

        await #expect(throws: DocumentServiceError.notVoidable) {
            try await store.documentService.voidDocument(documentID: issued.id, reason: "again")
        }
        await #expect(throws: DocumentServiceError.notFound) {
            try await store.documentService.voidDocument(documentID: "missing", reason: "reason")
        }
    }

    @Test func quoteAcceptedOrDeclined() async throws {
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()
        try await store.saveDraft(business, docType: .quote, id: "q1",
                                  lines: [TestStore.line("l1", "Website", price: 500_000)])
        await #expect(throws: DocumentServiceError.notALiveQuote) {
            try await store.documentService.acceptQuote(documentID: "q1") // still a draft
        }
        let quote = try await store.documentService.issue(documentID: "q1", deviceID: device.id)

        let accepted = try await store.documentService.acceptQuote(documentID: quote.id)
        #expect(accepted.quoteOutcome == .accepted)

        // The buyer can change their mind.
        let declined = try await store.documentService.declineQuote(documentID: quote.id)
        #expect(declined.quoteOutcome == .declined)

        // Converting, then trying to accept/decline again, is blocked.
        _ = try await store.documentService.convertQuote(documentID: quote.id)
        await #expect(throws: DocumentServiceError.alreadyConverted) {
            try await store.documentService.acceptQuote(documentID: quote.id)
        }

        // Invoices are never quotes.
        try await store.saveDraft(business, id: "d1", lines: [TestStore.line("l2", "Hosting", price: 100_000)])
        let invoice = try await store.documentService.issue(documentID: "d1", deviceID: device.id)
        await #expect(throws: DocumentServiceError.notALiveQuote) {
            try await store.documentService.acceptQuote(documentID: invoice.id)
        }
    }

    @Test func expiredQuotesCanStillBeAcceptedLate() async throws {
        // documents.md §12: `validUntil` having passed does not block accept/decline (status-quote-accepted-after-
        // expiry fixture proves the derived-status side; this proves the write path never even checks it).
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing()
        try await store.saveDraft(business, docType: .quote, id: "q1",
                                  lines: [TestStore.line("l1", "Website", price: 500_000)])
        let quote = try await store.documentService.issue(documentID: "q1", deviceID: device.id)
        _ = try await store.database.writer.write { db in
            try DocumentRecord.live.filter(key: quote.id).updateAll(db, Column("valid_until").set(to: "2020-01-01"))
        }
        let accepted = try await store.documentService.acceptQuote(documentID: quote.id)
        #expect(accepted.quoteOutcome == .accepted)
    }

    @Test func issuedDocumentsKeepTheirImages() async throws {
        let store = try TestStore()
        let (business, device) = try await store.setUpInvoicing(logo: BusinessSetupServiceTests.logo)
        let logoID = try #require(business.logoAssetId)
        try await store.saveDraft(business, lines: [TestStore.line("l1", "Website", price: 100_000)])
        let issued = try await store.documentService.issue(documentID: "d1", deviceID: device.id)
        #expect(issued.sellerSnapshot?.logoAssetId == logoID)

        try await store.setup.setImage(BusinessSetupServiceTests.signature, kind: .logo, businessID: business.id)
        #expect(try await store.assets.fetchAsset(id: logoID) != nil) // still printed on d1
    }
}
