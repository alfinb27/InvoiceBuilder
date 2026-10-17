import Foundation
import GRDB
import InvoiceCore
import Testing
@testable import InvoiceData

/// A backup moves between an iPhone and an Android phone (`spec/backup.md` §1): each app's tests restore a file the
/// other app exported. Both apps build the same business (`populateSample`; Android: `CrossPlatformBackupTests.kt`)
/// and export it to `spec/samples/backup-v1-from-<platform>.invoicebackup.json`. `make backup-samples` writes the
/// files again when an export changes.
extension TestStore {
    static let samples: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url.appending(path: "spec/samples")
    }()

    static let sampleApp = BackupFile.AppInfo(platform: "ios", version: "sample")
    static let raoTraders = "c0000000-0000-4000-8000-000000000001"
    static let mehtaExports = "c0000000-0000-4000-8000-000000000002"
    /// 4×4 and 4×2 PNGs, the same bytes on Android.
    static let sampleLogo = ImagePayload(mime: ImagePayload.png, data: Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR42mM45KH1HxkzkC4AAKgYIzHyuLugAAAAAElFTkSuQmCC")!)
    static let sampleSignature = ImagePayload(mime: ImagePayload.png, data: Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAAEUlEQVR42mOQElX4j4wZ0AUApqoKcQiRqlwAAAAASUVORK5CYII=")!)

    /// The full business with a logo and a signature; three live clients (one in another state, one archived) and a
    /// deleted one; two items (one archived, priced with tax); an invoice with line and document discounts, partly
    /// paid (a live and a deleted payment); an inter-state invoice with shipping, sent and paid in full; a void
    /// invoice; a quote converted into an invoice draft; a draft with a decimal quantity; a deleted draft.
    func populateSample() async throws -> DeviceState {
        let device = try await self.device.loadOrCreate(deviceName: "iPhone")
        let config = try #require(Self.configs.latest(family: "IN"))
        let series = BusinessSetup.defaultSeries(businessID: Self.fullBusiness.id, config: config,
                                                 ownerDeviceID: device.id, now: 0, newID: ids.make)
        let business = try await setup.createBusiness(Self.fullBusiness, series: series, logo: Self.sampleLogo,
                                                      signature: Self.sampleSignature, deviceID: device.id)
        try await clients.save(Client(
            id: Self.raoTraders, businessId: business.id, name: "Rao Traders", contactName: "Anil Rao",
            email: "accounts@raotraders.example", phone: "+91 80 5555 0199",
            billingAddress: Address(line1: "5 Residency Road", city: "Bengaluru", regionCode: "29",
                                    postalCode: "560025", countryCode: "IN"),
            shippingAddress: Address(line1: "Plot 7", line2: "Peenya Industrial Area", city: "Bengaluru",
                                     regionCode: "29", postalCode: "560058", countryCode: "IN"),
            countryCode: "IN", regionCode: "29", taxId: "29AABCR1234C1ZU", isBusiness: true, notes: "Pays by UPI"
        ))
        try await clients.save(Client(
            id: Self.mehtaExports, businessId: business.id, name: "Mehta Exports",
            billingAddress: Address(line1: "21 Nariman Point", city: "Mumbai", regionCode: "27", postalCode: "400021",
                                    countryCode: "IN"),
            countryCode: "IN", regionCode: "27", taxId: "27AAECM5678F1Z6", isBusiness: true
        ))
        try await clients.save(Client(id: "c0000000-0000-4000-8000-000000000003", businessId: business.id,
                                      name: "Old Client", countryCode: "IN", regionCode: "29", archivedAt: 1_500))
        try await clients.save(Client(id: "c0000000-0000-4000-8000-000000000004", businessId: business.id,
                                      name: "Gone Ltd", countryCode: "IN", regionCode: "29"))
        try await clients.delete(clientID: "c0000000-0000-4000-8000-000000000004")

        let website = CatalogItem(id: "ca000000-0000-4000-8000-000000000001", businessId: business.id,
                                  name: "Website design", description: "Design and build, up to five pages",
                                  kind: .service, unit: "JOB", unitPriceMinor: 5_000_000, currency: .inr,
                                  rateId: "gst_18", productCode: "998314")
        try await catalog.save(website)
        try await catalog.save(CatalogItem(id: "ca000000-0000-4000-8000-000000000002", businessId: business.id,
                                           name: "Printed brochures", kind: .goods, unit: "NOS", unitPriceMinor: 2_500,
                                           currency: .inr, rateId: "gst_5", productCode: "4911",
                                           priceIncludesTax: true, archivedAt: 1_500))

        let partlyPaid = try await sampleDraft(business, id: "d0000000-0000-4000-8000-000000000001",
                                               client: Self.raoTraders, lines: [
            LineItem(id: "da000000-0000-4000-8000-000000000001", catalogItemId: website.id,
                     description: "Website design", productCode: "998314", unit: "JOB", unitPriceMinor: 5_000_000,
                     discount: .percent("10"), rateId: "gst_18"),
            LineItem(id: "da000000-0000-4000-8000-000000000002", description: "Hosting", productCode: "998315",
                     unit: "MON", quantity: "12", unitPriceMinor: 120_000, rateId: "gst_18"),
        ]) { document in
            document.discount = .amount(50_000)
            document.notes = "Thank you for your business"
            document.terms = "Payment within 30 days"
        }
        _ = try await documentService.issue(documentID: partlyPaid.id, deviceID: device.id)
        _ = try await paymentService.recordPayment(documentID: partlyPaid.id, amountMinor: 1_000_000,
                                                   date: time.today(), method: .upi, reference: "UTR1", note: nil)
        let wrong = try await paymentService.recordPayment(documentID: partlyPaid.id, amountMinor: 1,
                                                           date: time.today(), method: .cash, reference: nil,
                                                           note: "Typed by mistake")
        try await payments.softDelete(paymentID: wrong.id)

        let interState = try await sampleDraft(business, id: "d0000000-0000-4000-8000-000000000002",
                                               client: Self.mehtaExports, lines: [
            LineItem(id: "da000000-0000-4000-8000-000000000003", description: "Logo pack", productCode: "998391",
                     unit: "JOB", unitPriceMinor: 1_500_000, rateId: "gst_18"),
        ]) { document in
            document.shippingMinor = 25_000
        }
        let sent = try await documentService.issue(documentID: interState.id, deviceID: device.id)
        try await documents.markSent(documentID: sent.id, at: time.now())
        _ = try await paymentService.recordPayment(documentID: sent.id, amountMinor: sent.totals.totalMinor,
                                                   date: time.today(), method: .bank, reference: "NEFT42", note: nil)

        let mistake = try await sampleDraft(business, id: "d0000000-0000-4000-8000-000000000003",
                                            client: Self.raoTraders, lines: [
            LineItem(id: "da000000-0000-4000-8000-000000000004", description: "Mistake", unitPriceMinor: 1_000,
                     rateId: "gst_18"),
        ])
        _ = try await documentService.issue(documentID: mistake.id, deviceID: device.id)
        _ = try await documentService.voidDocument(documentID: mistake.id, reason: "Raised twice")

        let quote = try await sampleDraft(business, .quote, id: "d0000000-0000-4000-8000-000000000004",
                                          client: Self.raoTraders, lines: [
            LineItem(id: "da000000-0000-4000-8000-000000000005", description: "Security audit", unit: "HRS",
                     quantity: "6", unitPriceMinor: 250_000, rateId: "gst_18"),
        ])
        _ = try await documentService.issue(documentID: quote.id, deviceID: device.id)
        _ = try await documentService.convertQuote(documentID: quote.id)

        _ = try await sampleDraft(business, id: "d0000000-0000-4000-8000-000000000005", client: Self.mehtaExports,
                                  lines: [
            LineItem(id: "da000000-0000-4000-8000-000000000006", description: "Consulting", unit: "HRS",
                     quantity: "2.5", unitPriceMinor: 300_000, rateId: "gst_18"),
        ])
        let dropped = try await sampleDraft(business, id: "d0000000-0000-4000-8000-000000000006",
                                            client: Self.raoTraders, lines: [
            LineItem(id: "da000000-0000-4000-8000-000000000007", description: "Dropped", unitPriceMinor: 10_000,
                     rateId: "gst_18"),
        ])
        try await documentService.deleteDraft(documentID: dropped.id)
        return device
    }

    func sampleDraft(_ business: Business, _ docType: DocumentType = .invoice, id: String, client clientID: String,
                     lines: [LineItem], edit: (inout Document) -> Void = { _ in }) async throws -> Document {
        let rules = try rules(business)
        let client = try await clients.fetchClient(id: clientID)
        var document = rules.newDocument(docType: docType, id: id, today: time.today(), client: client, now: 0)
        document.lines = lines
        edit(&document)
        return try await documents.saveDraft(rules.preparedDraft(document, client: client))
    }

    func taxComponents() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT component FROM tax_line WHERE deleted_at IS NULL ORDER BY 1")
        }
    }
}

