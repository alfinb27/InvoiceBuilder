import Foundation
import ImageIO
import InvoiceCore
import InvoiceData
import Testing
@testable import InvoiceUI

/// In-memory dependencies with a fixed clock (2026-09-19) and predictable ids.
@MainActor
enum TestEnvironment {
    static let today = LocalDate(iso: "2026-09-19")!

    /// A cache of its own per session, so a test never reads a file another test wrote.
    static func pdfDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "InvoicePDFTests-\(UUID().uuidString)")
    }

    static func dependencies(notifications: any NotificationScheduling = NoOpNotificationScheduler()) throws
        -> AppDependencies {
        try AppDependencies.make(database: AppDatabase.inMemory(), time: .fixed(now: 1_789_800_000_000, today: today),
                                 ids: .sequential(), notifications: notifications)
    }

    /// A seeded, onboarded business and its session. `notifications` defaults to a no-op; pass a fake to test
    /// reminder reconciliation.
    static func session(_ country: SampleData.Country = .india,
                        notifications: any NotificationScheduling = NoOpNotificationScheduler()) async throws
        -> Session {
        let dependencies = try dependencies(notifications: notifications)
        let device = try await dependencies.deviceState.loadOrCreate(deviceName: "Test")
        let business = try await SampleData.seed(country, dependencies: dependencies, deviceID: device.id)
        return try Session(dependencies: dependencies, business: business, deviceID: device.id,
                           pdfDirectory: pdfDirectory())
    }

    /// A GENERIC (United States) business that charges an 8.875% sales tax.
    static func genericSession() async throws -> Session {
        let dependencies = try dependencies()
        let device = try await dependencies.deviceState.loadOrCreate(deviceName: "Test")
        let config = try #require(dependencies.taxConfigs.latest(family: "GENERIC"))
        var draft = BusinessDraft()
        draft.countryCode = "US"
        draft.homeCurrency = "USD"
        draft.taxRegistration = "registered"
        draft.genericTaxName = "Sales tax"
        draft.genericTaxPercent = "8.875"
        draft.name = "Main St Bakery"
        draft.address = AddressDraft(line1: "200 Main St")
        let business = BusinessRules(config: config).makeBusiness(
            from: draft, id: dependencies.ids.make(), now: 1, today: today, newID: dependencies.ids.make)
        let created = try await dependencies.setup.createBusiness(business, series: [], logo: nil, signature: nil,
                                                                  deviceID: device.id)
        return try Session(dependencies: dependencies, business: created, deviceID: device.id,
                           pdfDirectory: pdfDirectory())
    }
}

@MainActor
final class Box<Value> {
    var value: Value?
}

@MainActor
@Suite("Onboarding")
struct OnboardingViewModelTests {
    @Test func indianRegularDealerFromStartToFinish() async throws {
        let dependencies = try TestEnvironment.dependencies()
        let device = try await dependencies.deviceState.loadOrCreate(deviceName: "Test")
        let finished = Box<Business>()
        let model = OnboardingViewModel(dependencies: dependencies, deviceID: device.id) { finished.value = $0 }

        model.continueTapped()
        #expect(model.state.step == .country)
        #expect(model.visibleIssue(.country) == .required)

        model.selectCountry("IN")
        #expect(model.state.draft.taxRegistration == "regular")
        #expect(model.state.draft.homeCurrency == .inr)
        model.continueTapped()
        #expect(model.state.step == .registration)
        model.continueTapped()
        #expect(model.state.step == .business)
        #expect(model.title(for: .bank) == "Bank and UPI")

        model.state.draft.name = "Bharat Test Studio"
        model.state.draft.taxId = "29aagcb7383j1z4"
        #expect(model.state.draft.pan == "AAGCB7383J") // derived from the GSTIN
        #expect(model.taxIDFeedback == .valid("Karnataka"))
        model.continueTapped()
        #expect(model.state.step == .business)
        #expect(model.visibleIssue(.addressLine1) == .required)
        #expect(model.visibleIssue(.region) == nil) // the GSTIN names the state

        model.state.draft.address.line1 = "12 MG Road"
        model.continueTapped()
        #expect(model.state.step == .bank)
        model.continueTapped()
        #expect(model.state.step == .images)
        #expect(model.isLastStep)

        await model.finish()
        let business = try #require(finished.value)
        #expect(business.taxId == "29AAGCB7383J1Z4")
        #expect(business.address?.regionCode == "29")
        #expect(try await dependencies.businesses.fetchBusinesses().map(\.id) == [business.id])
        let series = try await firstValue(dependencies.numberingSeries.observeSeries(businessID: business.id))
        #expect(series?.map(\.pattern) == ["INV/{fy}/{seq:4}", "QT/{fy}/{seq:4}"])
        #expect(series?.allSatisfy { $0.ownerDeviceId == device.id } == true)
        let state = try await dependencies.deviceState.loadOrCreate(deviceName: "Test")
        #expect(state.preferences.activeBusinessId == business.id)
    }

