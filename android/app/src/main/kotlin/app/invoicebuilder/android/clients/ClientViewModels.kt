package app.invoicebuilder.android.clients

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.invoicebuilder.android.app.EditorRoute
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.common.TaxIDFeedback
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.setup.ClientDraft
import app.invoicebuilder.core.domain.setup.ClientField
import app.invoicebuilder.core.domain.setup.ClientRules
import app.invoicebuilder.core.domain.setup.FieldIssue
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/** Archive, restore and delete from the client list. iOS: `ClientListViewModel` (the list itself is a Flow). */
class ClientListActions(private val session: Session) {
    var errorMessage by mutableStateOf<String?>(null)

    fun setArchived(archived: Boolean, client: Client) {
        session.scope.launch {
            try {
                session.container.clients.setArchived(archived, client.id)
                session.router.clients.didRemove(client.id)
            } catch (error: Exception) {
                errorMessage = "The client couldn't be ${if (archived) "archived" else "restored"}."
            }
        }
    }

    fun delete(client: Client) {
        session.scope.launch {
            try {
                session.container.clients.delete(client.id)
                session.router.clients.didRemove(client.id)
            } catch (error: Exception) {
                errorMessage = "The client couldn't be deleted."
            }
        }
    }
}

/** Creating or editing a client (`spec/setup.md` §5). iOS: `ClientEditorViewModel`. */
class ClientEditorViewModel(private val session: Session, val route: EditorRoute) {
    var draft by mutableStateOf(ClientDraft(countryCode = session.business.countryCode))
    /** The stored client being edited; null for a new one. */
    var original by mutableStateOf<Client?>(null)
        private set
    var isLoaded by mutableStateOf(route == EditorRoute.New)
        private set
    /** Save was pressed: every problem is shown, not only live tax ID feedback. */
    var attemptedSave by mutableStateOf(false)
        private set
    var isSaving by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
    private var otherClients by mutableStateOf(emptyList<Client>())
    private var started = false

    /** Reads the client being edited and the others (for the duplicate tax ID warning). Runs once per editor. */
    fun load() {
        if (started) return
        started = true
        session.scope.launch {
            otherClients = runCatching { session.container.clients.observeClients(session.business.id).first() }.getOrDefault(emptyList())
            val route = route
            if (route is EditorRoute.Edit && !isLoaded) {
                val client = session.container.clients.fetchClient(route.id)
                if (client != null) {
                    original = client
                    draft = ClientDraft.of(client)
                } else {
                    errorMessage = "This client no longer exists."
                }
                isLoaded = true
            }
        }
    }

    val rules: ClientRules get() = session.clientRules
    val isNew: Boolean get() = route == EditorRoute.New
    val issues: Map<ClientField, FieldIssue> get() = rules.issues(draft)

    fun visibleIssue(field: ClientField): FieldIssue? = if (attemptedSave) issues[field] else null

    val taxIDFeedback: TaxIDFeedback?
        get() {
            val validation = rules.taxIDValidation(draft) ?: return null
            if (validation.valid) return TaxIDFeedback.Valid(validation.region?.let { session.config.region(it)?.name })
            if (!attemptedSave && validation.normalized.length < 15) return null
            val error = validation.error ?: return null
            val name = session.config.labels.taxIdName
            return TaxIDFeedback.Invalid(IssueMessages.text(FieldIssue.InvalidTaxID(error), name, name))
        }

    val duplicate: Client? get() = rules.duplicate(draft, original?.id, otherClients)

    /** Saves and returns the stored client; null when a problem blocks saving. */
    suspend fun save(): Client? {
        attemptedSave = true
        if (issues.isNotEmpty() || !isLoaded) return null
        isSaving = true
        try {
            val container = session.container
            val client = original?.let { rules.updating(it, draft) }
                ?: rules.makeClient(draft, container.ids.make(), session.business.id, container.time.now())
            val saved = container.clients.save(client)
            session.router.clients.didSave(saved.id)
            return saved
        } catch (error: Exception) {
            errorMessage = "The client couldn't be saved."
            return null
        } finally {
            isSaving = false
        }
    }
}
