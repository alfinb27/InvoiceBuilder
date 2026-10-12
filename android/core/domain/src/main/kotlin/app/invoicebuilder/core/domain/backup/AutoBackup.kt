package app.invoicebuilder.core.domain.backup

import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.repositories.BackupService
import app.invoicebuilder.core.domain.support.TimeSource
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * A file in the cloud backup folder (`spec/backup.md` §7.3). The `ib…` app properties are null on a file the app
 * didn't tag (put there by hand). iOS: `CloudBackupEntry`.
 */
data class CloudBackupEntry(
    val id: String,
    val name: String,
    val deviceID: String? = null,
    val deviceName: String? = null,
    /** `ios` or `android`. */
    val platform: String? = null,
    /** The backup's `createdAt`, epoch ms UTC. */
    val createdAt: Long? = null,
    val businesses: String? = null,
    val invoiceCount: Int? = null,
    val clientCount: Int? = null,
) {
    /** The app wrote this file (it carries the device and the time). */
    val isTagged: Boolean get() = deviceID != null && createdAt != null

    companion object {
        /** §7.3: reads the Drive `appProperties`. */
        fun of(id: String, name: String, properties: Map<String, String>) = CloudBackupEntry(
            id, name, properties[Key.DEVICE_ID], properties[Key.DEVICE_NAME], properties[Key.PLATFORM],
            properties[Key.CREATED_AT]?.toLongOrNull(), properties[Key.BUSINESSES], properties[Key.INVOICES]?.toIntOrNull(),
            properties[Key.CLIENTS]?.toIntOrNull(),
        )
    }

    object Key {
        const val DEVICE_ID = "ibDeviceId"
        const val DEVICE_NAME = "ibDeviceName"
        const val PLATFORM = "ibPlatform"
        const val CREATED_AT = "ibCreatedAt"
        const val FORMAT_VERSION = "ibFormatVersion"
        const val BUSINESSES = "ibBusinesses"
        const val INVOICES = "ibInvoices"
        const val CLIENTS = "ibClients"
    }
}

/** Where a backup goes (`spec/backup.md` §7.3). */
sealed interface CloudBackupTarget {
    data object Create : CloudBackupTarget
    /** Replace this file's content and properties. */
    data class Update(val id: String) : CloudBackupTarget
}

/** The pure rules of automatic cloud backup (`spec/backup.md` §7; fixtures kind `autobackup`). iOS: `AutoBackupRules`. */
object AutoBackupRules {
    /** §7.2: at most one automatic attempt per 15 minutes. */
    const val MINIMUM_INTERVAL = 15 * 60 * 1000L
    /** §7.4: the newest backups of this device that stay. */
    const val KEEP = 10
    /** Drive allows 124 bytes per property, key plus value. */
    private const val PROPERTY_BYTES = 124

    /** §7.2: something changed since the last cloud backup and no attempt ran in the last 15 minutes. */
    fun isDue(lastBackupAt: Long?, latestChangeAt: Long?, lastAttemptAt: Long?, now: Long): Boolean {
        if (latestChangeAt == null) return false
        if (lastBackupAt != null && latestChangeAt <= lastBackupAt) return false
        if (lastAttemptAt != null && now - lastAttemptAt < MINIMUM_INTERVAL) return false
        return true
    }

    /** §7.3: replace this device's newest file of today, otherwise create one. Never another device's file. */
    fun target(entries: List<CloudBackupEntry>, fileName: String, deviceID: String): CloudBackupTarget =
        newestFirst(entries).firstOrNull { it.name == fileName && it.deviceID == deviceID }
            ?.let { CloudBackupTarget.Update(it.id) } ?: CloudBackupTarget.Create

    /** §7.4: this device's files beyond the [keep] newest, oldest first. */
    fun filesToDelete(entries: List<CloudBackupEntry>, deviceID: String, keep: Int = KEEP): List<String> =
        newestFirst(entries).filter { it.deviceID == deviceID }.drop(keep).reversed().map { it.id }

    /** §7.6: tagged files, newest first (larger `createdAt`; then larger id). */
    fun newestFirst(entries: List<CloudBackupEntry>): List<CloudBackupEntry> =
        entries.filter { it.isTagged }.sortedWith(compareByDescending<CloudBackupEntry> { it.createdAt ?: 0 }.thenByDescending { it.id })

