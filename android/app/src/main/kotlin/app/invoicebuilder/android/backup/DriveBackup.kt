package app.invoicebuilder.android.backup

import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.invoicebuilder.android.InvoiceApplication
import app.invoicebuilder.android.common.EditorSheet
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.NavRow
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.backup.AutoBackupRunner
import app.invoicebuilder.core.domain.backup.CloudBackupDestination
import app.invoicebuilder.core.domain.backup.CloudBackupEntry
import app.invoicebuilder.core.domain.backup.CloudBackupError
import app.invoicebuilder.core.domain.backup.CloudBackupException
import app.invoicebuilder.core.domain.backup.CloudBackupState
import app.invoicebuilder.core.domain.backup.CloudBackupStateStore
import app.invoicebuilder.core.domain.backup.CloudBackupTarget
import app.invoicebuilder.core.domain.support.TimeSource
import app.invoicebuilder.core.drive.ConsentLauncher
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.text.DateFormat
import java.util.Calendar
import java.util.Date
import java.util.concurrent.TimeUnit

/** An in-memory Google Drive for UI tests (`fakeDrive` extra ≈ iOS `-fakeDrive`): sign-in always succeeds. */
class DemoCloudBackup : CloudBackupDestination {
    private class File(val name: String, val properties: Map<String, String>, val data: ByteArray, val folder: String)
    private val lock = Mutex()
    private val files = linkedMapOf<String, File>()
    private val folders = mutableListOf<String>()
    private var counter = 0

    override suspend fun connect() = "you@example.com"
    override suspend fun disconnect() {}
    override suspend fun folder(knownID: String?): String = lock.withLock {
        if (knownID != null && knownID in folders) return knownID
        folders.firstOrNull() ?: "folder-${++counter}".also { folders += it }
    }
    override suspend fun list(folderID: String) = lock.withLock {
        files.filter { it.value.folder == folderID }.map { CloudBackupEntry.of(it.key, it.value.name, it.value.properties) }
    }
    override suspend fun upload(data: ByteArray, name: String, properties: Map<String, String>, target: CloudBackupTarget, folderID: String) =
        lock.withLock {
            val id = when (target) { CloudBackupTarget.Create -> "file-${++counter}"; is CloudBackupTarget.Update -> target.id }
            files[id] = File(name, properties, data, folderID)
            id
        }
    override suspend fun download(id: String) = lock.withLock { files[id]?.data } ?: throw CloudBackupException(CloudBackupError.Other)
    override suspend fun delete(id: String) { lock.withLock { files.remove(id) } }
}

/**
 * Google's consent sheet needs the visible Activity (≈ iOS presenting `ASWebAuthenticationSession` from the key
 * window). [MainActivity][app.invoicebuilder.android.MainActivity] registers its launcher here while it exists.
 */
object ConsentLaunchers {
    @Volatile var current: ConsentLauncher? = null

    /** Registers an `IntentSender` launcher on [activity] (before it starts) and publishes it. */
    fun register(activity: ComponentActivity) {
        var pending: CompletableDeferred<Intent?>? = null
        val launcher = activity.registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
            pending?.complete(if (result.resultCode == android.app.Activity.RESULT_OK) result.data else null)
        }
        current = ConsentLauncher { sender: IntentSender ->
            CompletableDeferred<Intent?>().also { pending = it; launcher.launch(IntentSenderRequest.Builder(sender).build()) }.await()
        }
    }
}

/** Settings → Backup → Google Drive and onboarding's restore (`spec/backup.md` §7). iOS: `DriveBackupModel`. */
class DriveBackupModel(
    private val runner: AutoBackupRunner,
    private val store: CloudBackupStateStore,
    private val time: TimeSource,
    private val scope: CoroutineScope,
) {
    var cloud by mutableStateOf(CloudBackupState())
    var isWorking by mutableStateOf(false)
        private set
    /** The restore list (§7.6): null until loaded; shown while non-null. */
    var backups by mutableStateOf<List<CloudBackupEntry>?>(null)
    var errorMessage by mutableStateOf<String?>(null)

    val isConnected get() = cloud.isConnected
    val hasError get() = isConnected && cloud.lastError != null

    val statusText: String
        get() = when {
            !isConnected -> DriveBackupText.NOT_CONNECTED
            cloud.lastError != null -> DriveBackupText.failed(cloud.lastError!!)
            else -> DriveBackupText.lastBackup(cloud.lastBackupAt, time.now())
        }

    suspend fun observe() = store.observeCloudBackupState().collect { cloud = it }

    fun connect() = work { runner.connect() }
    fun backUpNow() = work { runner.backUpNow() }
    fun disconnect() = work { runner.disconnect() }

    /** §7.6: signs in first when needed, then lists the backups, newest first. */
    fun showBackups() = work {
        if (!store.cloudBackupState().isConnected) runner.connect()
        backups = runner.list()
    }

    /** Downloads [entry] and hands the bytes to the usual restore (§4 step 1). */
    fun restore(entry: CloudBackupEntry, into: BackupViewModel) {
        backups = null
        work { into.loadBytes(runner.download(entry)) }
    }

    private fun work(body: suspend () -> Unit) {
        scope.launch {
            isWorking = true
            try {
                body()
            } catch (error: CloudBackupException) {
                if (error.error != CloudBackupError.Cancelled) errorMessage = DriveBackupText.failed(error.error)
            } catch (error: kotlinx.coroutines.CancellationException) {
                throw error
            } catch (error: Exception) {
                errorMessage = DriveBackupText.failed(CloudBackupError.Other)
            } finally {
                isWorking = false
                runCatching { cloud = store.cloudBackupState() }
            }
        }
    }
}