@Suite("Backups between the apps")
struct CrossPlatformBackupTests {
    /// What `populateSample` leaves live, on either app.
    static let live = BackupCounts(businesses: 1, clients: 3, catalogItems: 2, numberingSeries: 2, documents: 6,
                                   payments: 2, assets: 2)

    static func sample(from platform: String) -> URL {
        TestStore.samples.appending(path: "backup-v1-from-\(platform).invoicebackup.json")
    }

    @Test func aBackupExportedOnAndroidRestores() async throws {
        let bytes = try Data(contentsOf: Self.sample(from: "android"))
        let preview = try BackupCodec.validate(bytes, appSchemaVersion: AppDatabase.schemaVersion()).get()
        #expect(preview.file.app.platform == "android")
        #expect(preview.live == Self.live)

        let store = try TestStore()
        let device = try await store.device.loadOrCreate(deviceName: "iPhone")
        try await store.backupService().restore(preview.file, deviceID: device.id)
        // Every record comes back as Android wrote it; the one change is that this device takes over the series.
        var expected = preview.file.data.sorted()
        expected.numberingSeries = expected.numberingSeries.map { var series = $0; series.ownerDeviceId = device.id
            series.updatedAt = 0; return series }
        var exported = try await store.backupService().makeBackup(app: TestStore.sampleApp).data
        exported.numberingSeries = exported.numberingSeries.map { var series = $0; series.updatedAt = 0; return series }
        #expect(exported == expected)
        // The tax lines are rebuilt from the stored results: IGST for the other state, CGST and SGST at home.
        #expect(try await store.taxComponents() == ["CGST", "IGST", "SGST"])

        // Numbering carries on from the last invoice issued on the Android phone.
        let business = try #require(preview.file.data.businesses.first)
        let next = try await store.sampleDraft(business, id: "d0000000-0000-4000-8000-0000000000ff",
                                               client: TestStore.raoTraders, lines: [
            LineItem(id: "da000000-0000-4000-8000-0000000000ff", description: "Next", unitPriceMinor: 10_000,
                     rateId: "gst_18"),
        ])
        let issued = try await store.documentService.issue(documentID: next.id, deviceID: device.id)
        #expect(issued.number == "INV/26-27/0004")
    }

    /// The iOS file in spec/samples is what this app exports today, so the Android tests restore a current file.
    /// `make backup-samples` (BACKUP_SAMPLES=write) writes it again.
    @Test func theIOSSampleIsWhatThisAppExports() async throws {
        let store = try TestStore()
        _ = try await store.populateSample()
        let file = try await store.backupService().makeBackup(app: TestStore.sampleApp)
        let url = Self.sample(from: "ios")
        if ProcessInfo.processInfo.environment["BACKUP_SAMPLES"] == "write" {
            try BackupCodec.encode(file).write(to: url)
        }
        let committed = try BackupCodec.validate(try Data(contentsOf: url),
                                                 appSchemaVersion: AppDatabase.schemaVersion()).get()
        #expect(committed.file == file, "the iOS export changed: run `make backup-samples` and commit spec/samples")
        #expect(committed.live == Self.live)
    }
}
