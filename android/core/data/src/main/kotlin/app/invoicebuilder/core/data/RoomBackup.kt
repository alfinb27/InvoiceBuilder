package app.invoicebuilder.core.data

import androidx.room.withTransaction
import app.invoicebuilder.core.domain.backup.BackupCodec
import app.invoicebuilder.core.domain.backup.BackupData
import app.invoicebuilder.core.domain.backup.BackupFile
import app.invoicebuilder.core.domain.backup.BackupStatus
import app.invoicebuilder.core.domain.billing.FreeTierCounts
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.models.NumberingSeries
import app.invoicebuilder.core.domain.numbering.DuplicateNumbers
import app.invoicebuilder.core.domain.numbering.SeriesOwnership
import app.invoicebuilder.core.domain.repositories.BackupService
import app.invoicebuilder.core.domain.repositories.FreeTierRepository
import app.invoicebuilder.core.domain.repositories.NumberingService
import app.invoicebuilder.core.domain.support.IDGenerator
import app.invoicebuilder.core.domain.support.TimeSource
import app.invoicebuilder.core.domain.tax.TaxConfigStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import java.io.File

/** Export and "replace all" restore (`spec/backup.md`). iOS: `GRDBBackupService`. */
class RoomBackupService(
    private val db: AppDatabase,
    private val time: TimeSource,
    private val ids: IDGenerator,
    private val snapshots: BackupSnapshotStore,
    private val appVersion: String,
) : BackupService {
    override val schemaVersion: Int = SpecMigrations.VERSION

    override suspend fun makeBackup(app: BackupFile.AppInfo): BackupFile {
        val now = time.now()
        val data = db.withTransaction { exportData() }
        return BackupFile.of(now, app, schemaVersion, data)
    }

    override suspend fun writeSafetySnapshot() {
        snapshots.write(makeBackup(BackupFile.AppInfo("android", "snapshot")), time.now())
    }

    override suspend fun restore(file: BackupFile, deviceID: String) {
        writeSafetySnapshot() // §4 step 3: no snapshot, no restore.
        val now = time.now()
        db.withTransaction { replaceAll(file.data, deviceID, now) }
    }

    override suspend fun recordBackup(timestamp: Long) = db.appState().set(LAST_BACKUP_KEY, timestamp.toString())

    override fun observeStatus(): Flow<BackupStatus> =
        combine(db.appState().observe(LAST_BACKUP_KEY), db.documents().observeHasIssued()) { last, issued ->
            BackupStatus(last?.toLongOrNull(), issued)
        }

    /** §1: every row of the synced tables, tombstones included, live lines only, sorted. */
    private suspend fun exportData(): BackupData {
        val lines = db.documents().allLiveLines().groupBy { it.documentId }
        return BackupData(
            businesses = db.businesses().all().map { it.toDomain() },
            clients = db.clients().all().map { it.toDomain() },
            catalogItems = db.catalog().all().map { it.toDomain() },
            numberingSeries = db.series().all().map { it.toDomain() },
            documents = db.documents().all().map { entity -> entity.toDomain((lines[entity.id] ?: emptyList()).map { it.toDomain() }) },
            payments = db.payments().all().map { it.toDomain() },
            assets = db.assets().all().map { it.toDomain() },
        ).sorted()
    }

    /** §4 step 4, inside the caller's transaction (foreign keys are checked at commit). */
    private suspend fun replaceAll(data: BackupData, deviceID: String, now: Long) {
        db.openHelper.writableDatabase.execSQL("PRAGMA defer_foreign_keys = ON")
        for (asset in data.assets) if (db.assets().any(asset.id) != null) db.assets().update(asset.toEntity()) else db.assets().insert(asset.toEntity())
        for (row in data.businesses) if (db.businesses().any(row.id) != null) db.businesses().update(row.toEntity()) else db.businesses().insert(row.toEntity())
        for (row in data.clients) if (db.clients().any(row.id) != null) db.clients().update(row.toEntity()) else db.clients().insert(row.toEntity())
        for (row in data.catalogItems) if (db.catalog().any(row.id) != null) db.catalog().update(row.toEntity()) else db.catalog().insert(row.toEntity())
        for (row in data.numberingSeries) if (db.series().any(row.id) != null) db.series().update(row.toEntity()) else db.series().insert(row.toEntity())
        for (row in data.documents) if (db.documents().any(row.id) != null) db.documents().update(row.toEntity()) else db.documents().insert(row.toEntity())
        for (row in data.payments) if (db.payments().any(row.id) != null) db.payments().update(row.toEntity()) else db.payments().insert(row.toEntity())
        for (document in data.documents) for (line in document.lines) {
            val entity = line.toEntity(document.id, document.updatedAt, document.updatedAt)
            if (db.documents().anyLine(line.id) != null) db.documents().updateLine(entity) else db.documents().insertLine(entity)
        }

        val sql = db.openHelper.writableDatabase
        fun tombstoneOthers(table: String, kept: Set<String>) {
            sql.query("SELECT id FROM $table WHERE deleted_at IS NULL").use { cursor ->
                val stale = mutableListOf<String>()
                while (cursor.moveToNext()) cursor.getString(0).takeIf { it !in kept }?.let(stale::add)
                for (id in stale) sql.execSQL("UPDATE $table SET deleted_at = ?, updated_at = ? WHERE id = ?", arrayOf<Any>(now, now, id))
            }
        }
        tombstoneOthers("tax_line", emptySet())
        for (document in data.documents) for (taxLine in document.computed?.taxLines ?: emptyList()) {
            db.documents().insertTaxLine(taxLineEntity(ids.make(), document.id, taxLine, now))
        }
        tombstoneOthers("line_item", data.documents.flatMap { d -> d.lines.map { it.id } }.toSet())
        tombstoneOthers("payment", data.payments.map { it.id }.toSet())
        tombstoneOthers("document", data.documents.map { it.id }.toSet())
        tombstoneOthers("numbering_series", data.numberingSeries.map { it.id }.toSet())
        tombstoneOthers("catalog_item", data.catalogItems.map { it.id }.toSet())
        tombstoneOthers("client", data.clients.map { it.id }.toSet())
        tombstoneOthers("business", data.businesses.map { it.id }.toSet())
        tombstoneOthers("asset", data.assets.map { it.id }.toSet())

        // §4: take over, per live business and type, the series this device would otherwise lack.
        val liveBusinesses = db.businesses().allLive().map { it.id }.toSet()
        val series = db.series().allLive().map { it.toDomain() }.filter { it.businessId in liveBusinesses }
        for (group in series.groupBy { it.businessId to it.docType }.values) {
            if (group.none { it.ownerDeviceId == deviceID }) {
                val first = group.first()
                db.series().update(first.copy(ownerDeviceId = deviceID, updatedAt = now).toEntity())
            }
        }
    }

    companion object {
        const val LAST_BACKUP_KEY = "last_backup_at"
    }
}

