package app.invoicebuilder.android.app

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.invoicebuilder.core.domain.documents.DocumentStatus
import app.invoicebuilder.core.domain.models.DocumentType
import java.time.LocalDate

/**
 * All navigation state (iOS: `AppRouter`). Compose snapshot state (`mutableStateOf`) is the `@Observable` of
 * Compose: a screen that reads a property recomposes when it changes. The router lives in the `Session`, which lives
 * in the activity's `ViewModel`, so it survives rotation, folding and window resizing — the Android twin of ADR-0014.
 */
enum class AppTab { home, documents, clients, items, settings }

class AppRouter {
    var selectedTab by mutableStateOf(AppTab.home)
    val documents = DocumentsRouter()
    val clients = ListDetailRouter()
    val items = ListDetailRouter()
    val settings = SettingsRouter()

    fun startNewClient() {
        selectedTab = AppTab.clients
        clients.editor = EditorRoute.New
    }

    fun startNewItem() {
        selectedTab = AppTab.items
        items.editor = EditorRoute.New
    }
}

/** A list/detail section (clients, items). */
class ListDetailRouter {
    /** The row shown in the detail pane (pushed on phones). */
    var selection by mutableStateOf<String?>(null)
    var editor by mutableStateOf<EditorRoute?>(null)
    var searchText by mutableStateOf("")
    var showArchived by mutableStateOf(false)

    fun edit(id: String) { editor = EditorRoute.Edit(id) }

    fun didSave(id: String) {
        editor = null
        selection = id
    }

    fun didRemove(id: String) {
        if (selection == id) selection = null
    }
}

class DocumentsRouter {
    var docType by mutableStateOf(DocumentType.invoice)
    var selection by mutableStateOf<DocumentRoute?>(null)
    var searchText by mutableStateOf("")
    var statusFilter by mutableStateOf(InvoiceStatusFilter.all)
    var dateFilter by mutableStateOf(DocumentDateFilter.allTime)
    var pendingAction by mutableStateOf<PendingDocumentAction?>(null)
    /** A draft is open in the builder: on phones it has the screen to itself (no bottom bar), as on iOS. */
    var isEditingDraft by mutableStateOf(false)

    fun open(id: String) { selection = DocumentRoute.Existing(id) }

    fun open(id: String, then: DocumentAction) {
        selection = DocumentRoute.Existing(id)
        pendingAction = PendingDocumentAction(id, then)
    }

    fun takeAction(documentID: String): DocumentAction? {
        val pending = pendingAction?.takeIf { it.documentID == documentID } ?: return null
        pendingAction = null
        return pending.action
    }

    fun didRemove(id: String) {
        if (selection?.id == id) selection = null
    }
}

enum class DocumentAction { share, recordPayment, void }

data class PendingDocumentAction(val documentID: String, val action: DocumentAction)

/** The Invoices list's status segments. */
enum class InvoiceStatusFilter(val label: String) {
    all("All"), unpaid("Waiting"), overdue("Past due"), paid("Paid");

    fun matches(status: DocumentStatus): Boolean = when (this) {
        all -> true
        unpaid -> status in setOf(DocumentStatus.issued, DocumentStatus.sent, DocumentStatus.partiallyPaid, DocumentStatus.overdue)
        overdue -> status == DocumentStatus.overdue
        paid -> status == DocumentStatus.paid
    }
}

enum class DocumentDateFilter(val label: String) {
    allTime("All time"), thisMonth("This month"), last30Days("Last 30 days"), last3Months("Last 3 months");

    fun from(today: LocalDate): LocalDate? = when (this) {
        allTime -> null
        thisMonth -> today.withDayOfMonth(1)
        last30Days -> today.minusDays(30)
        last3Months -> today.minusDays(90)
    }
}

/** A document in the detail pane: a stored one, or a new draft written on its first change. */
sealed interface DocumentRoute {
    val id: String
    data class New(val docType: DocumentType, override val id: String) : DocumentRoute
    data class Existing(override val id: String) : DocumentRoute
}

sealed interface EditorRoute {
    data object New : EditorRoute
    data class Edit(val id: String) : EditorRoute
}

enum class SettingsPage(val title: String) {
    profile("Business profile"), images("Logo and signature"), numbering("Invoice numbering"), defaults("Invoice defaults"),
    taxRates("Tax rates"), unlock("Unlimited invoices"), backup("Backup"), about("About"),
}

class SettingsRouter {
    var selection by mutableStateOf<SettingsPage?>(null)
    /** A backup opened from another app, waiting for the Backup page (`spec/backup.md` §6). */
    var incomingBackup by mutableStateOf<Uri?>(null)

    fun restore(from: Uri) {
        selection = SettingsPage.backup
        incomingBackup = from
    }
}