    /** §7.3: the `appProperties` a backup file carries, each cut to fit Drive's limit. */
    fun properties(file: BackupFile, deviceID: String, deviceName: String): Map<String, String> {
        val data = file.data
        val businesses = data.businesses.filter { it.deletedAt == null }.joinToString(", ") { it.name }
        val invoices = data.documents.count {
            it.deletedAt == null && it.docType == DocumentType.invoice && it.lifecycle == DocumentLifecycle.issued
        }
        val clients = data.clients.count { it.deletedAt == null }
        val raw = mapOf(
            CloudBackupEntry.Key.DEVICE_ID to deviceID, CloudBackupEntry.Key.DEVICE_NAME to deviceName,
            CloudBackupEntry.Key.PLATFORM to file.app.platform, CloudBackupEntry.Key.CREATED_AT to file.createdAt.toString(),
            CloudBackupEntry.Key.FORMAT_VERSION to file.formatVersion.toString(), CloudBackupEntry.Key.BUSINESSES to businesses,
            CloudBackupEntry.Key.INVOICES to invoices.toString(), CloudBackupEntry.Key.CLIENTS to clients.toString(),
        )
        return raw.mapValues { (key, value) -> fit(value, key) }
    }

    /** Cuts [value] (adding "…") so key plus value fit in Drive's 124 bytes. */
    fun fit(value: String, key: String): String {
        val room = PROPERTY_BYTES - key.utf8Size()
        if (value.utf8Size() <= room) return value
        var cut = value
        while (cut.isNotEmpty() && cut.utf8Size() + "…".utf8Size() > room) cut = cut.dropLast(1)
        return "$cut…"
    }

    private fun String.utf8Size() = toByteArray(Charsets.UTF_8).size
}

/** Why a cloud backup failed (`spec/backup.md` §7.5); [rawValue] is `app_state.drive_last_error`. */
enum class CloudBackupError(val rawValue: String) {
    /** Consent revoked or expired: the user reconnects. */
    SignedOut("signedOut"),
    QuotaExceeded("quotaExceeded"),
    NetworkUnavailable("networkUnavailable"),
    /** The user closed the sign-in sheet (never stored). */
    Cancelled("cancelled"),
    Other("other");