    @Test func changingCountryStartsTheRegistrationAgain() throws {
        let model = OnboardingViewModel(dependencies: try TestEnvironment.dependencies(), deviceID: "d") { _ in }
        model.selectCountry("IN")
        model.state.draft.taxRegistration = "composition"
        model.state.draft.regionCode = "29"
        model.selectCountry("GB")
        #expect(model.state.draft.taxRegistration == "vatRegistered")
        #expect(model.state.draft.homeCurrency == .gbp)
        #expect(model.state.draft.regionCode == nil)
        #expect(model.title(for: .bank) == "Bank details")
    }

    @Test func genericCountriesNeedAHomeCurrency() throws {
        let model = OnboardingViewModel(dependencies: try TestEnvironment.dependencies(), deviceID: "d") { _ in }
        model.selectCountry("US")
        #expect(model.config?.family == "GENERIC")
        model.continueTapped()
        #expect(model.state.step == .country)
        #expect(model.visibleIssue(.homeCurrency) == .required)
        model.state.draft.homeCurrency = "USD"
        model.continueTapped()
        #expect(model.state.step == .registration)
        #expect(model.issues(for: .registration)[.genericTaxPercent] == .required)
    }

    @Test func sidebarOnlyOpensCompletedSteps() throws {
        let model = OnboardingViewModel(dependencies: try TestEnvironment.dependencies(), deviceID: "d") { _ in }
        #expect(model.canVisit(.country))
        #expect(!model.canVisit(.registration))
        model.go(to: .business)
        #expect(model.state.step == .country)
        model.selectCountry("GB")
        #expect(model.canVisit(.business))
        #expect(!model.canVisit(.bank)) // business details are still empty
    }

    @Test func finishJumpsToTheFirstIncompleteStep() async throws {
        let model = OnboardingViewModel(dependencies: try TestEnvironment.dependencies(), deviceID: "d") { _ in }
        model.selectCountry("GB")
        model.state.step = .images
        await model.finish()
        #expect(model.state.step == .business)
        #expect(model.visibleIssue(.name) == .required)
    }
}

@MainActor
@Suite("App start")
struct AppModelTests {
    @Test func startsOnboardingWithoutABusiness() async throws {
        let model = AppModel(dependencies: try TestEnvironment.dependencies())
        await model.start()
        guard case .onboarding = model.phase else {
            Issue.record("expected onboarding, got \(model.phase)")
            return
        }
    }

    @Test func opensTheActiveBusiness() async throws {
        let model = AppModel(dependencies: try TestEnvironment.dependencies(), seed: .uk)
        await model.start()
        guard case .ready(let session) = model.phase else {
            Issue.record("expected the main shell, got \(model.phase)")
            return
        }
        #expect(session.business.name == "Thames Design Ltd")
        #expect(session.config.family == "GB")
    }
}

@MainActor
@Suite("Routers")
struct RouterTests {
    @Test func homeQuickActionsOpenEditors() {
        let router = AppRouter()
        router.startNewClient()
        #expect(router.selectedTab == .clients && router.clients.editor == .new)
        router.startNewItem()
        #expect(router.selectedTab == .items && router.items.editor == .new)
    }

    @Test func savingSelectsAndRemovingClears() {
        let router = ListDetailRouter()
        router.edit("c1")
        #expect(router.editor == .edit("c1"))
        router.didSave("c1")
        #expect(router.editor == nil && router.selection == "c1")
        router.didRemove("c2")
        #expect(router.selection == "c1")
        router.didRemove("c1")
        #expect(router.selection == nil)
    }
}

