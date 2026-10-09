package app.invoicebuilder.android.backup

import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.common.SystemSheets
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.LabeledValue
import app.invoicebuilder.core.designsystem.NavRow
import app.invoicebuilder.core.designsystem.ReadableColumn
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.backup.BackupPreview
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

/** Settings → Backup (`spec/backup.md` §2, §4, §5). iOS: `BackupPage`. */
@Composable
fun BackupPage(session: Session, model: BackupViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val flows = rememberBackupFlows(model)
    val incoming = session.router.settings.incomingBackup
    LaunchedEffect(incoming) {
        if (incoming != null) {
            session.router.settings.incomingBackup = null
            model.open(incoming, context.contentResolver)
        }
    }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            ReadableColumn(Modifier.fillMaxWidth()) {
                FormSection(
                    "Back up",
                    if (model.isDue) "You haven't backed up in a while. Save a backup somewhere other than this device."
                    else "One file with your business, clients, items, invoices, quotes and payments. Keep it somewhere safe, such as Google Drive or your email.",
                ) {
                    androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("backup.last")) {
                        Icon(if (model.isDue) Icons.Filled.Warning else Icons.Filled.CheckCircle, null,
                            tint = if (model.isDue) Theme.colors.warning else Theme.colors.textSecondary)
                        Text("  " + model.lastBackupText)
                    }
                    NavRow("Save backup to a file", { flows.saveToFile() }, icon = Icons.Filled.Folder, tag = "backup.saveToFiles")
                    NavRow("Share backup…", {
                        scope.launch {
                            val export = model.prepareExport() ?: return@launch
                            SystemSheets.shareFile(context, export.file, "application/json", export.fileName)
                            model.shared()
                        }
                    }, icon = Icons.Filled.Share)
                }
                FormSection("Restore", "Replaces all the data on this device with the backup. A copy of the current data is kept first.") {
                    NavRow("Restore from a backup…", { flows.pickFile() }, icon = Icons.Filled.History, tag = "backup.restore", tint = Theme.colors.danger)
                }
            }
        }
        if (model.isWorking) CircularProgressIndicator(Modifier.align(Alignment.Center))
    }
}

/** The save and open pickers, the confirmation and the error alert, shared by Settings and onboarding. */
class BackupFlowLaunchers(val saveToFile: () -> Unit, val pickFile: () -> Unit)

@Composable
fun rememberBackupFlows(model: BackupViewModel): BackupFlowLaunchers {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // ≈ `.fileExporter`: the user picks where the file goes; the app then writes it.
    val creator = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) model.saveExport(uri, context.contentResolver)
    }
    // ≈ `.fileImporter`: any file (backups arrive with all sorts of MIME types from chat apps and mail).
    val opener = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) model.open(uri, context.contentResolver)
    }
    model.pendingRestore?.let { preview ->
        RestoreConfirmation(preview, model.isWorking, onCancel = model::cancelRestore, onConfirm = model::confirmRestore)
    }
    model.errorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { model.errorMessage = null },
            title = { Text("Backup") }, text = { Text(message) },
            confirmButton = { TextButton({ model.errorMessage = null }) { Text("OK") } },
        )
    }
    return BackupFlowLaunchers(
        saveToFile = { scope.launch { model.prepareExport()?.let { creator.launch(it.fileName) } } },
        pickFile = { opener.launch(arrayOf("application/json", "application/octet-stream", "*/*")) },
    )
}

/** §4 step 2: what the backup holds and what restoring does, before anything changes. */
@Composable
fun RestoreConfirmation(preview: BackupPreview, isWorking: Boolean, onCancel: () -> Unit, onConfirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = { if (!isWorking) onCancel() },
        title = { Text("Restore backup?") },
        text = {
            Column {
                LabeledValue("Made", DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(preview.file.createdAt)))
                LabeledValue("On", if (preview.file.app.platform == "android") "Android" else "iPhone or iPad")
                Text("It contains", fontWeight = FontWeight.SemiBold, modifier = androidx.compose.ui.Modifier.fillMaxWidth())
                LabeledValue("Businesses", preview.live.businesses.toString())
                LabeledValue("Clients", preview.live.clients.toString())
                LabeledValue("Items", preview.live.catalogItems.toString())
                LabeledValue("Invoices and quotes", preview.live.documents.toString())
                LabeledValue("Payments", preview.live.payments.toString())
                Text("Everything on this device is replaced by the backup. A copy of the current data is kept on this device first.",
                    color = Theme.colors.textSecondary)
                if (isWorking) CircularProgressIndicator()
            }
        },
        confirmButton = {
            TextButton(onConfirm, enabled = !isWorking, modifier = Modifier.testTag("backup.confirmRestore")) {
                Text("Replace all data", color = Theme.colors.danger)
            }
        },
        dismissButton = { TextButton(onCancel, enabled = !isWorking) { Text("Cancel") } },
    )
}

fun appVersion(context: Context): String = app.invoicebuilder.android.app.AppContainer.appVersion(context)
