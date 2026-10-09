package app.invoicebuilder.android.backup

import android.content.ContentResolver
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.invoicebuilder.android.app.AppContainer
import app.invoicebuilder.core.domain.backup.BackupCodec
import app.invoicebuilder.core.domain.backup.BackupError
import app.invoicebuilder.core.domain.backup.BackupFile
import app.invoicebuilder.core.domain.backup.BackupPreview
import app.invoicebuilder.core.domain.backup.BackupStatus
import app.invoicebuilder.core.domain.decimal.Outcome
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Settings → Backup, and "Restore from a backup" in onboarding (`spec/backup.md`). Works without a `Session`, so a
 * new device can restore before any business exists. iOS: `BackupViewModel`.
 *
 * Android's file pickers are the Storage Access Framework: `CreateDocument` (≈ `.fileExporter`) writes the export
 * to a place the user picks, `OpenDocument` (≈ `.fileImporter`) returns a `content://` Uri to read.
 */
class BackupViewModel(
    private val container: AppContainer,
    private val deviceID: String,
    private val scope: CoroutineScope,
    private val appVersion: String,
    /** After a restore committed: drop caches and rebuild the app from the database (§4 step 5). */
    private val onRestored: suspend () -> Unit,
) {
    var status by mutableStateOf<BackupStatus?>(null)
        private set
    /** An export ready to save or share. */
    var export by mutableStateOf<BackupExport?>(null)
        private set
    /** A file that passed validation, waiting for the user to confirm (§4 step 2). */
    var pendingRestore by mutableStateOf<BackupPreview?>(null)
        private set
    var isWorking by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
    var didRestore by mutableStateOf(false)
        private set

    val today get() = container.time.today()
    val isDue: Boolean get() = status?.isDue(today) ?: false
    val lastBackupText: String get() = BackupText.lastBackup(status?.daysSinceLastBackup(today))

    fun observe() {
        scope.launch { container.backup.observeStatus().collect { status = it } }
    }

    // Export (§2)

    /** Builds the file; the screen then opens the save picker or the share sheet. */
    suspend fun prepareExport(): BackupExport? {
        isWorking = true
        try {
            val file = container.backup.makeBackup(BackupFile.AppInfo("android", appVersion))
            return withContext(Dispatchers.IO) { BackupExport.make(file, today, container.cacheDirectory) }.also { export = it }
        } catch (error: Exception) {
            errorMessage = BackupText.exportFailed
            return null
        } finally {
            isWorking = false
        }
    }

    /** The save picker returned a destination: write the bytes there. Only a completed save counts as a backup. */
    fun saveExport(to: Uri, resolver: ContentResolver) {
        val export = export ?: return
        scope.launch {
            val written = withContext(Dispatchers.IO) {
                runCatching { resolver.openOutputStream(to, "wt")?.use { it.write(export.file.readBytes()) } != null }.getOrDefault(false)
            }
            if (written) container.backup.recordBackup(container.time.now()) else errorMessage = BackupText.exportFailed
        }
    }

    /** The share sheet cannot report whether the file was kept, so sharing counts as a backup (as iOS's "completed"). */
    fun shared() {
        scope.launch { container.backup.recordBackup(container.time.now()) }
    }

    // Restore (§4)

    /** A file picked or opened from another app (§6): read and validated off the main thread, then previewed. */
    fun open(uri: Uri, resolver: ContentResolver) {
        scope.launch {
            isWorking = true
            try {
                val bytes = withContext(Dispatchers.IO) { runCatching { resolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull() }
                if (bytes == null) errorMessage = BackupText.unreadable else load(bytes)
            } finally {
                isWorking = false
            }
        }
    }

    /** Decoding and checking a whole backup is heavy JSON work: on a background thread (≈ a detached task on iOS). */
    private suspend fun load(bytes: ByteArray) {
        val schemaVersion = container.backup.schemaVersion
        when (val result = withContext(Dispatchers.Default) { BackupCodec.validate(bytes, schemaVersion) }) {
            is Outcome.Success -> pendingRestore = result.value
            is Outcome.Failure -> errorMessage = BackupText.message(result.error.code)
        }
    }

    fun cancelRestore() { pendingRestore = null }

    fun confirmRestore() {
        val pending = pendingRestore ?: return
        scope.launch {
            isWorking = true
            try {
                container.backup.restore(pending.file, deviceID)
                pendingRestore = null
                didRestore = true
                onRestored()
            } catch (error: Exception) {
                pendingRestore = null
                errorMessage = BackupText.restoreFailed
            } finally {
                isWorking = false
            }
        }
    }
}

/** An exported backup written to the cache, for the share sheet (via FileProvider) and the save picker. */
data class BackupExport(val fileName: String, val file: File) {
    companion object {
        fun make(backup: BackupFile, today: java.time.LocalDate, cache: File): BackupExport {
            val name = BackupFile.fileName(today)
            val folder = File(cache, "backups").also { it.mkdirs() }
            folder.listFiles()?.forEach { it.delete() } // one outgoing backup at a time
            val target = File(folder, name)
            target.writeBytes(BackupCodec.encode(backup))
            return BackupExport(name, target)
        }
    }
}

/** What the backup screens say (`spec/backup.md` §3, §5). */
object BackupText {
    fun lastBackup(days: Int?): String = when (days) {
        null -> "Never backed up"
        0 -> "Last backup: today"
        1 -> "Last backup: yesterday"
        else -> "Last backup: $days days ago"
    }

    fun message(code: BackupError.Code): String = when (code) {
        BackupError.Code.NotJSON, BackupError.Code.NotABackup -> "This file isn't an InvoiceBuilder backup."
        BackupError.Code.NewerFormat, BackupError.Code.NewerSchema ->
            "This backup was made by a newer version of the app. Update the app, then try again."
        else -> "This backup is damaged and can't be restored. Nothing was changed."
    }

    const val unreadable = "The file couldn't be opened."
    const val exportFailed = "The backup couldn't be created. Try again."
    const val restoreFailed = "The backup couldn't be restored. Nothing was changed."
}
