import Foundation
import InvoiceCore
import Observation

/// The signed-in state of the app: the active business, its tax config and the navigation router. Created after
/// onboarding (or at launch) and shared by every screen through the environment.
@MainActor @Observable
public final class Session {
    public let dependencies: AppDependencies
    /// This device's id (owner of the numbering series it creates).
    public let deviceID: String
    /// The active business, kept current by `observeBusiness()`.
    public private(set) var business: Business
    public let config: TaxConfig
    public let router = AppRouter()
    public let formatter: SpecFormatter
    /// Renders and caches the PDFs the preview, sharing and printing use (`spec/pdf/RENDERING.md`).
    let pdfLibrary: PDFLibrary

    public init(dependencies: AppDependencies, business: Business, deviceID: String,
                pdfDirectory: URL? = nil) throws {
        let today = dependencies.time.today()
        guard let config = dependencies.taxConfigs.latest(family: business.taxConfig, on: today)
            ?? dependencies.taxConfigs.latest(family: "GENERIC", on: today) else {
            throw SpecLoadingError(path: "tax/\(business.taxConfig).json", reason: "no config for this business")
        }
        self.dependencies = dependencies
        self.business = business
        self.deviceID = deviceID
        self.config = config
        formatter = SpecFormatter(currencies: dependencies.reference.currencies)
        pdfLibrary = try PDFLibrary(configs: dependencies.taxConfigs, reference: dependencies.reference,
                                    assets: dependencies.assets, directory: pdfDirectory)
    }

    /// Re-plans and replaces this business's local reminders (`spec/reminders.md` §3): at launch, after issuing an
    /// invoice, after a payment is recorded or removed, after a void, and after the business default changes.
    func reconcileReminders() async {
        let reconciler = ReminderReconciler(dependencies: dependencies)
        await reconciler.requestAuthorizationIfNeeded()
        await reconciler.reconcile(businessID: business.id)
    }

    /// Keeps `business` in step with the database (edits in Settings show everywhere at once).
    func observeBusiness() async {
        do {
            for try await latest in dependencies.businesses.observeBusiness(id: business.id) {
                if let latest { business = latest }
            }
        } catch {
            // The stream only ends with an error if the database fails; the last known business stays on screen.
        }
    }

    // MARK: Rules for the active business

    var today: LocalDate { dependencies.time.today() }

    var businessRules: BusinessRules { BusinessRules(config: config) }

    var clientRules: ClientRules { ClientRules(config: config, businessCountry: business.countryCode) }

    var catalogRules: CatalogItemRules {
        CatalogItemRules(config: config, business: business, currencies: dependencies.reference.currencies,
                         units: dependencies.reference.units, today: today)
    }

    var numberingRules: NumberingSeriesRules {
        NumberingSeriesRules(config: config, today: today, deviceID: deviceID)
    }

    var documentRules: DocumentRules {
        DocumentRules(configs: dependencies.taxConfigs, business: business,
                      currencies: dependencies.reference.currencies, defaultConfig: config)
    }

    // MARK: Navigation

    /// Opens a new invoice or quote in the Invoices tab (Home, the list, ⌘N / ⇧⌘N). Nothing is written until the
    /// first change (`spec/documents.md` §2).
    public func startNewDocument(_ docType: DocumentType) {
        router.selectedTab = .documents
        router.documents.docType = docType
        router.documents.selection = .new(docType, id: dependencies.ids.make())
    }

    /// Opens an existing invoice or quote in the Invoices tab (a client's document list, a search result).
    public func openDocument(_ id: String, docType: DocumentType) {
        router.selectedTab = .documents
        router.documents.docType = docType
        router.documents.open(id)
    }

    var registration: TaxRegistration? { config.registration(business.taxRegistration) }

    var chargesTax: Bool { registration?.chargesTax ?? false }

    // MARK: Display helpers

    /// An amount: the symbol for the home currency, the ISO code for any other (`ENGINE.md` §7.1).
    func money(_ minor: Int64, currency: CurrencyCode? = nil) -> String {
        formatter.money(minor, currency: currency ?? business.homeCurrency, homeCurrency: business.homeCurrency)
    }

    func countryName(_ code: String) -> String {
        dependencies.reference.country(code: code)?.name ?? code
    }

    func regionName(_ code: String?) -> String? {
        code.map { config.region($0)?.name ?? $0 }
    }

    func rate(_ id: String) -> TaxRate? {
        config.rate(id, customRates: business.customRates)
    }

    func unitLabel(_ id: String) -> String {
        dependencies.reference.unit(id: id)?.label ?? id
    }
}
