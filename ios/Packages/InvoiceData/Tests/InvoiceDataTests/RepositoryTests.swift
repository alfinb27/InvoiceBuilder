import Foundation
import GRDB
import InvoiceCore
import Synchronization
import Testing
@testable import InvoiceData

/// An in-memory database with every repository, a clock that ticks 1 ms per call and predictable ids.
struct TestStore {
    let database: AppDatabase
    let time: TimeSource
    let ids = IDGenerator.sequential()

    init() throws {
        database = try AppDatabase.inMemory()
        let clock = Mutex<Int64>(1_000)
        time = TimeSource(
            now: { clock.withLock { value in value += 1; return value } },
            today: { LocalDate(iso: "2026-09-19")! }
        )
    }

    var businesses: GRDBBusinessRepository { GRDBBusinessRepository(database: database, time: time) }
    var clients: GRDBClientRepository { GRDBClientRepository(database: database, time: time) }
    var catalog: GRDBCatalogRepository { GRDBCatalogRepository(database: database, time: time) }
    var series: GRDBNumberingSeriesRepository { GRDBNumberingSeriesRepository(database: database, time: time) }
    var assets: GRDBAssetRepository { GRDBAssetRepository(database: database) }
    var device: GRDBDeviceStateRepository { GRDBDeviceStateRepository(database: database, time: time, ids: ids) }
    var setup: GRDBBusinessSetupService { GRDBBusinessSetupService(database: database, time: time, ids: ids) }

    static let fullBusiness = Business(
        id: "b0000000-0000-4000-8000-000000000001", name: "Bharat Web Studio", legalName: "Bharat Web Studio LLP",
        address: Address(line1: "12 MG Road", city: "Bengaluru", regionCode: "29", postalCode: "560001",
                         countryCode: "IN"),
        email: "hello@example.in", phone: "+91 80 5555 0100", website: "https://example.in", countryCode: "IN",
        taxConfig: "IN", taxRegistration: "regular", taxId: "29AAGCB7383J1Z4",
        extraIds: ExtraIDs(pan: "AAGCB7383J", lutReference: "AD2903260123456",
                           lutValidUntil: LocalDate(iso: "2027-03-31")),
        homeCurrency: .inr, turnoverMinor: 5_000_000_001,
        bank: BankDetails(accountName: "Bharat Web Studio LLP", accountNumber: "000123456789", ifsc: "EXMP0001234"),
        upiVpa: "bharatweb@examplebank", paymentTermsDays: 30, defaultNotes: "Thank you", defaultTerms: "Net 30",
        templateId: .classic, accentColor: "#0F766E", reminderDaysAfterDue: 3,
        customRates: [CustomRates.noTax]
    )

    func insertBusiness(_ business: Business = fullBusiness) async throws -> Business {
        try await businesses.save(business)
    }
}

@Suite("Repositories")
struct RepositoryTests {
    @Test func businessRoundTripsEveryField() async throws {
        let store = try TestStore()
        let saved = try await store.insertBusiness()
        #expect(saved.createdAt == 1_001 && saved.updatedAt == 1_001)
        #expect(try await store.businesses.fetchBusiness(id: saved.id) == saved)

        // Clearing optional fields writes NULLs (and keeps created_at).
        var cleared = saved
        cleared.legalName = nil
        cleared.address = nil
        cleared.extraIds = nil
        cleared.bank = nil
        cleared.customRates = nil
        cleared.turnoverMinor = nil
        let updated = try await store.businesses.save(cleared)
        #expect(updated.createdAt == 1_001 && updated.updatedAt == 1_002)
        let fetched = try #require(try await store.businesses.fetchBusiness(id: saved.id))
        #expect(fetched == updated)
        #expect(fetched.address == nil && fetched.bank == nil && fetched.legalName == nil)
    }

    @Test func businessesAreListedOldestFirstWithoutTombstones() async throws {
        let store = try TestStore()
        var first = TestStore.fullBusiness
        first.id = "b2"
        var second = TestStore.fullBusiness
        second.id = "b1"
        var deleted = TestStore.fullBusiness
        deleted.id = "b0"
        deleted.deletedAt = 5
        for business in [first, second, deleted] { try await store.businesses.save(business) }
        #expect(try await store.businesses.fetchBusinesses().map(\.id) == ["b2", "b1"])
        #expect(try await store.businesses.fetchBusiness(id: "b0") == nil)
    }

