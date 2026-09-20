import Foundation
import InvoiceCore
import InvoiceData

/// Everything the screens need, built once at launch (ADR-0004: manual injection). View models receive it through
/// their initialisers; tests and previews use `inMemory()` or fakes.
public struct AppDependencies: Sendable {
    public var businesses: any BusinessRepository
    public var clients: any ClientRepository
    public var catalog: any CatalogRepository
    public var numberingSeries: any NumberingSeriesRepository
    public var assets: any AssetRepository
    public var deviceState: any DeviceStateRepository
    public var setup: any BusinessSetupService
    public var documents: any DocumentRepository
    public var documentService: any DocumentService
    public var taxConfigs: TaxConfigStore
    public var reference: ReferenceData
    public var time: TimeSource
    public var ids: IDGenerator

    public init(businesses: any BusinessRepository, clients: any ClientRepository, catalog: any CatalogRepository,
                numberingSeries: any NumberingSeriesRepository, assets: any AssetRepository,
                deviceState: any DeviceStateRepository, setup: any BusinessSetupService,
                documents: any DocumentRepository, documentService: any DocumentService, taxConfigs: TaxConfigStore,
                reference: ReferenceData, time: TimeSource, ids: IDGenerator) {
        self.businesses = businesses
        self.clients = clients
        self.catalog = catalog
        self.numberingSeries = numberingSeries
        self.assets = assets
        self.deviceState = deviceState
        self.setup = setup
        self.documents = documents
        self.documentService = documentService
        self.taxConfigs = taxConfigs
        self.reference = reference
        self.time = time
        self.ids = ids
    }

    /// Repositories backed by `database`, plus the bundled spec.
    public static func make(database: AppDatabase, time: TimeSource = .system, ids: IDGenerator = .random) throws
        -> AppDependencies {
        let taxConfigs = try TaxConfigStore.bundled()
        let reference = try ReferenceData.bundled()
        return AppDependencies(
            businesses: GRDBBusinessRepository(database: database, time: time),
            clients: GRDBClientRepository(database: database, time: time),
            catalog: GRDBCatalogRepository(database: database, time: time),
            numberingSeries: GRDBNumberingSeriesRepository(database: database, time: time),
            assets: GRDBAssetRepository(database: database),
            deviceState: GRDBDeviceStateRepository(database: database, time: time, ids: ids),
            setup: GRDBBusinessSetupService(database: database, time: time, ids: ids),
            documents: GRDBDocumentRepository(database: database, time: time),
            documentService: GRDBDocumentService(database: database, time: time, ids: ids, configs: taxConfigs,
                                                 currencies: reference.currencies),
            taxConfigs: taxConfigs,
            reference: reference,
            time: time,
            ids: ids
        )
    }

    /// The app's on-disk database in Application Support.
    public static func live() throws -> AppDependencies {
        try make(database: AppDatabase.openOnDisk(at: AppDatabase.defaultURL()))
    }

    /// An empty in-memory database (previews, tests, UI tests).
    public static func inMemory(time: TimeSource = .system, ids: IDGenerator = .random) throws -> AppDependencies {
        try make(database: AppDatabase.inMemory(), time: time, ids: ids)
    }

    /// Launch arguments for UI tests and screenshots: `-inMemory` starts with an empty database;
    /// `-seed IN|GB` also adds a sample business, clients and items.
    public static func forLaunch(arguments: [String]) throws -> (AppDependencies, seed: SampleData.Country?) {
        let seed = arguments.firstIndex(of: "-seed").flatMap { index in
            arguments.indices.contains(index + 1) ? SampleData.Country(rawValue: arguments[index + 1]) : nil
        }
        if seed != nil || arguments.contains("-inMemory") {
            return (try inMemory(), seed)
        }
        return (try live(), nil)
    }
}
