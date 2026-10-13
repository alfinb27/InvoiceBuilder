package app.invoicebuilder.android.backup

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import app.invoicebuilder.android.common.DetailColumn
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.NavRow
import app.invoicebuilder.core.designsystem.SwitchRow
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.backup.AutoBackupRunner
import app.invoicebuilder.core.domain.backup.CloudBackupError
import app.invoicebuilder.core.domain.backup.CloudBackupException
import app.invoicebuilder.core.domain.backup.CloudBackupStateStore
import app.invoicebuilder.core.domain.backup.DriveSyncEngine
import app.invoicebuilder.core.domain.backup.DriveSyncState
import app.invoicebuilder.core.domain.backup.DriveSyncStore
import app.invoicebuilder.core.domain.support.TimeSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** Settings → Sync and Welcome → "Sync with Google Drive" (`spec/drive-sync.md` §1, §7, §9). iOS: `DriveSyncModel`. */
class DriveSyncModel(
    private val engine: DriveSyncEngine,
    private val store: DriveSyncStore,
    private val autoBackup: AutoBackupRunner?,
    private val backupState: CloudBackupStateStore,
    private val time: TimeSource,
    private val scope: CoroutineScope,
    /** After a pull that changed records (`sync.md` §5: reminders, or a reload when a business arrived). */
    private val onMerged: suspend (Int) -> Unit = {},
) {
    var sync by mutableStateOf(DriveSyncState())
    var isWorking by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)

    val isOn get() = sync.isConnected
    val hasError get() = isOn && sync.lastError != null
    val statusText get() = DriveSyncText.status(sync, time.now())

    suspend fun observe() = store.observeDriveSyncState().collect { sync = it }

    /** §1, §7: connect and merge; Drive backup comes on with it. */
    fun connect() = work {
        engine.connect()
        if (!backupState.cloudBackupState().isConnected) autoBackup?.let { runner -> runCatching { runner.connect() } }
        onMerged(1)
    }

    fun syncNow() = work {
        val changed = engine.syncNow()
        if (changed > 0) onMerged(changed)
    }

    /** §7: the files stay in Drive. */
    fun disconnect() = work { engine.disconnect() }

    private fun work(body: suspend () -> Unit) {
        scope.launch {
            isWorking = true
            try {
                body()
            } catch (error: CloudBackupException) {
                if (error.error != CloudBackupError.Cancelled) errorMessage = DriveSyncText.failed(error.error)
            } catch (error: kotlinx.coroutines.CancellationException) {
                throw error
            } catch (error: Exception) {
                errorMessage = DriveSyncText.failed(CloudBackupError.Other)
            } finally {
                isWorking = false
                runCatching { sync = store.driveSyncState() }
            }
        }
    }
}

/** What the Google Drive sync rows say (`spec/drive-sync.md` §9). iOS: `DriveSyncText`. */
object DriveSyncText {
    const val OFF = "Keep this phone in step with your other phones, Android or iPhone, through your own Google Drive."

    fun failed(error: CloudBackupError) = when (error) {
        CloudBackupError.SignedOut -> "Paused: you're signed out of Google Drive. Connect again to carry on."
        CloudBackupError.QuotaExceeded -> "Paused: your Google Drive is full."
        CloudBackupError.NetworkUnavailable -> "Waiting for the network"
        CloudBackupError.Cancelled, CloudBackupError.Other -> "Couldn't sync with Google Drive. It will try again. If this keeps happening, update the app."
    }

    fun status(state: DriveSyncState, now: Long): String = when {
        !state.isConnected -> OFF
        state.lastError != null -> failed(state.lastError!!)
        state.lastSyncAt == null -> "Syncing…"
        else -> "Up to date · synced ${DriveBackupText.`when`(state.lastSyncAt!!, now)}"
    }
}

/** Settings → Sync (Android syncs only through Google Drive). iOS: the Google Drive section of `SyncPage`. */
@Composable
fun DriveSyncPage(model: DriveSyncModel) {
    LaunchedEffect(model) { model.observe() }
    var confirming by rememberSaveable { mutableStateOf(false) }
    DetailColumn {
        FormSection(header = "Google Drive",
            footer = "Works between Android phones, iPhones and iPads through your own Google Drive. Turning it off keeps everything here and in Drive.") {
            Row(Modifier.fillMaxWidth().padding(vertical = 12.dp).testTag("sync.drive.status"), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (model.hasError) Icons.Filled.Warning else Icons.Filled.Sync, null,
                    tint = if (model.hasError) Theme.colors.warning else Theme.colors.textSecondary)
                Text("  " + model.statusText)
            }
            SwitchRow("Sync with Google Drive", model.isOn, { on -> if (on) confirming = true else model.disconnect() },
                enabled = !model.isWorking, tag = "sync.drive")
            if (model.isOn) NavRow("Sync now", model::syncNow, icon = Icons.Filled.Sync, tag = "sync.drive.now")
        }
        if (model.isWorking) CircularProgressIndicator(Modifier.padding(16.dp))
    }
    if (confirming) {
        AlertDialog(
            { confirming = false }, title = { Text("Sync with Google Drive?") },
            text = { Text("The businesses on this phone and in your Google Drive will be combined.") },
            confirmButton = {
                TextButton({ confirming = false; model.connect() }, Modifier.testTag("sync.drive.confirm")) { Text("Sync with Google Drive") }
            },
            dismissButton = { TextButton({ confirming = false }) { Text("Cancel") } },
        )
    }
    model.errorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { model.errorMessage = null }, title = { Text("Google Drive") }, text = { Text(message) },
            confirmButton = { TextButton({ model.errorMessage = null }) { Text("OK") } },
        )
    }
}