    @Test func clientsSaveArchiveAndDelete() async throws {
        let store = try TestStore()
        let business = try await store.insertBusiness()
        var client = Client(
            id: "c1", businessId: business.id, name: "Rao Traders", contactName: "K. Rao",
            billingAddress: Address(line1: "5 Residency Road", city: "Bengaluru", regionCode: "29", countryCode: "IN"),
            countryCode: "IN", regionCode: "29", taxId: "29AABCR1234C1ZU", isBusiness: true, defaultCurrency: .inr
        )
        client = try await store.clients.save(client)
        #expect(try await store.clients.fetchClient(id: "c1") == client)

        try await store.clients.setArchived(true, clientID: "c1")
        let archived = try #require(try await store.clients.fetchClient(id: "c1"))
        #expect(archived.isArchived && archived.updatedAt > client.updatedAt)
        try await store.clients.setArchived(false, clientID: "c1")
        #expect(try await store.clients.fetchClient(id: "c1")?.isArchived == false)

        try await store.clients.delete(clientID: "c1")
        #expect(try await store.clients.fetchClient(id: "c1") == nil)
        let tombstone = try await store.database.writer.read { db in try ClientRecord.fetchOne(db, key: "c1") }
        #expect(tombstone?.deletedAt != nil) // a tombstone, not a SQL DELETE
        await #expect(throws: RecordNotFound.self) { try await store.clients.delete(clientID: "c1") }
        await #expect(throws: RecordNotFound.self) { try await store.clients.setArchived(true, clientID: "nope") }
    }

    @Test func observingClientsEmitsCurrentValueThenChanges() async throws {
        let store = try TestStore()
        let business = try await store.insertBusiness()
        var updates = store.clients.observeClients(businessID: business.id).makeAsyncIterator()
        #expect(try await updates.next() == [])

        let client = try await store.clients.save(
            Client(id: "c1", businessId: business.id, name: "Rao Traders", countryCode: "IN"))
        #expect(try await updates.next() == [client])

        try await store.clients.delete(clientID: "c1")
        #expect(try await updates.next() == [])
    }

    @Test func catalogItemsAndRateUsage() async throws {
        let store = try TestStore()
        let business = try await store.insertBusiness()
        let tea = CatalogItem(id: "i1", businessId: business.id, name: "Tea leaves", description: "Assam, 1 kg",
                              kind: .goods, unit: "KGS", unitPriceMinor: 24_000, currency: .inr, rateId: "gst_5",
                              productCode: "0902", priceIncludesTax: true)
        let milk = CatalogItem(id: "i2", businessId: business.id, name: "Milk", kind: .goods, unit: "LTR",
                               unitPriceMinor: 5_600, currency: .inr, rateId: "exempt")
        let savedTea = try await store.catalog.save(tea)
        try await store.catalog.save(milk)
        #expect(try await store.catalog.fetchItem(id: "i1") == savedTea)
        #expect(try await store.catalog.countItems(businessID: business.id, usingRate: "gst_5") == 1)

        try await store.catalog.delete(itemID: "i1")
        #expect(try await store.catalog.countItems(businessID: business.id, usingRate: "gst_5") == 0)
        try await store.catalog.setArchived(true, itemID: "i2")
        #expect(try await store.catalog.fetchItem(id: "i2")?.isArchived == true)
    }

    @Test func numberingSeriesKeepTheirCounters() async throws {
        let store = try TestStore()
        let business = try await store.insertBusiness()
        var invoices = NumberingSeries(id: "s1", businessId: business.id, docType: .invoice, label: "Invoices",
                                       pattern: "INV/{fy}/{seq:4}", reset: .fiscalYear, ownerDeviceId: "d1")
        let quotes = NumberingSeries(id: "s2", businessId: business.id, docType: .quote, label: "Quotes",
                                     pattern: "QT/{fy}/{seq:4}", reset: .fiscalYear, ownerDeviceId: "d1")
        try await store.series.save(quotes)
        invoices = try await store.series.save(invoices)
        var updates = store.series.observeSeries(businessID: business.id).makeAsyncIterator()
        #expect(try await updates.next()?.map(\.id) == ["s1", "s2"]) // invoice before quote

        invoices.counters = ["FY2026": 142]
        try await store.series.save(invoices)
        #expect(try await updates.next()?.first?.counters == ["FY2026": 142])
    }

