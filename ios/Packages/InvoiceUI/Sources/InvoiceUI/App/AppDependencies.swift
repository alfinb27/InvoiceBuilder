import Foundation
import InvoiceBilling
import InvoiceCore
import InvoiceData
import InvoiceDrive
import InvoiceSync
import UIKit

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
    /// Device series, takeover and the duplicate-number check (`spec/sync.md` §3–4).
    public var numbering: any NumberingService
    /// iCloud sync (`spec/sync.md`); `UnavailableSyncService` unless the build names an iCloud container.
    public var sync: any SyncService
    /// The unlock and the free-tier count (`spec/billing.md`).
    public var entitlements: any EntitlementService
    /// Automatic backup to Google Drive (`spec/backup.md` §7); nil unless the build carries a Google OAuth client
    /// (`GoogleDriveClientID`) or a UI test asks for the in-memory one (`-fakeDrive`).
    public var cloudBackup: (any DriveSyncDestination)?
    /// The §7.7 state and the latest change (the backup service, which owns `app_state`).
    public var cloudBackupState: any CloudBackupStateStore
    /// Drive sync's database side (`spec/drive-sync.md`; the backup service too).
    public var driveSyncStore: any DriveSyncStore
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
                numbering: any NumberingService, sync: any SyncService = UnavailableSyncService(),
                entitlements: any EntitlementService, cloudBackup: (any DriveSyncDestination)? = nil,
                cloudBackupState: any CloudBackupStateStore, driveSyncStore: any DriveSyncStore,
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
        self.numbering = numbering
        self.sync = sync
        self.entitlements = entitlements
        self.cloudBackup = cloudBackup
        self.cloudBackupState = cloudBackupState
        self.driveSyncStore = driveSyncStore
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
                            snapshots: BackupSnapshotStore = .temporary(),
                            sync: any SyncService = UnavailableSyncService(),
                            store: any StoreClient = UnavailableStoreClient(),
                            counterMirror: any CounterMirror = MemoryCounterMirror(),
                            deviceMarker: any DeviceMarkerStore = InMemoryDeviceMarkerStore(),
                            cloudBackup: (any DriveSyncDestination)? = nil,
                            bundleID: String = Bundle.main.bundleIdentifier ?? "app.invoicebuilder.invoices") throws
        -> AppDependencies {
        let taxConfigs = try TaxConfigStore.bundled()
        let reference = try ReferenceData.bundled()
        let backup = try GRDBBackupService(database: database, time: time, ids: ids, snapshots: snapshots)
        return AppDependencies(
            businesses: GRDBBusinessRepository(database: database, time: time),
            clients: GRDBClientRepository(database: database, time: time),
            catalog: GRDBCatalogRepository(database: database, time: time),
            numberingSeries: GRDBNumberingSeriesRepository(database: database, time: time),
            assets: GRDBAssetRepository(database: database),
            deviceState: GRDBDeviceStateRepository(database: database, time: time, ids: ids, marker: deviceMarker),
            setup: GRDBBusinessSetupService(database: database, time: time, ids: ids),
            documents: GRDBDocumentRepository(database: database, time: time),
            documentService: GRDBDocumentService(database: database, time: time, ids: ids, configs: taxConfigs,
                                                 currencies: reference.currencies),
            payments: GRDBPaymentRepository(database: database, time: time),
            paymentService: GRDBPaymentService(database: database, time: time, ids: ids),
            backup: backup,
            numbering: GRDBNumberingService(database: database, time: time, ids: ids, configs: taxConfigs),
            sync: sync,
            entitlements: StoreEntitlementService(
                productID: StoreEntitlementService.productID(bundleID: bundleID), store: store,
                counts: GRDBFreeTierRepository(database: database), mirror: counterMirror),
            cloudBackup: cloudBackup,
            cloudBackupState: backup,
            driveSyncStore: backup,
            taxConfigs: taxConfigs,
            reference: reference,
            time: time,
            ids: ids,
            notifications: notifications
        )
    }

    /// The app's on-disk database in Application Support. A build whose Info.plist names an iCloud container
    /// (`InvoiceSyncContainer`, set together with the iCloud capability) syncs it (`spec/sync.md`).
    public static func live(bundle: Bundle = .main) throws -> AppDependencies {
        let url = try AppDatabase.defaultURL()
        let drive = googleDrive(bundle: bundle)
        guard let container = bundle.object(forInfoDictionaryKey: "InvoiceSyncContainer") as? String,
              !container.isEmpty else {
            return try make(database: AppDatabase.openOnDisk(at: url), notifications: SystemNotificationScheduler(),
                            snapshots: .defaultStore(), store: StoreKitClient(), counterMirror: KeychainCounterMirror(),
                            deviceMarker: KeychainDeviceMarkerStore(), cloudBackup: drive)
        }
        let database = try AppDatabase.openOnDisk(at: url) {
            LiveSyncService.prepare(&$0, containerIdentifier: container)
        }
        let sync = try LiveSyncService(
            database: database, containerIdentifier: container,
            deviceState: GRDBDeviceStateRepository(database: database, time: .system, ids: .random,
                                                    marker: KeychainDeviceMarkerStore()),
            enabled: false)
        return try make(database: database, notifications: SystemNotificationScheduler(),
                        snapshots: .defaultStore(), sync: sync, store: StoreKitClient(),
                        counterMirror: KeychainCounterMirror(), deviceMarker: KeychainDeviceMarkerStore(),
                        cloudBackup: drive)
    }

    /// Google Drive backup when the build carries the OAuth client (ADR-0021); nil otherwise.
    static func googleDrive(bundle: Bundle) -> (any DriveSyncDestination)? {
        guard let clientID = bundle.object(forInfoDictionaryKey: "GoogleDriveClientID") as? String,
              !clientID.isEmpty else { return nil }
        let http = URLSessionHTTPClient()
        let auth = GoogleAuth(config: GoogleOAuthConfig(clientID: clientID), http: http, store: KeychainTokenStore(),
                              authenticator: SystemWebAuthenticator())
        return GoogleDriveDestination(auth: auth, http: http)
    }

    /// The runner for this device's automatic cloud backups, or nil without a cloud.
    @MainActor func autoBackupRunner(deviceID: String, appVersion: String) -> AutoBackupRunner? {
        guard let cloudBackup else { return nil }
        return AutoBackupRunner(destination: cloudBackup, backups: backup, state: cloudBackupState, time: time,
                                device: .init(id: deviceID, name: UIDevice.current.model,
                                              app: .init(platform: "ios", version: appVersion)))
    }

    /// Live sync through this device's Google Drive connection (`spec/drive-sync.md`), or nil without Drive.
    func driveSyncEngine(deviceID: String) -> DriveSyncEngine? {
        guard let cloudBackup else { return nil }
        return DriveSyncEngine(destination: cloudBackup, store: driveSyncStore, time: time, deviceID: deviceID)
    }

    /// An empty in-memory database (previews, tests, UI tests).
    public static func inMemory(time: TimeSource = .system, ids: IDGenerator = .random,
                                cloudBackup: (any DriveSyncDestination)? = nil) throws -> AppDependencies {
        try make(database: AppDatabase.inMemory(), time: time, ids: ids, cloudBackup: cloudBackup)
    }

    /// Launch arguments for UI tests and screenshots: `-inMemory` starts with an empty database;
    /// `-seed IN|GB` also adds a sample business, clients and items; `-fakeDrive` adds an in-memory Google Drive.
    public static func forLaunch(arguments: [String]) throws -> (AppDependencies, seed: SampleData.Country?) {
        let seed = arguments.firstIndex(of: "-seed").flatMap { index in
            arguments.indices.contains(index + 1) ? SampleData.Country(rawValue: arguments[index + 1]) : nil
        }
        if seed != nil || arguments.contains("-inMemory") {
            let drive: (any DriveSyncDestination)? = arguments.contains("-fakeDrive") ? DemoCloudBackup.shared : nil
            return (try inMemory(cloudBackup: drive), seed)
        }
        return (try live(), nil)
    }
}