@MainActor
@Suite("Client editor")
struct ClientEditorTests {
    @Test func invalidGSTINBlocksSavingThenAValidOneSaves() async throws {
        let session = try await TestEnvironment.session()
        let model = ClientEditorViewModel(session: session, route: .new)
        await model.load()
        model.state.draft.name = "Kaveri Textiles"
        model.state.draft.isBusiness = true
        model.state.draft.taxId = "33AAACC1206D1ZX"
        #expect(await model.save() == nil)
        #expect(model.visibleIssue(.taxId) == .invalidTaxID(.checksum))

        model.state.draft.taxId = "33aaacc1206d1zn"
        #expect(model.taxIDFeedback == .valid("Tamil Nadu"))
        let saved = try #require(await model.save())
        #expect(saved.taxId == "33AAACC1206D1ZN" && saved.regionCode == "33")
        #expect(session.router.clients.selection == saved.id)
        #expect(try await session.dependencies.clients.fetchClient(id: saved.id) == saved)
    }

    @Test func warnsAboutADuplicateTaxID() async throws {
        let session = try await TestEnvironment.session()
        let model = ClientEditorViewModel(session: session, route: .new)
        await model.load()
        model.state.draft.isBusiness = true
        model.state.draft.taxId = "29AABCR1234C1ZU"
        #expect(model.duplicate?.name == "Rao Traders")
    }

    @Test func editsAnExistingClient() async throws {
        let session = try await TestEnvironment.session()
        let clients = try #require(try await firstValue(
            session.dependencies.clients.observeClients(businessID: session.business.id)))
        let rao = try #require(clients.first { $0.name == "Rao Traders" })
        let model = ClientEditorViewModel(session: session, route: .edit(rao.id))
        #expect(!model.state.isLoaded)
        await model.load()
        #expect(model.state.isLoaded && model.state.draft.name == "Rao Traders")
        #expect(model.duplicate == nil) // its own tax ID is not a duplicate
        model.state.draft.email = "accounts@rao.example"
        let saved = try #require(await model.save())
        #expect(saved.id == rao.id && saved.email == "accounts@rao.example")
        #expect(saved.createdAt == rao.createdAt)
    }
}

@MainActor
@Suite("Catalogue editor")
struct CatalogEditorTests {
    @Test func savesPricesInMinorUnits() async throws {
        let session = try await TestEnvironment.session()
        let model = CatalogItemEditorViewModel(session: session, route: .new)
        await model.load()
        #expect(model.currencySymbol == "₹")
        #expect(model.productCodeHint == "At least 4 digits needed on B2B invoices.")
        model.state.draft.name = "Logo design"
        model.state.draft.priceText = "1,234.50"
        #expect(await model.save() == nil) // no rate yet
        #expect(model.visibleIssue(.rate) == .required)
        model.state.draft.rateId = "gst_18"
        let saved = try #require(await model.save())
        #expect(saved.unitPriceMinor == 123_450 && saved.currency == .inr && saved.rateId == "gst_18")
        #expect(session.router.items.selection == saved.id)
    }

    @Test func warnsWhenTheSavedRateIsNoLongerInForce() async throws {
        let session = try await TestEnvironment.session()
        let model = CatalogItemEditorViewModel(session: session, route: .new)
        model.state.draft.rateId = "gst_12"
        #expect(model.rateWarning != nil)
        #expect(model.rateChoices.last?.id == "gst_12")
        model.state.draft.rateId = "gst_5"
        #expect(model.rateWarning == nil)
        #expect(!model.rateChoices.contains { $0.id == "gst_12" })
    }
}