/** What the Google Drive rows say (`spec/backup.md` §7.5–7.6). iOS: `DriveBackupText`. */
object DriveBackupText {
    const val NOT_CONNECTED = "Back up automatically to your own Google Drive. Restore on any phone, Android or iPhone."

    fun failed(error: CloudBackupError) = when (error) {
        CloudBackupError.SignedOut -> "Couldn't back up to Google Drive: you're signed out. Connect again to carry on."
        CloudBackupError.QuotaExceeded -> "Couldn't back up to Google Drive: your Google Drive is full."
        CloudBackupError.NetworkUnavailable -> "Couldn't back up to Google Drive: no internet connection. It will try again."
        CloudBackupError.Cancelled, CloudBackupError.Other -> "Couldn't back up to Google Drive. It will try again later."
    }

    fun lastBackup(timestamp: Long?, now: Long) =
        if (timestamp == null) "Not backed up to Google Drive yet" else "Last backup to Google Drive: ${`when`(timestamp, now)}"

    /** "today at 14:02", "yesterday at 09:10" or "8 Oct 2026 at 18:30". */
    fun `when`(timestamp: Long, now: Long): String {
        val time = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(timestamp))
        val day = Calendar.getInstance().apply { timeInMillis = timestamp }
        val today = Calendar.getInstance().apply { timeInMillis = now }
        fun same(a: Calendar, b: Calendar) = a.get(Calendar.YEAR) == b.get(Calendar.YEAR) && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
        if (same(day, today)) return "today at $time"
        today.add(Calendar.DAY_OF_YEAR, -1)
        if (same(day, today)) return "yesterday at $time"
        return "${DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(timestamp))} at $time"
    }

    /** The restore list's first line: when, and from which device. */
    fun title(entry: CloudBackupEntry, now: Long): String {
        val platform = when (entry.platform) { "android" -> "Android"; "ios" -> "iOS"; else -> null }
        val device = listOfNotNull(entry.deviceName, platform?.let { "($it)" }).joinToString(" ")
        val time = entry.createdAt?.let { `when`(it, now) } ?: entry.name
        val first = time.replaceFirstChar { it.uppercase() }
        return if (device.isEmpty()) first else "$first · $device"
    }

    /** The second line: businesses and counts. */
    fun detail(entry: CloudBackupEntry) = listOfNotNull(
        entry.businesses?.takeIf { it.isNotEmpty() },
        entry.invoiceCount?.let { if (it == 1) "1 invoice" else "$it invoices" },
        entry.clientCount?.let { if (it == 1) "1 client" else "$it clients" },
    ).joinToString(" · ")
}

// Screens

/** Settings → Backup's "Google Drive" row, and the page behind it. iOS: `DriveBackupRow`. */
@Composable
fun DriveBackupRow(drive: DriveBackupModel, onOpen: () -> Unit) {
    NavRow("Google Drive", onOpen, icon = Icons.Filled.CloudUpload, tag = "backup.drive",
        value = if (drive.isConnected) (if (drive.hasError) "Needs attention" else "On") else "Off")
}

