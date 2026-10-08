package app.invoicebuilder.android.app

import androidx.compose.runtime.snapshotFlow
import androidx.lifecycle.SavedStateHandle
import app.invoicebuilder.core.domain.models.DocumentType
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Where the user was, kept across process death (≈ iOS state restoration). The router outlives rotation on its own
 * (it lives in the `AppModel`); when the OS kills the process in the background, `SavedStateHandle` brings back the
 * tab and what each section had open. A draft that was open is reopened as a stored document: its edits are already
 * in Room (autosave + flush on `ON_STOP`). Editors and sheets are not restored.
 */
object RouterState {
    private const val TAB = "router.tab"
    private const val DOC_TYPE = "router.documents.docType"
    private const val DOCUMENT = "router.documents.selection"
    private const val CLIENT = "router.clients.selection"
    private const val ITEM = "router.items.selection"
    private const val SETTINGS = "router.settings.selection"

    fun restore(router: AppRouter, state: SavedStateHandle) {
        state.get<String>(TAB)?.let { name -> AppTab.entries.firstOrNull { it.name == name }?.let { router.selectedTab = it } }
        state.get<String>(DOC_TYPE)?.let { router.documents.docType = DocumentType(it) }
        state.get<String>(DOCUMENT)?.let { router.documents.selection = decode(it) }
        state.get<String>(CLIENT)?.let { router.clients.selection = it }
        state.get<String>(ITEM)?.let { router.items.selection = it }
        state.get<String>(SETTINGS)?.let { name -> SettingsPage.entries.firstOrNull { it.name == name }?.let { router.settings.selection = it } }
    }

    /** A new draft stays "new": it opens from Room if it was saved, or as an empty draft with the same id if not. */
    private fun encode(route: DocumentRoute): String = when (route) {
        is DocumentRoute.New -> "new:${route.docType.rawValue}:${route.id}"
        is DocumentRoute.Existing -> "existing:${route.id}"
    }

    private fun decode(text: String): DocumentRoute? {
        val parts = text.split(":")
        return when {
            parts.size == 3 && parts[0] == "new" -> DocumentRoute.New(DocumentType(parts[1]), parts[2])
            parts.size == 2 && parts[0] == "existing" -> DocumentRoute.Existing(parts[1])
            else -> null
        }
    }

    /** Mirrors the router into [state] as it changes (`snapshotFlow` ≈ observing an `@Observable` property). */
    fun save(router: AppRouter, state: SavedStateHandle, scope: CoroutineScope) {
        scope.launch { snapshotFlow { router.selectedTab }.collect { state[TAB] = it.name } }
        scope.launch { snapshotFlow { router.documents.docType }.collect { state[DOC_TYPE] = it.rawValue } }
        scope.launch { snapshotFlow { router.documents.selection }.collect { state[DOCUMENT] = it?.let(::encode) } }
        scope.launch { snapshotFlow { router.clients.selection }.collect { state[CLIENT] = it } }
        scope.launch { snapshotFlow { router.items.selection }.collect { state[ITEM] = it } }
        scope.launch { snapshotFlow { router.settings.selection?.name }.collect { state[SETTINGS] = it } }
    }
}