    companion object {
        fun of(raw: String?): CloudBackupError? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** A failed cloud call (Kotlin throws; Swift throws the enum itself). */
class CloudBackupException(val error: CloudBackupError) : Exception(error.rawValue)

/** The cloud backup state kept in `app_state` (`spec/backup.md` §7.7). iOS: `CloudBackupState`. */
data class CloudBackupState(
    val accountEmail: String? = null,
    val folderID: String? = null,
    val lastBackupAt: Long? = null,
    val lastAttemptAt: Long? = null,
    val lastError: CloudBackupError? = null,
) {
    val isConnected: Boolean get() = accountEmail != null

    /** The `app_state` rows (null = delete the row). */
    val rows: Map<String, String?>
        get() = mapOf(
            ACCOUNT to accountEmail, FOLDER to folderID, LAST_BACKUP to lastBackupAt?.toString(),
            LAST_ATTEMPT to lastAttemptAt?.toString(), LAST_ERROR to lastError?.rawValue,
        )

    companion object {
        const val ACCOUNT = "drive_account_email"
        const val FOLDER = "drive_folder_id"
        const val LAST_BACKUP = "drive_last_backup_at"
        const val LAST_ATTEMPT = "drive_last_attempt_at"
        const val LAST_ERROR = "drive_last_error"
        val ROW_KEYS = listOf(ACCOUNT, FOLDER, LAST_BACKUP, LAST_ATTEMPT, LAST_ERROR)

        fun fromRows(rows: Map<String, String>) = CloudBackupState(
            rows[ACCOUNT], rows[FOLDER], rows[LAST_BACKUP]?.toLongOrNull(), rows[LAST_ATTEMPT]?.toLongOrNull(),
            CloudBackupError.of(rows[LAST_ERROR]),
        )
    }
}

/**
 * A cloud the user backs up to (`spec/backup.md` §7; Google Drive in `:core:drive`). Calls throw
 * [CloudBackupException]. iOS: `CloudBackupDestination`.
 */
interface CloudBackupDestination {
    /** Signs in (asking for the one scope) and returns the account's email. */
    suspend fun connect(): String
    /** Revokes the token and forgets the account on this device. */
    suspend fun disconnect()
    /** §7.1: the app's folder — [knownID] when it is still there, otherwise found or created. */
    suspend fun folder(knownID: String?): String
    suspend fun list(folderID: String): List<CloudBackupEntry>
    /** Writes [data] (create or replace per [target]) and returns the file's id. */
    suspend fun upload(data: ByteArray, name: String, properties: Map<String, String>, target: CloudBackupTarget, folderID: String): String
    suspend fun download(id: String): ByteArray
    suspend fun delete(id: String)
}

/** Reads and writes the §7.7 state and knows when data last changed (the backup service implements it). */
interface CloudBackupStateStore {
    suspend fun cloudBackupState(): CloudBackupState
    suspend fun saveCloudBackupState(state: CloudBackupState)
    fun observeCloudBackupState(): Flow<CloudBackupState>
    /** §7.2: the highest `updated_at` over the synced tables; null without rows. */
    suspend fun latestChangeAt(): Long?
}

/** Runs automatic cloud backups (`spec/backup.md` §7): connect, back up when due or now, prune, list, download. */
class AutoBackupRunner(
    private val destination: CloudBackupDestination,
    private val backups: BackupService,
    private val state: CloudBackupStateStore,
    private val time: TimeSource,
    private val device: Device,
) {
    data class Device(val id: String, /** The model name ("Pixel 8", "iPhone"). */ val name: String, val app: BackupFile.AppInfo)

    /** The backup in progress: a second request waits for it instead of returning as if it had run. */
    private val running = Mutex()
    @Volatile private var lastRunError: CloudBackupException? = null

    /** §7.1: sign in, find or create the folder, back up at once when there is data. A failed first backup keeps the connection. */
    suspend fun connect() {
        val email = destination.connect()
        val folder = destination.folder(null)
        state.saveCloudBackupState(state.cloudBackupState().copy(accountEmail = email, folderID = folder, lastError = null))
        if (state.latestChangeAt() != null) {
            try { backUpNow() } catch (_: CloudBackupException) {} // recorded in the state; connected anyway
        }
    }

    /** §7.1: revoke and forget; files stay in the cloud. */
    suspend fun disconnect() {
        destination.disconnect()
        state.saveCloudBackupState(CloudBackupState())
    }

    /**
     * §7.2: the automatic path. Returns false when no backup is due; throws when one was due and failed, so background
     * work can retry. Cancellation propagates.
     */
    suspend fun backUpIfDue(): Boolean {
        val current = state.cloudBackupState()
        if (!current.isConnected || current.lastError == CloudBackupError.SignedOut) return false
        if (!AutoBackupRules.isDue(current.lastBackupAt, state.latestChangeAt(), current.lastAttemptAt, time.now())) return false
        backUpNow()
        return true
    }

    /** §7.2 "Back up now": export, upload (§7.3), prune (§7.4), record the result (§7.5). */
    suspend fun backUpNow() {
        if (!running.tryLock()) {
            // Join the backup already running and report its outcome.
            running.withLock {}
            lastRunError?.let { throw it }
            return
        }
        lastRunError = null
        try {
            var current = state.cloudBackupState()
            if (!current.isConnected) throw CloudBackupException(CloudBackupError.SignedOut)
            current = current.copy(lastAttemptAt = time.now())
            state.saveCloudBackupState(current)
            try {
                val file = backups.makeBackup(device.app)
                // §7.3: a folder that is gone or trashed is found or created again.
                val folder = destination.folder(current.folderID)
                upload(file, folder)
                current = current.copy(folderID = folder, lastBackupAt = file.createdAt, lastError = null)
                state.saveCloudBackupState(current)
                backups.recordBackup(time.now())
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                val reason = (error as? CloudBackupException)?.error ?: CloudBackupError.Other
                runCatching { state.saveCloudBackupState(current.copy(lastError = reason)) }
                throw CloudBackupException(reason).also { lastRunError = it }
            }
        } finally {
            running.unlock()
        }
    }

    /** §7.6: every tagged backup in the folder, newest first. */
    suspend fun list(): List<CloudBackupEntry> {
        val folder = destination.folder(state.cloudBackupState().folderID)
        return AutoBackupRules.newestFirst(destination.list(folder))
    }

    suspend fun download(entry: CloudBackupEntry): ByteArray = destination.download(entry.id)

    private suspend fun upload(file: BackupFile, folderID: String) {
        val data = BackupCodec.encode(file)
        val name = BackupFile.fileName(time.today())
        val entries = destination.list(folderID)
        val target = AutoBackupRules.target(entries, name, device.id)
        val properties = AutoBackupRules.properties(file, device.id, device.name)
        val id = destination.upload(data, name, properties, target, folderID)
        // §7.4: prune with the new file in the list (a failed delete waits for the next backup).
        val after = entries.filter { it.id != id } + CloudBackupEntry.of(id, name, properties)
        for (old in AutoBackupRules.filesToDelete(after, device.id)) runCatching { destination.delete(old) }
    }
}
