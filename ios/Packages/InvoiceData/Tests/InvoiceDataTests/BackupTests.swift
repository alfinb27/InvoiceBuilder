import Foundation
import GRDB
import InvoiceCore
import Testing
@testable import InvoiceData

extension TestStore {
    func backupService(snapshots: BackupSnapshotStore = .temporary()) throws -> GRDBBackupService {
        try GRDBBackupService(database: database, time: time, ids: ids, snapshots: snapshots)
    }

    static let app = BackupFile.AppInfo(platform: "ios", version: "test")

    /// A business with a logo, a live and a deleted client, an item, an issued invoice with a live and a deleted
    /// payment, a void invoice, a converted quote, a draft and a deleted draft.
    func populate() async throws -> DeviceState {
        let (business, device) = try await setUpInvoicing(logo: ImagePayload(mime: ImagePayload.png,
                                                                             data: Data([0x89, 0x50, 0x4e, 0x47])))
        try await catalog.save(CatalogItem(id: "i1", businessId: business.id, name: "Website", kind: .service,
                                           unit: "JOB", unitPriceMinor: 500_000, currency: .inr, rateId: "gst_18"))
        try await clients.save(Client(id: "c2", businessId: business.id, name: "Gone Ltd", countryCode: "IN",
                                      regionCode: "29"))

        var withItem = TestStore.line("l1", "Website", price: 1_000_000)
        withItem.catalogItemId = "i1"
        try await saveDraft(business, id: "d1", lines: [withItem, TestStore.line("l2", "Hosting", price: 120_000)])
        let issued = try await documentService.issue(documentID: "d1", deviceID: device.id)
        try await paymentService.recordPayment(documentID: issued.id, amountMinor: 200_000, date: time.today(),
                                               method: .upi, reference: "UTR1", note: nil)
        let wrong = try await paymentService.recordPayment(documentID: issued.id, amountMinor: 1, date: time.today(),
                                                           method: .cash, reference: nil, note: nil)
        try await payments.softDelete(paymentID: wrong.id)

        try await saveDraft(business, id: "d2", lines: [TestStore.line("l3", "Mistake", price: 1_000)])
        _ = try await documentService.issue(documentID: "d2", deviceID: device.id)
        _ = try await documentService.voidDocument(documentID: "d2", reason: "Raised twice")

        try await saveDraft(business, docType: .quote, id: "q1", lines: [TestStore.line("l4", "Audit", price: 50_000)])
        _ = try await documentService.issue(documentID: "q1", deviceID: device.id)
        _ = try await documentService.convertQuote(documentID: "q1")

        try await saveDraft(business, id: "d3", lines: [TestStore.line("l5", "Later", price: 10_000)])
        try await saveDraft(business, id: "d4", lines: [TestStore.line("l6", "Dropped", price: 10_000)])
        try await documentService.deleteDraft(documentID: "d4")
        try await clients.delete(clientID: "c2")
        return device
    }