    @Test func deviceStateIsCreatedOnce() async throws {
        let store = try TestStore()
        let first = try await store.device.loadOrCreate(deviceName: "iPhone")
        let second = try await store.device.loadOrCreate(deviceName: "Other name")
        #expect(first == second)
        #expect(first.id == "00000000-0000-4000-8000-000000000001")
        #expect(first.preferences.activeBusinessId == nil)

        try await store.device.setActiveBusiness(id: "b1")
        #expect(try await store.device.loadOrCreate(deviceName: "iPhone").preferences.activeBusinessId == "b1")
    }
}

@Suite("Business setup service")
struct BusinessSetupServiceTests {
    static let logo = ImagePayload(mime: ImagePayload.png, data: Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]))
    static let signature = ImagePayload(mime: ImagePayload.png, data: Data([0x89, 0x50, 0x4E, 0x47, 9, 9]))

    @Test func createsEverythingInOneTransaction() async throws {
        let store = try TestStore()
        let device = try await store.device.loadOrCreate(deviceName: "iPhone")
        let config = try #require(try TaxConfigStore.bundled().latest(family: "IN"))
        let business = TestStore.fullBusiness
        let series = BusinessSetup.defaultSeries(businessID: business.id, config: config, ownerDeviceID: device.id,
                                                 now: 0, newID: store.ids.make)

        let created = try await store.setup.createBusiness(business, series: series, logo: Self.logo,
                                                           signature: Self.signature, deviceID: device.id)
        #expect(try await store.businesses.fetchBusiness(id: business.id) == created)
        let logoID = try #require(created.logoAssetId)
        let signatureID = try #require(created.signatureAssetId)
        let logo = try #require(try await store.assets.fetchAsset(id: logoID))
        #expect(logo.kind == .logo && logo.data == Self.logo.data && logo.mime == "image/png")
        #expect(logo.sha256 == "cdf3cefe7ec6253d1cb4828ab654da6beb8a4727daac0c49dbf26bedf5887f79") // shasum -a 256
        #expect(try await store.assets.fetchAsset(id: signatureID)?.kind == .signature)

        var updates = store.series.observeSeries(businessID: business.id).makeAsyncIterator()
        #expect(try await updates.next()?.map(\.pattern) == ["INV/{fy}/{seq:4}", "QT/{fy}/{seq:4}"])
        #expect(try await store.device.loadOrCreate(deviceName: "x").preferences.activeBusinessId == business.id)
    }

    @Test func failureLeavesNothingBehind() async throws {
        let store = try TestStore()
        let device = try await store.device.loadOrCreate(deviceName: "iPhone")
        let business = TestStore.fullBusiness
        // A series pointing at a business that does not exist violates its foreign key.
        let orphan = NumberingSeries(id: "s1", businessId: "missing", docType: .invoice, label: "Invoices",
                                     pattern: "INV-{seq:4}", reset: .never, ownerDeviceId: device.id)
        await #expect(throws: (any Error).self) {
            try await store.setup.createBusiness(business, series: [orphan], logo: Self.logo, signature: nil,
                                                 deviceID: device.id)
        }
        #expect(try await store.businesses.fetchBusinesses().isEmpty)
        let assetCount = try await store.database.writer.read { db in try AssetRecord.fetchCount(db) }
        #expect(assetCount == 0)
        #expect(try await store.device.loadOrCreate(deviceName: "x").preferences.activeBusinessId == nil)
    }

    @Test func replacingAnImageTombstonesTheOldOne() async throws {
        let store = try TestStore()
        let device = try await store.device.loadOrCreate(deviceName: "iPhone")
        let created = try await store.setup.createBusiness(TestStore.fullBusiness, series: [], logo: Self.logo,
                                                           signature: nil, deviceID: device.id)
        let oldLogo = try #require(created.logoAssetId)

        // The same bytes again reuse the stored asset.
        let same = try await store.setup.setImage(Self.logo, kind: .logo, businessID: created.id)
        #expect(same.logoAssetId == oldLogo)

        let replaced = try await store.setup.setImage(Self.signature, kind: .logo, businessID: created.id)
        #expect(replaced.logoAssetId != oldLogo)
        #expect(try await store.assets.fetchAsset(id: oldLogo) == nil) // tombstoned

        let removed = try await store.setup.setImage(nil, kind: .logo, businessID: created.id)
        #expect(removed.logoAssetId == nil)
        let replacedID = try #require(replaced.logoAssetId)
        #expect(try await store.assets.fetchAsset(id: replacedID) == nil)
        #expect(try await store.businesses.fetchBusiness(id: created.id)?.logoAssetId == nil)
    }
}
