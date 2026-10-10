package app.invoicebuilder.android.documents

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.input.KeyboardType
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.invoicebuilder.android.app.EditorRoute
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.clients.ClientEditor
import app.invoicebuilder.android.common.ConfirmDialog
import app.invoicebuilder.android.common.EditorSheet
import app.invoicebuilder.android.common.ErrorAlert
import app.invoicebuilder.android.common.SearchField
import app.invoicebuilder.core.designsystem.DateField
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.FormTextField
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.designsystem.NavRow
import app.invoicebuilder.core.designsystem.PickerField
import app.invoicebuilder.core.designsystem.Tag
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.documents.DocumentInput
import app.invoicebuilder.core.domain.documents.Payment
import app.invoicebuilder.core.domain.documents.PaymentMethod
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.setup.SetupSearch
import app.invoicebuilder.core.domain.support.trimmedOrNull
import kotlinx.coroutines.launch

/** Choosing the client: search, "No client" (walk-in) or a new client added on the spot. iOS: `ClientPickerSheet`. */
@Composable
fun ClientPickerSheet(session: Session, selectedID: String?, onPick: (Client?) -> Unit, onDismiss: () -> Unit) {
    val clients by remember(session.business.id) { session.container.clients.observeClients(session.business.id) }.collectAsStateWithLifecycle(emptyList())
    var query by rememberSaveable { mutableStateOf("") }
    var adding by rememberSaveable { mutableStateOf(false) }
    EditorSheet("Client", onCancel = onDismiss, onSave = { adding = true }, saveTitle = "New client", saveTag = "newClient") {
        SearchField(query, { query = it }, "Name, ${session.config.labels.taxIdName}, email or phone")
        PickerRow("No client", "A walk-in customer", selectedID == null, "client-none") { onPick(null); onDismiss() }
        HorizontalDivider(color = Theme.colors.border)
        for (client in SetupSearch.clients(clients.filter { !it.isArchived }, query)) {
            val detail = when {
                client.countryCode != session.business.countryCode -> session.countryName(client.countryCode)
                client.taxId != null -> "${session.config.labels.taxIdName} ${client.taxId}"
                else -> client.billingAddress?.city
            }
            PickerRow(client.name, detail, client.id == selectedID, "pickClient-${client.name}") { onPick(client); onDismiss() }
        }
    }
    if (adding) ClientEditor(session, EditorRoute.New, onDone = { adding = false }, onSaved = { onPick(it); onDismiss() })
}

@Composable
private fun PickerRow(title: String, detail: String?, selected: Boolean, tag: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).semantics(mergeDescendants = true) { this.selected = selected }.testTag(tag)
        .padding(vertical = Theme.Space.s), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title)
            if (detail != null) Text(detail, style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
        }
        if (selected) Icon(Icons.Filled.Check, null, tint = Theme.colors.brand)
    }
}

/** The first issue on a device that owns no series of this type (`spec/sync.md` §3). iOS: `SeriesChoiceSheet`. */
@Composable
fun SeriesChoiceSheet(choice: DocumentViewModel.SeriesChoice, docType: DocumentType, startOwn: () -> Unit, takeOver: (String) -> Unit, cancel: () -> Unit) {
    var pending by remember { mutableStateOf<DocumentViewModel.SeriesChoice.Option?>(null) }
    EditorSheet("Numbering on this device", onCancel = cancel, onSave = null) {
        choice.ownFirstNumber?.let { first ->
            FormSection(footer = "Each device numbers from its own series, so two devices never give out the same number.") {
                NavRow("Start numbering on this device", startOwn, subtitle = "The first will be $first", tag = "series.startOwn")
            }
        }
        if (choice.others.isNotEmpty()) {
            FormSection("Continue another device's series",
                "Only if that device no longer issues ${DocumentText.noun(docType)}s, such as a phone you replaced.") {
                for (option in choice.others) NavRow(option.series.label, { pending = option }, subtitle = option.nextNumber?.let { "Continues with $it" })
            }
        }
    }
    pending?.let { option ->
        ConfirmDialog("Continue ${option.series.label}?", "The other device will have to choose numbering again before it issues.",
            "Continue on this device", { takeOver(option.series.id) }, { pending = null }, destructive = false)
    }
}

/** Recording a payment (`spec/documents.md` §10). A correction is delete-and-re-add. iOS: `PaymentEditorViewModel`. */
class PaymentEditorViewModel(private val session: Session, val documentID: String, val currency: CurrencyCode) {
    var amountText by mutableStateOf("")
    var date by mutableStateOf(session.today)
    var method by mutableStateOf(PaymentMethod.cash)
    var reference by mutableStateOf("")
    var note by mutableStateOf("")
    var attemptedSave by mutableStateOf(false)
        private set
    var isSaving by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)

    private val exponent get() = session.container.reference.currencies.exponent(currency)
    val amountIssue get() = (DocumentInput.paymentAmount(amountText, exponent) as? Outcome.Failure)?.error
    fun visibleAmountIssue() = if (attemptedSave) amountIssue else null

    suspend fun save(): Payment? {
        attemptedSave = true
        val amount = (DocumentInput.paymentAmount(amountText, exponent) as? Outcome.Success)?.value ?: return null
        isSaving = true
        return try {
            session.container.paymentService.recordPayment(documentID, amount, date, method, reference.trimmedOrNull, note.trimmedOrNull)
        } catch (error: Exception) {
            errorMessage = "The payment couldn't be recorded."
            null
        } finally {
            isSaving = false
        }
    }
}

/** Record a payment (`spec/documents.md` §10). iOS: `PaymentEditorView`. */
@Composable
fun PaymentEditor(session: Session, documentID: String, currency: CurrencyCode, onSaved: (Payment) -> Unit, onDismiss: () -> Unit) {
    val key = "payment-$documentID"
    val model = session.retained(key) { PaymentEditorViewModel(session, documentID, currency) }
    val scope = rememberCoroutineScope()
    fun close() { session.release(key); onDismiss() }
    EditorSheet("Record payment", onCancel = ::close, onSave = { scope.launch { model.save()?.let { onSaved(it); close() } } },
        isBusy = model.isSaving, saveTag = "savePayment") {
        FormSection {
            FormTextField("Amount (${currency.rawValue})", model.amountText, { model.amountText = it }, prompt = "0",
                issue = model.visibleAmountIssue()?.let { IssueMessages.text(it, "amount") }, keyboard = KeyboardType.Decimal, tag = "paymentAmountField")
            DateField("Date", model.date, { model.date = it })
            PickerField("Method", model.method, PaymentMethodText.all.map { it to PaymentMethodText.label(it) }, { it?.let { m -> model.method = m } })
        }
        FormSection {
            FormTextField("Reference (optional)", model.reference, { model.reference = it })
            FormTextField("Note (optional)", model.note, { model.note = it })
        }
    }
    ErrorAlert(model.errorMessage, { model.errorMessage = null })
}
