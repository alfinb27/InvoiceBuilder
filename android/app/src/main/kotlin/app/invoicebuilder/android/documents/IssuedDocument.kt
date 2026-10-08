package app.invoicebuilder.android.documents

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.automirrored.filled.ReceiptLong
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import app.invoicebuilder.android.app.DocumentAction
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.common.DetailColumn
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.LabeledValue
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.models.DocumentType

/**
 * An issued invoice or quote, read-only: what was frozen at issue. Duplicating starts a new draft; an issued quote
 * can be converted. iOS: `IssuedDocumentView`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IssuedDocument(model: DocumentViewModel, session: Session, showsBack: Boolean, onBack: () -> Unit) {
    val document = model.document
    val config = model.config
    var menu by remember { mutableStateOf(false) }
    var showingVoid by rememberSaveable { mutableStateOf(false) }
    var voidReason by rememberSaveable { mutableStateOf("") }
    var showingPayment by rememberSaveable { mutableStateOf(false) }

    // A row action chosen in the list, once this document is on screen.
    val pending = session.router.documents.pendingAction
    LaunchedEffect(pending, document.id) {
        when (session.router.documents.takeAction(document.id)) {
            DocumentAction.share -> model.openPreview()
            DocumentAction.recordPayment -> if (model.canRecordPayment) showingPayment = true
            DocumentAction.void -> if (model.canVoid) { voidReason = ""; showingVoid = true }
            null -> {}
        }
    }

    Scaffold(
        containerColor = Theme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(document.number ?: "") },
                navigationIcon = { if (showsBack) IconButton(onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                actions = {
                    IconButton({ model.openPreview() }, enabled = model.canPreview, modifier = Modifier.testTag("previewButton")) {
                        Icon(Icons.Filled.Share, "Share")
                    }
                    Box {
                        IconButton({ menu = true }, Modifier.testTag("documentActions")) { Icon(Icons.Filled.MoreVert, "Actions") }
                        DropdownMenu(menu, { menu = false }) {
                            DropdownMenuItem({ Text("Duplicate") }, { menu = false; model.duplicate() }, leadingIcon = { Icon(Icons.Filled.ContentCopy, null) })
                            if (model.canConvert) {
                                DropdownMenuItem({ Text("Convert to invoice") }, { menu = false; model.convertToInvoice() },
                                    leadingIcon = { Icon(Icons.AutoMirrored.Filled.ReceiptLong, null) }, modifier = Modifier.testTag("convertToInvoice"))
                            }
                            if (model.canRecordPayment) {
                                DropdownMenuItem({ Text("Record payment") }, { menu = false; showingPayment = true },
                                    leadingIcon = { Icon(Icons.Filled.Payments, null) }, modifier = Modifier.testTag("recordPayment"))
                            }
                            if (model.canSendReminder) {
                                DropdownMenuItem({ Text("Send reminder") }, { menu = false; model.sendReminder() },
                                    leadingIcon = { Icon(Icons.Filled.NotificationsActive, null) }, modifier = Modifier.testTag("sendReminder"))
                            }
                            if (model.canRespondToQuote) {
                                DropdownMenuItem({ Text("Mark accepted") }, { menu = false; model.acceptQuote() }, leadingIcon = { Icon(Icons.Filled.CheckCircle, null) })
                                DropdownMenuItem({ Text("Mark declined") }, { menu = false; model.declineQuote() }, leadingIcon = { Icon(Icons.Filled.Cancel, null) })
                            }
                            if (model.canVoid) {
                                DropdownMenuItem({ Text("Void", color = Theme.colors.danger) }, { menu = false; voidReason = ""; showingVoid = true },
                                    leadingIcon = { Icon(Icons.Filled.Block, null, tint = Theme.colors.danger) }, modifier = Modifier.testTag("voidDocument"))
                            }
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Theme.colors.background),
            )
        },
    ) { padding ->
        DetailColumn(Modifier.padding(padding)) {
            Column(Modifier.fillMaxWidth().padding(vertical = Theme.Space.m),
                verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                Text(document.computed?.title ?: DocumentText.noun(document.docType).replaceFirstChar(Char::uppercase),
                    color = Theme.colors.textSecondary)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(document.number ?: "", Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
                    StatusTag(document.status(session.today, model.paidMinor))
                }
                Text(session.money(document.totals.totalMinor, document.currency), style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.testTag("issuedTotal"))
                if (document.docType == DocumentType.invoice && model.paidMinor > 0) {
                    val outstanding = maxOf(document.totals.totalMinor - model.paidMinor, 0)
                    Text("${session.money(model.paidMinor, document.currency)} paid · ${session.money(outstanding, document.currency)} outstanding",
                        style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
                }
            }
            if (document.lifecycle == DocumentLifecycle.void) {
                FormSection("Void") {
                    document.voidReason?.let { LabeledValue("Reason", it) }
                    document.voidedAt?.let { LabeledValue("Voided", localDate(it).displayText) }
                }
            }
            document.buyerSnapshot?.let { buyer ->
                FormSection("Client") {
                    Text(buyer.name ?: "", fontWeight = FontWeight.Medium)
                    buyer.address?.let { Text(it) }
                    buyer.taxId?.let { Text(if (buyer.country == session.business.countryCode) "${config.labels.taxIdName} $it" else it, fontFamily = FontFamily.Monospace) }
                }
            }
            FormSection("Dates") {
                LabeledValue("Issued", document.issueDate.displayText)
                document.supplyDate?.let { LabeledValue("Supply date", it.displayText) }
                document.dueDate?.let { LabeledValue("Due", it.displayText) }
                document.validUntil?.let { LabeledValue("Valid until", it.displayText) }
                document.computed?.placeOfSupply?.let { LabeledValue(config.labels.placeOfSupply ?: "Place of supply", config.region(it)?.name ?: it) }
            }
            FormSection("Items") {
                document.lines.forEachIndexed { index, line ->
                    LineRow(line, document.computed?.lines?.getOrNull(index), document.currency, document.computed?.chargesTax ?: false, session)
                    HorizontalDivider(color = Theme.colors.border.copy(alpha = 0.5f))
                }
            }
            FormSection("Totals") { TotalsView(document.computed, null, document.currency, config, session) }
            if (model.payments.isNotEmpty()) {
                FormSection("Payments") {
                    for (payment in model.payments) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(PaymentMethodText.label(payment.method))
                                Text(payment.date.displayText, style = MaterialTheme.typography.labelSmall, color = Theme.colors.textSecondary)
                                payment.reference?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = Theme.colors.textTertiary) }
                            }
                            Text(session.money(payment.amountMinor, document.currency))
                            IconButton({ model.deletePayment(payment) }) { Icon(Icons.Filled.Delete, "Delete payment", tint = Theme.colors.danger) }
                        }
                    }
                }
            }
            document.notes?.let { FormSection("Notes") { Text(it) } }
            document.terms?.let { FormSection("Terms") { Text(it) } }
            document.computed?.notes?.takeIf { it.isNotEmpty() }?.let { notes ->
                FormSection("Printed notes") { for (note in notes) Text(note.text, style = MaterialTheme.typography.bodySmall) }
            }
        }
    }

    if (showingVoid) {
        AlertDialog(
            onDismissRequest = { showingVoid = false },
            title = { Text("Void this ${DocumentText.noun(document.docType)}?") },
            text = {
                Column {
                    Text("Its number is kept and cannot be reused. This cannot be undone.")
                    OutlinedTextField(voidReason, { voidReason = it }, Modifier.fillMaxWidth().testTag("voidReasonField"), label = { Text("Reason") })
                }
            },
            confirmButton = { TextButton({ showingVoid = false; model.voidDocument(voidReason) }, Modifier.testTag("confirmVoid")) { Text("Void", color = Theme.colors.danger) } },
            dismissButton = { TextButton({ showingVoid = false }) { Text("Cancel") } },
        )
    }
    if (showingPayment) {
        PaymentEditor(session, document.id, document.currency, onSaved = model::recordedPayment, onDismiss = { showingPayment = false })
    }
}
