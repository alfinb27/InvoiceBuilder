import Foundation
import GRDB
import InvoiceCore
import Testing
@testable import InvoiceData

extension TestStore {
    var numbering: GRDBNumberingService {
        GRDBNumberingService(database: database, time: time, ids: ids, configs: Self.configs)
    }
}

/// Two devices on one (synced) database: device A set the business up; device B arrives later.
@Suite("Numbering on several devices")
struct NumberingServiceTests {
    static let deviceB = "dddddddd-0000-4000-8000-00000000000b"

    @Test func aSecondDeviceStartsItsOwnSeries() async throws {
        let store = try TestStore()
        let (business, deviceA) = try await store.setUpInvoicing()
        try await store.saveDraft(business, id: "a1", lines: [TestStore.line("l1", "Work", price: 1_000)])
        let first = try await store.documentService.issue(documentID: "a1", deviceID: deviceA.id)
        #expect(first.number == "INV/26-27/0001")

        // B owns nothing yet: issuing is blocked, nothing is written.
        try await store.saveDraft(business, id: "b1", lines: [TestStore.line("l2", "Work", price: 1_000)])
        await #expect(throws: DocumentServiceError.blocked([.noSeries])) {
            try await store.documentService.issue(documentID: "b1", deviceID: Self.deviceB)
        }

        let series = try await store.numbering.createDeviceSeries(businessID: business.id, docType: .invoice,
                                                                  deviceID: Self.deviceB)
        #expect(series.pattern == "INV/{fy}/B{seq:4}" && series.label == "Invoices (B)")
        let fromB = try await store.documentService.issue(documentID: "b1", deviceID: Self.deviceB)
        #expect(fromB.number == "INV/26-27/B0001")

        // A keeps its own sequence.
        try await store.saveDraft(business, id: "a2", lines: [TestStore.line("l3", "Work", price: 1_000)])
        #expect(try await store.documentService.issue(documentID: "a2", deviceID: deviceA.id).number
                == "INV/26-27/0002")

        // A third device gets the next letter.
        let third = try await store.numbering.createDeviceSeries(businessID: business.id, docType: .invoice,
                                                                 deviceID: "third")
        #expect(third.pattern == "INV/{fy}/C{seq:4}")
    }

    @Test func takingOverContinuesAfterTheHighestIssuedNumber() async throws {
        let store = try TestStore()
        let (business, deviceA) = try await store.setUpInvoicing()
        for index in 1...3 {
            try await store.saveDraft(business, id: "a\(index)", lines: [TestStore.line("l\(index)", "W", price: 100)])
            _ = try await store.documentService.issue(documentID: "a\(index)", deviceID: deviceA.id)
        }
        // A's counter fell behind (e.g. an older synced copy of the series): the takeover still continues after 3.
        let original = try #require(try await store.database.writer.read { db in
            try NumberingSeriesRecord.live.filter(Column("doc_type") == "invoice").fetchOne(db)?.series()
        })
        try await store.database.writer.write { db in
            var stale = original
            stale.counters = [:]
            try NumberingSeriesRecord(stale).update(db)
        }

        let taken = try await store.numbering.takeOver(seriesID: original.id, deviceID: Self.deviceB)
        #expect(taken.ownerDeviceId == Self.deviceB)
        try await store.saveDraft(business, id: "b1", lines: [TestStore.line("l9", "W", price: 100)])
        #expect(try await store.documentService.issue(documentID: "b1", deviceID: Self.deviceB).number
                == "INV/26-27/0004")
        // A no longer owns an invoice series.
        try await store.saveDraft(business, id: "a9", lines: [TestStore.line("l10", "W", price: 100)])
        await #expect(throws: DocumentServiceError.blocked([.noSeries])) {
            try await store.documentService.issue(documentID: "a9", deviceID: deviceA.id)
        }
    }

    @Test func duplicateNumbersAreReported() async throws {
        let store = try TestStore()
        let (business, deviceA) = try await store.setUpInvoicing()
        try await store.saveDraft(business, id: "a1", lines: [TestStore.line("l1", "W", price: 100)])
        let issued = try await store.documentService.issue(documentID: "a1", deviceID: deviceA.id)

        var duplicates = store.numbering.observeDuplicateNumbers(businessID: business.id).makeAsyncIterator()
        #expect(try await duplicates.next() == [])

        // A hand-edited backup (or a bug) brings a second document with the same number.
        try await store.saveDraft(business, id: "a2", lines: [TestStore.line("l2", "W", price: 100)])
        try await store.database.writer.write { db in
            try db.execute(sql: "UPDATE document SET lifecycle = 'issued', number = ? WHERE id = 'a2'",
                           arguments: [issued.number])
        }
        let groups = try await duplicates.next()
        #expect(groups?.count == 1 && groups?.first?.ids == ["a1", "a2"] && groups?.first?.number == issued.number)
    }
}