/** Settings → Backup → Google Drive (`spec/backup.md` §7.1, §7.5). iOS: `DriveBackupPage`. */
@Composable
fun DriveBackupPage(drive: DriveBackupModel, onDismiss: () -> Unit) {
    EditorSheet("Google Drive", onCancel = onDismiss, onSave = null) {
        if (!drive.isConnected) {
            FormSection(footer = DriveBackupText.NOT_CONNECTED) {
                NavRow("Back up to Google Drive automatically", drive::connect, icon = Icons.Filled.CloudUpload, tag = "backup.drive.connect")
            }
        } else {
            FormSection(footer = "Backs up after you make changes, and once a day, to the \"InvoiceBuilder backups\" folder. Keeps this device's newest 10. Stopping keeps the files.") {
                Row(Modifier.fillMaxWidth().padding(vertical = 12.dp).testTag("backup.drive.account"), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Person, null, tint = Theme.colors.textSecondary)
                    Text("  " + (drive.cloud.accountEmail ?: ""))
                }
                Row(Modifier.fillMaxWidth().padding(vertical = 12.dp).testTag("backup.drive.status"), verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (drive.hasError) Icons.Filled.Warning else Icons.Filled.CheckCircle, null,
                        tint = if (drive.hasError) Theme.colors.warning else Theme.colors.textSecondary)
                    Text("  " + drive.statusText)
                }
                if (drive.cloud.lastError == CloudBackupError.SignedOut) {
                    NavRow("Connect Google Drive again", drive::connect, icon = Icons.Filled.Refresh, tag = "backup.drive.reconnect")
                } else {
                    NavRow("Back up now", drive::backUpNow, icon = Icons.Filled.CloudUpload, tag = "backup.drive.backUpNow")
                }
                NavRow("Stop backing up to Google Drive", drive::disconnect, icon = Icons.Filled.Close, tag = "backup.drive.disconnect")
            }
        }
        if (drive.isWorking) CircularProgressIndicator(Modifier.padding(16.dp))
    }
}

/** The restore list and Drive errors, shared by Settings and onboarding (§7.6). iOS: `DriveRestoreFlow`. */
@Composable
fun DriveRestoreFlow(drive: DriveBackupModel, backup: BackupViewModel) {
    LaunchedEffect(drive) { drive.observe() }
    drive.backups?.let { entries ->
        EditorSheet("Restore from Google Drive", onCancel = { drive.backups = null }, onSave = null) {
            if (entries.isEmpty()) {
                FormSection(footer = "Backups appear here once the app on your other phone has backed up to this Google account.") {
                    Text("No backups in Google Drive yet", Modifier.padding(vertical = 12.dp))
                }
            } else {
                val now = System.currentTimeMillis()
                FormSection(footer = "Restoring replaces all the data on this device. A copy of the current data is kept first.") {
                    entries.forEachIndexed { index, entry ->
                        Column(Modifier.fillMaxWidth().clickable { drive.restore(entry, backup) }.padding(vertical = 10.dp).testTag("driveBackup-$index")) {
                            Text(DriveBackupText.title(entry, now), style = Theme.Fonts.style("rowTitle"), color = Theme.colors.textPrimary)
                            Text(DriveBackupText.detail(entry), style = Theme.Fonts.style("footnote"), color = Theme.colors.textSecondary)
                        }
                    }
                }
            }
        }
    }
    drive.errorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { drive.errorMessage = null }, title = { Text("Google Drive") }, text = { Text(message) },
            confirmButton = { TextButton({ drive.errorMessage = null }) { Text("OK") } },
        )
    }
}

/** The restore button for a Restore section. */
@Composable
fun DriveRestoreRow(drive: DriveBackupModel) {
    NavRow("Restore from Google Drive…", drive::showBackups, icon = Icons.Filled.CloudDownload, tag = "backup.drive.restore",
        tint = Theme.colors.danger)
}

// Background (spec/backup.md §7.2)

/** A backup when one is due: after the app leaves the screen, and once a day (WorkManager, needs a connection). */
class DriveBackupWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = try {
        val container = (applicationContext as InvoiceApplication).container
        val device = container.deviceState.loadOrCreate(Build.MODEL)
        container.autoBackupRunner(device.id)?.backUpIfDue()
        Result.success()
    } catch (cancelled: kotlinx.coroutines.CancellationException) {
        throw cancelled
    } catch (error: CloudBackupException) {
        // Signed out or Drive full: retrying can't help until the user acts (the Backup page says so).
        if (error.error == CloudBackupError.SignedOut || error.error == CloudBackupError.QuotaExceeded) Result.success() else Result.retry()
    } catch (error: Exception) {
        Result.retry()
    }

    companion object {
        /** A retry earlier than §7.2's 15-minute floor would find nothing due. */
        private const val BACKOFF_MINUTES = 15L
        private val network = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

        /** The app went to the background (≈ iOS `scenePhase == .background`). */
        fun appStopped(context: Context) {
            val work = WorkManager.getInstance(context)
            work.enqueueUniqueWork("driveBackupNow", ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<DriveBackupWorker>().setConstraints(network).setInitialDelay(1, TimeUnit.SECONDS)
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_MINUTES, TimeUnit.MINUTES).build())
            work.enqueueUniquePeriodicWork("driveBackup", ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<DriveBackupWorker>(1, TimeUnit.DAYS).setConstraints(network)
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_MINUTES, TimeUnit.MINUTES).build())
        }
    }
}

