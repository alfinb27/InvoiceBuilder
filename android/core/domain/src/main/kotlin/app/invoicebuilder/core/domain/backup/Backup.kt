package app.invoicebuilder.core.domain.backup

import app.invoicebuilder.core.domain.documents.Document
import app.invoicebuilder.core.domain.documents.Payment
import app.invoicebuilder.core.domain.models.Asset
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.models.NumberingSeries
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** A portable `.invoicebackup` file (`spec/schema/backup.schema.json`, `spec/backup.md`). iOS: `BackupFile`. */
@Serializable
data class BackupFile(
    val format: String = FORMAT,
    val formatVersion: Int = FORMAT_VERSION,
    /** Export time, epoch ms UTC. */
    val createdAt: Long,
    val app: AppInfo,
    /** The highest migration applied when the file was written. */
    val dbSchemaVersion: Int,
    val counts: BackupCounts,
    val data: BackupData,
) {
    @Serializable
    data class AppInfo(/** `ios` or `android`. */ val platform: String, val version: String)

    companion object {
        const val FORMAT = "invoicebuilder-backup"
        /** The newest `formatVersion` this app reads and the one it writes. */
        const val FORMAT_VERSION = 1
        const val FILE_EXTENSION = "invoicebackup"

        fun of(createdAt: Long, app: AppInfo, dbSchemaVersion: Int, data: BackupData) =
            BackupFile(createdAt = createdAt, app = app, dbSchemaVersion = dbSchemaVersion, counts = data.counts, data = data)

        /** `InvoiceBackup-YYYY-MM-DD.invoicebackup` (§1). */
        fun fileName(date: LocalDate): String = "InvoiceBackup-$date.$FILE_EXTENSION"
    }
}

/** Every row of the synced tables, tombstones included (`spec/backup.md` §1). */
@Serializable
data class BackupData(
    val businesses: List<Business> = emptyList(),
    val clients: List<Client> = emptyList(),
    val catalogItems: List<CatalogItem> = emptyList(),
    val numberingSeries: List<NumberingSeries> = emptyList(),
    val documents: List<Document> = emptyList(),
    val payments: List<Payment> = emptyList(),
    val assets: List<Asset> = emptyList(),
) {
    /** Array lengths, tombstones included. */
    val counts: BackupCounts
        get() = BackupCounts(businesses.size, clients.size, catalogItems.size, numberingSeries.size, documents.size, payments.size, assets.size)

    /** Rows whose `deletedAt` is null: what the restore preview shows. */
    val liveCounts: BackupCounts
        get() = BackupCounts(
            businesses.count { it.deletedAt == null }, clients.count { it.deletedAt == null },
            catalogItems.count { it.deletedAt == null }, numberingSeries.count { it.deletedAt == null },
            documents.count { it.deletedAt == null }, payments.count { it.deletedAt == null }, assets.count { it.deletedAt == null },
        )

    /** Each collection by `createdAt`, then `id` (§1), so the same data always gives the same file. */
    fun sorted(): BackupData = BackupData(
        businesses.sortedWith(compareBy({ it.createdAt }, { it.id })),
        clients.sortedWith(compareBy({ it.createdAt }, { it.id })),
        catalogItems.sortedWith(compareBy({ it.createdAt }, { it.id })),
        numberingSeries.sortedWith(compareBy({ it.createdAt }, { it.id })),
        documents.sortedWith(compareBy<Document>({ it.createdAt }, { it.id })).map { document ->
            document.copy(lines = document.lines.sortedWith(compareBy({ it.position }, { it.id })))
        },
        payments.sortedWith(compareBy({ it.createdAt }, { it.id })),
        assets.sortedWith(compareBy({ it.createdAt }, { it.id })),
    )
}

@Serializable
data class BackupCounts(
    val businesses: Int,
    val clients: Int,
    val catalogItems: Int,
    val numberingSeries: Int,
    val documents: Int,
    val payments: Int,
    val assets: Int,
) {
    fun named(): List<Pair<String, Int>> = listOf(
        "businesses" to businesses, "clients" to clients, "catalogItems" to catalogItems, "numberingSeries" to numberingSeries,
        "documents" to documents, "payments" to payments, "assets" to assets,
    )
}

/** A file that passed `BackupCodec.validate`: what the user confirms before restoring (§4 step 2). */
data class BackupPreview(val file: BackupFile) {
    /** Live rows per collection. */
    val live: BackupCounts get() = file.data.liveCounts
}

/** Why a file cannot be restored (`spec/backup.md` §3). */
class BackupError(val code: Code, val detail: String? = null) : Exception(detail?.let { "${code.rawValue}: $it" } ?: code.rawValue) {
    enum class Code(val rawValue: String) {
        NotJSON("not_json"), NotABackup("not_a_backup"), NewerFormat("newer_format"), NewerSchema("newer_schema"),
        InvalidRecord("invalid_record"), CountMismatch("count_mismatch"), DuplicateID("duplicate_id"),
        AssetHashMismatch("asset_hash_mismatch"), DanglingReference("dangling_reference"),
    }
}

/** What Settings shows about backups (`spec/backup.md` §5). */
data class BackupStatus(
    /** `app_state.last_backup_at`, epoch ms UTC. */
    val lastBackupAt: Long?,
    /** At least one live document is issued or void. */
    val hasIssuedDocuments: Boolean,
) {
    /** Whole calendar days since the last backup, in [zone]; null when there has been none. */
    fun daysSinceLastBackup(today: LocalDate, zone: ZoneId = ZoneId.systemDefault()): Int? {
        val last = lastBackupAt ?: return null
        val date = Instant.ofEpochMilli(last).atZone(zone).toLocalDate()
        return maxOf(0, (today.toEpochDay() - date.toEpochDay()).toInt())
    }

    /** §5: something has been issued and the last backup is missing or 30 or more days old. */
    fun isDue(today: LocalDate, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        if (!hasIssuedDocuments) return false
        val days = daysSinceLastBackup(today, zone) ?: return true
        return days >= DUE_AFTER_DAYS
    }

    companion object {
        const val DUE_AFTER_DAYS = 30
    }
}
