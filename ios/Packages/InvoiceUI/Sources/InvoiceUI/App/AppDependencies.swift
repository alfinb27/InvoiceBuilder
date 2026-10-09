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
    public var payments: any PaymentRepository
    public var paymentService: any PaymentService
    /// Export and restore (`spec/backup.md`).
    public var backup: any BackupService
    public var taxConfigs: TaxConfigStore
    public var reference: ReferenceData
    public var time: TimeSource
    public var ids: IDGenerator
    /// `SystemNotificationScheduler` only for `live()`; every other path defaults to a no-op (`spec/reminders.md`
    /// §3) so tests and UI-test runs never touch the real notification center or show a permission prompt.
    public var notifications: any NotificationScheduling

    public init(businesses: any BusinessRepository, clients: any ClientRepository, catalog: any CatalogRepository,
                numberingSeries: any NumberingSeriesRepository, assets: any AssetRepository,
                deviceState: any DeviceStateRepository, setup: any BusinessSetupService,
                documents: any DocumentRepository, documentService: any DocumentService,
                payments: any PaymentRepository, paymentService: any PaymentService, backup: any BackupService,
                taxConfigs: TaxConfigStore,
                reference: ReferenceData, time: TimeSource, ids: IDGenerator,
                notifications: any NotificationScheduling = NoOpNotificationScheduler()) {
        self.businesses = businesses
        self.clients = clients
        self.catalog = catalog
        self.numberingSeries = numberingSeries
        self.assets = assets
        self.deviceState = deviceState
        self.setup = setup
        self.documents = documents
        self.documentService = documentService
        self.payments = payments
        self.paymentService = paymentService
        self.backup = backup
        self.taxConfigs = taxConfigs
        self.reference = reference
        self.time = time
        self.ids = ids
        self.notifications = notifications
    }

    /// Repositories backed by `database`, plus the bundled spec. `notifications` defaults to a no-op and safety
    /// snapshots to a temporary folder; only `live()` passes the real ones.
    public static func make(database: AppDatabase, time: TimeSource = .system, ids: IDGenerator = .random,
                            notifications: any NotificationScheduling = NoOpNotificationScheduler(),
                            snapshots: BackupSnapshotStore = .temporary()) throws -> AppDependencies {
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
            payments: GRDBPaymentRepository(database: database, time: time),
            paymentService: GRDBPaymentService(database: database, time: time, ids: ids),
            backup: try GRDBBackupService(database: database, time: time, ids: ids, snapshots: snapshots),
            taxConfigs: taxConfigs,
            reference: reference,
            time: time,
            ids: ids,
            notifications: notifications
        )
    }

    /// The app's on-disk database in Application Support.
    public static func live() throws -> AppDependencies {
        try make(database: AppDatabase.openOnDisk(at: AppDatabase.defaultURL()),
                 notifications: SystemNotificationScheduler(), snapshots: .defaultStore())
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