/** Safety snapshots (`spec/backup.md` §4 step 3): `pre-restore-<epoch ms>.invoicebackup`, newest 3 kept. */
class BackupSnapshotStore(val directory: File) {
    fun write(file: BackupFile, timestamp: Long): File {
        directory.mkdirs()
        val target = File(directory, "pre-restore-$timestamp.${BackupFile.FILE_EXTENSION}")
        target.writeBytes(BackupCodec.encode(file))
        for (stale in snapshots().drop(KEPT)) stale.delete()
        return target
    }

    /** Newest first. */
    fun snapshots(): List<File> = (directory.listFiles() ?: emptyArray())
        .filter { it.name.startsWith("pre-restore-") && it.extension == BackupFile.FILE_EXTENSION }
        .sortedByDescending { it.nameWithoutExtension.removePrefix("pre-restore-").toLongOrNull() ?: 0 }

    companion object {
        const val KEPT = 3
    }
}

/** Numbering on several devices (`spec/sync.md` §3–4). iOS: `GRDBNumberingService`. */
class RoomNumberingService(
    private val db: AppDatabase,
    private val time: TimeSource,
    private val ids: IDGenerator,
    private val configs: TaxConfigStore,
) : NumberingService {
    override suspend fun createDeviceSeries(businessID: String, docType: DocumentType, deviceID: String): NumberingSeries = db.withTransaction {
        val business = db.businesses().live(businessID)?.toDomain() ?: throw RecordNotFound("business", businessID)
        val config = configs.latest(business.taxConfig, time.today()) ?: configs.latest("GENERIC", time.today())!!
        val existing = db.series().liveOf(businessID).map { it.toDomain() }
        when (val result = SeriesOwnership.deviceSeries(ids.make(), businessID, docType, config, existing, deviceID, time.now())) {
            is Outcome.Success -> result.value.also { db.series().insert(it.toEntity()) }
            is Outcome.Failure -> throw IllegalStateException(result.error.rawValue)
        }
    }

    override suspend fun takeOver(seriesID: String, deviceID: String): NumberingSeries = db.withTransaction {
        val series = db.series().live(seriesID)?.toDomain() ?: throw RecordNotFound("numbering_series", seriesID)
        val highest = mutableMapOf<String, Int>()
        db.openHelper.writableDatabase.query(
            "SELECT period_key, MAX(sequence) FROM document WHERE series_id = ? AND lifecycle <> 'draft' AND deleted_at IS NULL " +
                "AND period_key IS NOT NULL AND sequence IS NOT NULL GROUP BY period_key",
            arrayOf(seriesID),
        ).use { cursor -> while (cursor.moveToNext()) highest[cursor.getString(0)] = cursor.getInt(1) }
        SeriesOwnership.takeOver(series, deviceID, highest, time.now()).also { db.series().update(it.toEntity()) }
    }

    override fun observeDuplicateNumbers(businessID: String): Flow<List<DuplicateNumbers.Group>> = db.observe("document") {
        DuplicateNumbers.find(db.documents().summaries(businessID).map {
            DuplicateNumbers.Row(it.id, DocumentType(it.doc_type), DocumentLifecycle(it.lifecycle), it.number)
        })
    }
}

/** The free-tier counts the database keeps (`spec/billing.md`, Free tier). iOS: `GRDBFreeTierRepository`. */
class RoomFreeTierRepository(private val db: AppDatabase) : FreeTierRepository {
    override suspend fun fetchCounts(): FreeTierCounts = FreeTierCounts(
        local = FreeTierCounter.count(db),
        deviceMirror = (db.devices().current()?.freeCounterMirror ?: 0).toInt(),
        issuedInDatabase = db.documents().everIssuedInvoices(),
    )
}
