package app.invoicebuilder.android.app

import android.content.Context
import app.invoicebuilder.android.reminders.NoOpNotificationScheduler
import app.invoicebuilder.android.reminders.NotificationScheduling
import app.invoicebuilder.android.reminders.SystemNotificationScheduler
import app.invoicebuilder.core.billing.BlockStoreCounterMirror
import app.invoicebuilder.core.billing.CounterMirror
import app.invoicebuilder.core.billing.MemoryCounterMirror
import app.invoicebuilder.core.billing.PlayBillingClient
import app.invoicebuilder.core.billing.StoreClient
import app.invoicebuilder.core.billing.StoreEntitlementService
import app.invoicebuilder.core.billing.UnavailableStoreClient
import app.invoicebuilder.core.data.AppDatabase
import app.invoicebuilder.core.data.BackupSnapshotStore
import app.invoicebuilder.core.data.RoomAssetRepository
import app.invoicebuilder.core.data.RoomBackupService
import app.invoicebuilder.core.data.RoomBusinessRepository
import app.invoicebuilder.core.data.RoomBusinessSetupService
import app.invoicebuilder.core.data.RoomCatalogRepository
import app.invoicebuilder.core.data.RoomClientRepository
import app.invoicebuilder.core.data.RoomDeviceStateRepository
import app.invoicebuilder.core.data.RoomDocumentRepository
import app.invoicebuilder.core.data.RoomDocumentService
import app.invoicebuilder.core.data.RoomFreeTierRepository
import app.invoicebuilder.core.data.RoomNumberingSeriesRepository
import app.invoicebuilder.core.data.RoomNumberingService
import app.invoicebuilder.core.data.RoomPaymentRepository
import app.invoicebuilder.core.data.RoomPaymentService
import app.invoicebuilder.core.domain.reference.ReferenceData
import app.invoicebuilder.core.domain.repositories.AssetRepository
import app.invoicebuilder.core.domain.repositories.BackupService
import app.invoicebuilder.core.domain.repositories.BusinessRepository
import app.invoicebuilder.core.domain.repositories.BusinessSetupService
import app.invoicebuilder.core.domain.repositories.CatalogRepository
import app.invoicebuilder.core.domain.repositories.ClientRepository
import app.invoicebuilder.core.domain.repositories.DeviceStateRepository
import app.invoicebuilder.core.domain.repositories.DocumentRepository
import app.invoicebuilder.core.domain.repositories.DocumentService
import app.invoicebuilder.core.domain.repositories.EntitlementService
import app.invoicebuilder.core.domain.repositories.NumberingSeriesRepository
import app.invoicebuilder.core.domain.repositories.NumberingService
import app.invoicebuilder.core.domain.repositories.PaymentRepository
import app.invoicebuilder.core.domain.repositories.PaymentService
import app.invoicebuilder.core.domain.support.IDGenerator
import app.invoicebuilder.core.domain.support.TimeSource
import app.invoicebuilder.core.domain.tax.TaxConfigStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.io.File

/**
 * Everything the screens need, built once at launch (ADR-0004: manual injection). iOS: `AppDependencies`.
 * The `Application` subclass owns the live one (≈ the app's `@main` struct building `AppDependencies.live()`).
 *
 * There is no sync service: iCloud sync is iOS-only, and Android relies on backups and Google's Auto Backup
 * (`spec/sync.md`, ADR-0013).
 */
class AppContainer(
    val businesses: BusinessRepository,
    val clients: ClientRepository,
    val catalog: CatalogRepository,
    val numberingSeries: NumberingSeriesRepository,
    val assets: AssetRepository,
    val deviceState: DeviceStateRepository,
    val setup: BusinessSetupService,
    val documents: DocumentRepository,
    val documentService: DocumentService,
    val payments: PaymentRepository,
    val paymentService: PaymentService,
    val backup: BackupService,
    val numbering: NumberingService,
    val entitlements: EntitlementService,
    val taxConfigs: TaxConfigStore,
    val reference: ReferenceData,
    val time: TimeSource,
    val ids: IDGenerator,
    val notifications: NotificationScheduling,
    /** The app's cache directory: rendered PDFs, unpacked fonts, outgoing backups. */
    val cacheDirectory: File,
    /** Long-lived work that must outlive a screen (≈ unstructured `Task`s on iOS). */
    val scope: CoroutineScope,
    val applicationID: String,
) {
    companion object {
        private val taxConfigs by lazy { TaxConfigStore.bundled() }
        private val reference by lazy { ReferenceData.bundled() }

        /** Repositories backed by [db], plus the bundled spec. Only [live] passes the real store and notifications. */
        fun make(
            context: Context,
            db: AppDatabase,
            time: TimeSource = TimeSource.system,
            ids: IDGenerator = IDGenerator.random,
            notifications: NotificationScheduling = NoOpNotificationScheduler(),
            snapshots: BackupSnapshotStore = BackupSnapshotStore(File(context.cacheDir, "snapshots-temp")),
            store: StoreClient = UnavailableStoreClient(),
            counterMirror: CounterMirror = MemoryCounterMirror(),
        ): AppContainer {
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val applicationID = context.packageName.removeSuffix(".debug")
            return AppContainer(
                businesses = RoomBusinessRepository(db, time),
                clients = RoomClientRepository(db, time),
                catalog = RoomCatalogRepository(db, time),
                numberingSeries = RoomNumberingSeriesRepository(db, time),
                assets = RoomAssetRepository(db),
                deviceState = RoomDeviceStateRepository(db, time, ids),
                setup = RoomBusinessSetupService(db, time, ids),
                documents = RoomDocumentRepository(db, time),
                documentService = RoomDocumentService(db, time, ids, taxConfigs, reference.currencies),
                payments = RoomPaymentRepository(db, time),
                paymentService = RoomPaymentService(db, time, ids),
                backup = RoomBackupService(db, time, ids, snapshots, appVersion(context)),
                numbering = RoomNumberingService(db, time, ids, taxConfigs),
                entitlements = StoreEntitlementService(
                    StoreEntitlementService.productID(applicationID), store, RoomFreeTierRepository(db), counterMirror, scope,
                ),
                taxConfigs = taxConfigs,
                reference = reference,
                time = time,
                ids = ids,
                notifications = notifications,
                cacheDirectory = context.cacheDir,
                scope = scope,
                applicationID = applicationID,
            )
        }

        /** The on-disk database, Play Billing, Block Store and real notifications. */
        fun live(context: Context): AppContainer = make(
            context, AppDatabase.open(context),
            notifications = SystemNotificationScheduler(context),
            snapshots = BackupSnapshotStore(File(context.filesDir, "snapshots")),
            store = PlayBillingClient(context),
            counterMirror = BlockStoreCounterMirror(context),
        )

        /** An empty in-memory database (previews, tests, the demo business). */
        fun inMemory(context: Context, time: TimeSource = TimeSource.system, ids: IDGenerator = IDGenerator.random): AppContainer =
            make(context, AppDatabase.inMemory(context), time, ids)

        fun appVersion(context: Context): String = runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull() ?: "0"
    }
}