    func liveTaxLines() async throws -> [String] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT document_id, component, rate, category, taxable_minor, tax_minor, charged FROM tax_line
                WHERE deleted_at IS NULL ORDER BY document_id, component, rate
                """).map(\.description)
        }
    }

    func rowCounts() async throws -> [String: Int] {
        try await database.writer.read { db in
            var counts: [String: Int] = [:]
            for table in ["business", "client", "catalog_item", "numbering_series", "document", "line_item",
                          "tax_line", "payment", "asset"] {
                counts[table] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)")
            }
            return counts
        }
    }
}

@Suite("Backup")
struct BackupTests {
    @Test func roundTripIsLossless() async throws {
        let source = try TestStore()
        let device = try await source.populate()
        let file = try await source.backupService().makeBackup(app: TestStore.app)
        #expect(file.counts == file.data.counts)
        #expect(file.data.liveCounts.documents == 5 && file.data.documents.count == 6)
        #expect(file.data.clients.contains { $0.id == "c2" && $0.deletedAt != nil })
        #expect(file.data.assets.count == 1)

        // The bytes validate as a backup this app can read.
        let bytes = try BackupCodec.encode(file)
        let preview = try BackupCodec.validate(bytes, appSchemaVersion: AppDatabase.schemaVersion()).get()
        #expect(preview.file == file)

        // "Wipe": a new database on the same device.
        let target = try TestStore()
        let sameDevice = try await target.database.writer.write { db in
            var record = try DeviceStateRecord(device)
            record.createdAt = 0
            try record.insert(db)
            return record
        }
        #expect(sameDevice.id == device.id)
        try await target.backupService().restore(preview.file, deviceID: device.id)

        let again = try await target.backupService().makeBackup(app: TestStore.app)
        #expect(again.data == file.data)
        #expect(try await target.liveTaxLines() == (try await source.liveTaxLines()))
    }

    @Test func restoreReplacesEverythingWithTombstonesAndASnapshot() async throws {
        let source = try TestStore()
        _ = try await source.populate()
        let file = try await source.backupService().makeBackup(app: TestStore.app)

        // A device with different data of its own.
        let target = try TestStore()
        let device = try await target.device.loadOrCreate(deviceName: "iPad")
        try await target.businesses.save(Business(id: "other", name: "Other Co", countryCode: "GB", taxConfig: "GB",
                                                  taxRegistration: "vat", homeCurrency: .gbp, paymentTermsDays: 14,
                                                  templateId: .modern))
        try await target.clients.save(Client(id: "oc", businessId: "other", name: "Someone", countryCode: "GB"))
        let before = try await target.backupService().makeBackup(app: TestStore.app)

        let snapshots = BackupSnapshotStore.temporary()
        try await target.backupService(snapshots: snapshots).restore(file, deviceID: device.id)

        // The old rows are tombstones, not gone.
        let old = try #require(try await target.database.writer.read { db in
            try BusinessRecord.fetchOne(db, key: "other")
        })
        #expect(old.deletedAt != nil)
        #expect(try await target.businesses.fetchBusinesses().map(\.id) == [TestStore.fullBusiness.id])

        // The snapshot holds what was there before.
        let written = try snapshots.snapshots()
        #expect(written.count == 1)
        let snapshot = try BackupCodec.validate(Data(contentsOf: written[0]),
                                               appSchemaVersion: AppDatabase.schemaVersion()).get()
        #expect(snapshot.file.data == before.data)

        // This device had no series of its own for the restored business: it takes them over.
        let series = try await target.database.writer.read { db in
            try NumberingSeriesRecord.live.fetchAll(db)
        }
        #expect(!series.isEmpty && series.allSatisfy { $0.ownerDeviceId == device.id })

        // And it can issue the next number straight away, after the restored ones.
        let business = try #require(try await target.businesses.fetchBusiness(id: TestStore.fullBusiness.id))
        let rules = try target.rules(business)
        var draft = rules.newDocument(docType: .invoice, id: "new", today: target.time.today(), client: nil, now: 0)
        draft.lines = [TestStore.line("n1", "More work", price: 10_000)]
        _ = try await target.documents.saveDraft(rules.preparedDraft(draft, client: nil))
        let issued = try await target.documentService.issue(documentID: "new", deviceID: device.id)
        let numbers = file.data.documents.compactMap(\.number)
        #expect(issued.number != nil && !numbers.contains(issued.number!))
    }

    @Test func aFailedRestoreChangesNothing() async throws {
        let store = try TestStore()
        let device = try await store.populate()
        let service = try store.backupService()
        let before = try await service.makeBackup(app: TestStore.app)
        let counts = try await store.rowCounts()

        // A file that passes nothing would get here, but the database itself refuses it mid-transaction.
        var broken = before
        broken.data.payments[0].amountMinor = 0 // CHECK (amount_minor > 0)
        broken.data.clients.append(Client(id: "new-client", businessId: TestStore.fullBusiness.id, name: "New",
                                          countryCode: "IN"))
        await #expect(throws: (any Error).self) {
            try await service.restore(broken, deviceID: device.id)
        }
        let after = try await service.makeBackup(app: TestStore.app)
        #expect(after.data == before.data)
        #expect(try await store.rowCounts() == counts)
    }

    @Test func snapshotsKeepTheNewestThree() throws {
        let store = BackupSnapshotStore.temporary()
        let file = BackupFile(createdAt: 0, app: TestStore.app, dbSchemaVersion: 3, data: BackupData())
        for stamp in [10, 40, 20, 30] as [Int64] { try store.write(file, at: stamp) }
        #expect(try store.snapshots().map(\.lastPathComponent) == [
            "pre-restore-40.invoicebackup", "pre-restore-30.invoicebackup", "pre-restore-20.invoicebackup",
        ])
    }

    @Test func theSpecSampleRestoresAndExportsTheSameData() async throws {
        // The file both platforms read (spec/samples): restoring it and exporting again gives the same records.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        let bytes = try Data(contentsOf: url.appending(path: "spec/samples/backup-v1-sample.invoicebackup.json"))
        let preview = try BackupCodec.validate(bytes, appSchemaVersion: AppDatabase.schemaVersion()).get()

        let store = try TestStore()
        let device = try await store.device.loadOrCreate(deviceName: "iPhone")
        try await store.backupService().restore(preview.file, deviceID: device.id)
        var expected = preview.file.data.sorted()
        // The one change restoring makes: this device takes over the series it needs to keep numbering.
        expected.numberingSeries = expected.numberingSeries.map { var series = $0; series.ownerDeviceId = device.id
            series.updatedAt = 0; return series }
        var exported = try await store.backupService().makeBackup(app: TestStore.app).data
        exported.numberingSeries = exported.numberingSeries.map { var series = $0; series.updatedAt = 0; return series }
        #expect(exported == expected)
        let taxLines = try await store.liveTaxLines()
        #expect(taxLines.count == 2) // CGST + SGST rebuilt from the stored result
    }

    @Test func statusTracksLastBackupAndIssuedDocuments() async throws {
        let store = try TestStore()
        let service = try store.backupService()
        var statuses = service.observeStatus().makeAsyncIterator()
        let first = try await statuses.next()
        #expect(first == BackupStatus(lastBackupAt: nil, hasIssuedDocuments: false))

        try await service.recordBackup(at: 1_789_800_000_000)
        let second = try await statuses.next()
        #expect(second?.lastBackupAt == 1_789_800_000_000)

        let today = LocalDate(iso: "2026-09-19")!
        let utc = TimeZone(identifier: "UTC")!
        // 1_789_800_000_000 ms = 2026-09-19 06:40 UTC.
        #expect(second?.daysSinceLastBackup(today: today, timeZone: utc) == 0)
        #expect(BackupStatus(lastBackupAt: nil, hasIssuedDocuments: false).isDue(today: today) == false)
        #expect(BackupStatus(lastBackupAt: nil, hasIssuedDocuments: true).isDue(today: today) == true)
        let status = BackupStatus(lastBackupAt: 1_789_800_000_000, hasIssuedDocuments: true)
        #expect(status.isDue(today: today.adding(days: 29), timeZone: utc) == false)
        #expect(status.isDue(today: today.adding(days: 30), timeZone: utc) == true)
    }
}