@MainActor
@Suite("Settings")
struct SettingsTests {
    @Test func changingTheNextInvoiceNumber() async throws {
        let session = try await TestEnvironment.session()
        let model = NumberingSettingsViewModel(session: session)
        model.state.series = try #require(try await firstValue(
            session.dependencies.numberingSeries.observeSeries(businessID: session.business.id)))
        let invoices = try #require(model.state.series.first { $0.docType == .invoice })
        #expect(model.nextNumber(invoices) == "INV/26-27/0001")

        model.edit(invoices)
        model.state.draft?.nextNumberText = "142"
        #expect(model.preview == "INV/26-27/0142")
        model.state.draft?.pattern = "INVOICE/{fyLong}/{seq:5}"
        #expect(model.visibleIssue(.pattern) == .invalidNumbering(.numberTooLong))
        #expect(await model.saveEditing() == false)
        model.state.draft?.pattern = "INV/{fy}/{seq:4}"
        #expect(await model.saveEditing())

        let stored = try #require(try await firstValue(
            session.dependencies.numberingSeries.observeSeries(businessID: session.business.id)))
        #expect(stored.first { $0.docType == .invoice }?.counters == ["FY2026": 142])
    }

    @Test func businessProfileSavesEdits() async throws {
        let session = try await TestEnvironment.session()
        let model = BusinessProfileViewModel(session: session)
        #expect(!model.hasChanges)
        model.state.draft.paymentTermsDays = 30
        model.state.draft.upiVpa = "New@Bank"
        #expect(model.hasChanges)
        await model.save()
        #expect(model.state.didSave)
        let stored = try #require(try await session.dependencies.businesses.fetchBusiness(id: session.business.id))
        #expect(stored.paymentTermsDays == 30 && stored.upiVpa == "new@bank")
    }

    @Test func customRatesInUseCannotBeRemoved() async throws {
        let session = try await TestEnvironment.genericSession()
        let model = TaxRatesViewModel(session: session)
        #expect(model.rates.map(\.label) == ["Sales tax 8.875%", "No tax"])

        model.startNew()
        model.state.draft?.name = "City tax"
        model.state.draft?.percent = "2"
        #expect(await model.saveEditing())
        let stored = try #require(try await session.dependencies.businesses.fetchBusiness(id: session.business.id))
        #expect(stored.customRates?.map(\.label) == ["Sales tax 8.875%", "City tax 2%", "No tax"])

        let salesTax = model.rates[0]
        try await session.dependencies.catalog.save(CatalogItem(
            id: "i1", businessId: session.business.id, name: "Bread", unit: "PCS", unitPriceMinor: 450,
            currency: "USD", rateId: salesTax.id))
        await model.remove(salesTax)
        #expect(model.state.errorMessage == "1 item uses this rate. Change it first.")
    }
}

@Suite("Image processing (setup.md §9)")
struct ImageProcessingTests {
    static func image(width: Int, height: Int, transparent: Bool) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Noise so the JPEG does not compress to nothing.
        for y in stride(from: 0, to: height, by: 8) {
            for x in stride(from: 0, to: width, by: 8) {
                context.setFillColor(red: CGFloat((x * 7 + y * 3) % 255) / 255, green: CGFloat((x * y) % 255) / 255,
                                     blue: CGFloat((x + y * 5) % 255) / 255, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 8, height: 8))
            }
        }
        if transparent { context.clear(CGRect(x: 0, y: 0, width: 40, height: 40)) }
        return ImageProcessing.encode(context.makeImage()!, as: .png)!
    }

    static func size(of data: Data) -> (Int, Int) {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        return (image.width, image.height)
    }

    @Test func largeOpaquePhotoBecomesASmallJPEG() throws {
        let logo = try ImageProcessing.encodeLogo(Self.image(width: 3000, height: 2000, transparent: false))
        #expect(logo.mime == ImagePayload.jpeg)
        #expect(logo.data.count <= ImageProcessing.maxBytes)
        let (width, height) = Self.size(of: logo.data)
        #expect(max(width, height) <= 1024 && width > height)
    }

    @Test func transparentLogoStaysPNG() throws {
        let logo = try ImageProcessing.encodeLogo(Self.image(width: 400, height: 200, transparent: true))
        #expect(logo.mime == ImagePayload.png)
        #expect(Self.size(of: logo.data) == (400, 200)) // never upscaled
    }

    @Test func garbageIsRejected() {
        #expect(throws: ImageProcessing.UnreadableImage.self) {
            try ImageProcessing.encodeLogo(Data("not an image".utf8))
        }
    }
}
