package app.invoicebuilder.android.catalog

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.SearchOff
import androidx.compose.material.icons.filled.Unarchive
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.invoicebuilder.android.app.EditorRoute
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.common.ConfirmDialog
import app.invoicebuilder.android.common.DetailColumn
import app.invoicebuilder.android.common.EditorSheet
import app.invoicebuilder.android.common.EmptyState
import app.invoicebuilder.android.common.ErrorAlert
import app.invoicebuilder.android.common.ListDetail
import app.invoicebuilder.android.common.SearchField
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.FormTextField
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.designsystem.IssueText
import app.invoicebuilder.core.designsystem.LabeledValue
import app.invoicebuilder.core.designsystem.PickerField
import app.invoicebuilder.core.designsystem.SegmentedChoice
import app.invoicebuilder.core.designsystem.SwitchRow
import app.invoicebuilder.core.designsystem.Tag
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.ItemKind
import app.invoicebuilder.core.domain.setup.CatalogItemDraft
import app.invoicebuilder.core.domain.setup.CatalogItemField
import app.invoicebuilder.core.domain.setup.CatalogItemRules
import app.invoicebuilder.core.domain.setup.FieldIssue
import app.invoicebuilder.core.domain.setup.SetupSearch
import app.invoicebuilder.core.domain.tax.TaxRate
import kotlinx.coroutines.launch

/** Creating or editing a catalogue item (`spec/setup.md` §10). iOS: `CatalogItemEditorViewModel`. */
class CatalogItemEditorViewModel(private val session: Session, val route: EditorRoute) {
    var draft by mutableStateOf(CatalogItemDraft())
    var original by mutableStateOf<CatalogItem?>(null)
        private set
    var isLoaded by mutableStateOf(route == EditorRoute.New)
        private set
    var attemptedSave by mutableStateOf(false)
        private set
    var isSaving by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
    private var started = false

    fun load() {
        val route = route
        if (started || route !is EditorRoute.Edit || isLoaded) return
        started = true
        session.scope.launch {
            val item = session.container.catalog.fetchItem(route.id)
            if (item != null) {
                original = item
                draft = CatalogItemDraft.of(item, rules.exponent)
            } else {
                errorMessage = "This item no longer exists."
            }
            isLoaded = true
        }
    }

    val rules: CatalogItemRules get() = session.catalogRules
    val isNew get() = route == EditorRoute.New
    val issues: Map<CatalogItemField, FieldIssue> get() = rules.issues(draft)
    fun visibleIssue(field: CatalogItemField): FieldIssue? = if (attemptedSave) issues[field] else null
    val rateChoices: List<TaxRate> get() = rules.rateChoices(draft.rateId)

    /** The saved rate is no longer in force (e.g. GST 12% after 22 September 2025). */
    val rateWarning: String?
        get() = draft.rateId?.takeIf { !rules.isInForce(it) }?.let { "This rate isn't in force today. Choose a current rate." }

    /** "At least 4 digits needed on B2B invoices" (IN), from the business's turnover tier. */
    val productCodeHint: String?
        get() {
            val (b2b, b2c) = rules.requiredProductCodeDigits ?: return null
            return when {
                b2b == 0 && b2c == 0 -> null
                b2c == 0 -> "At least $b2b digits needed on B2B invoices."
                b2b == b2c -> "At least $b2b digits needed on every invoice."
                else -> "At least $b2b digits on B2B invoices, $b2c on others."
            }
        }

    val currencySymbol: String get() = session.container.reference.currencies[rules.currency]?.symbol ?: rules.currency.rawValue

    suspend fun save(): CatalogItem? {
        attemptedSave = true
        if (issues.isNotEmpty() || !isLoaded) return null
        isSaving = true
        try {
            val container = session.container
            val item = original?.let { rules.updating(it, draft) } ?: rules.makeItem(draft, container.ids.make(), container.time.now())
            val saved = container.catalog.save(item)
            session.router.items.didSave(saved.id)
            return saved
        } catch (error: Exception) {
            errorMessage = "The item couldn't be saved."
            return null
        } finally {
            isSaving = false
        }
    }
}

/** The Items tab (wireframe 7): list and detail, with the editor over them. iOS: `CatalogSection`. */
@Composable
fun CatalogSection(session: Session) {
    val router = session.router.items
    var errorMessage by remember { mutableStateOf<String?>(null) }
    fun act(message: String, block: suspend () -> Unit) {
        session.scope.launch { runCatching { block() }.onFailure { errorMessage = message } }
    }
    ListDetail(
        hasSelection = router.selection != null,
        onCloseDetail = { router.selection = null },
        list = {
            CatalogList(session,
                onArchive = { item -> act("The item couldn't be ${if (item.isArchived) "restored" else "archived"}.") {
                    session.container.catalog.setArchived(!item.isArchived, item.id); router.didRemove(item.id)
                } },
                onDelete = { item -> act("The item couldn't be deleted.") { session.container.catalog.delete(item.id); router.didRemove(item.id) } })
        },
        detail = { twoPane -> router.selection?.let { CatalogItemDetail(session, it, showsBack = !twoPane) } },
        empty = { EmptyState("Select an item", Icons.Filled.Inventory2, "Its price and tax details appear here.") },
    )
    router.editor?.let { route -> CatalogItemEditor(session, route, onDone = { router.editor = null }) }
    ErrorAlert(errorMessage, { errorMessage = null })
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun CatalogList(session: Session, onArchive: (CatalogItem) -> Unit, onDelete: (CatalogItem) -> Unit) {
    val router = session.router.items
    val all by remember(session.business.id) { session.container.catalog.observeItems(session.business.id) }.collectAsStateWithLifecycle(null)
    var pendingDelete by remember { mutableStateOf<CatalogItem?>(null) }
    val items = all?.let { SetupSearch.items(it.filter { item -> item.isArchived == router.showArchived }, router.searchText) }
    Scaffold(
        containerColor = Theme.colors.background,
        topBar = {
            TopAppBar({ Text("Items") }, actions = {
                IconButton({ router.editor = EditorRoute.New }, Modifier.testTag("addItem")) { Icon(Icons.Filled.Add, "Add item") }
            }, colors = TopAppBarDefaults.topAppBarColors(containerColor = Theme.colors.background))
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Column(Modifier.padding(horizontal = Theme.Space.l)) {
                SearchField(router.searchText, { router.searchText = it }, "Name or ${session.config.labels.productCodeName}")
                FilterChip(router.showArchived, { router.showArchived = !router.showArchived }, { Text("Show archived") },
                    leadingIcon = { Icon(Icons.Filled.Archive, null) })
            }
            when {
                items == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                items.isEmpty() -> when {
                    router.searchText.isNotBlank() -> EmptyState("No results for “${router.searchText}”", Icons.Filled.SearchOff)
                    router.showArchived -> EmptyState("No archived items", Icons.Filled.Archive, "Archived items are hidden from pickers but kept for old invoices.")
                    else -> EmptyState("No items yet", Icons.Filled.Inventory2, "Save the goods and services you sell, with their prices and tax rates.",
                        "Add item" to { router.editor = EditorRoute.New })
                }
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    items(items, key = { it.id }) { item ->
                        var menu by remember { mutableStateOf(false) }
                        ListItem(
                            headlineContent = { Text(item.name) },
                            supportingContent = item.productCode?.let { { Text("${session.config.labels.productCodeName} $it") } },
                            trailingContent = {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Column(horizontalAlignment = Alignment.End) {
                                        Text(session.money(item.unitPriceMinor, item.currency))
                                        Text(session.rate(item.rateId)?.label ?: item.rateId, style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
                                    }
                                    Box {
                                        IconButton({ menu = true }) { Icon(Icons.Filled.MoreVert, "Actions") }
                                        DropdownMenu(menu, { menu = false }) {
                                            DropdownMenuItem({ Text("Edit") }, { menu = false; router.edit(item.id) }, leadingIcon = { Icon(Icons.Filled.Edit, null) })
                                            DropdownMenuItem({ Text(if (item.isArchived) "Restore" else "Archive") }, { menu = false; onArchive(item) },
                                                leadingIcon = { Icon(if (item.isArchived) Icons.Filled.Unarchive else Icons.Filled.Archive, null) })
                                            DropdownMenuItem({ Text("Delete", color = Theme.colors.danger) }, { menu = false; pendingDelete = item },
                                                leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Theme.colors.danger) })
                                        }
                                    }
                                }
                            },
                            colors = ListItemDefaults.colors(containerColor = if (router.selection == item.id) Theme.colors.brand.copy(alpha = 0.12f) else Theme.colors.background),
                            modifier = Modifier.combinedClickable(onClick = { router.selection = item.id }, onLongClick = { menu = true }).testTag("item-${item.name}"),
                        )
                        HorizontalDivider(color = Theme.colors.border.copy(alpha = 0.5f))
                    }
                }
            }
        }
    }
    pendingDelete?.let { item ->
        ConfirmDialog("Delete ${item.name}?", "Invoices that already include this item keep their lines.", "Delete", { onDelete(item) }, { pendingDelete = null })
    }
}

/** An item's details; Edit opens the editor. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CatalogItemDetail(session: Session, itemID: String, showsBack: Boolean) {
    val item by remember(itemID) { session.container.catalog.observeItem(itemID) }.collectAsStateWithLifecycle(null)
    val labels = session.config.labels
    Scaffold(
        containerColor = Theme.colors.background,
        topBar = {
            TopAppBar({ Text(item?.name ?: "") },
                navigationIcon = { if (showsBack) IconButton({ session.router.items.selection = null }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                actions = { if (item != null) TextButton({ session.router.items.edit(itemID) }) { Text("Edit") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Theme.colors.background))
        },
    ) { padding ->
        val current = item ?: return@Scaffold Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        DetailColumn(Modifier.padding(padding)) {
            Column(Modifier.padding(vertical = Theme.Space.s), verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                Text(current.name, style = MaterialTheme.typography.titleLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                    Tag(if (current.kind == ItemKind.goods) "Goods" else "Service")
                    if (current.isArchived) Tag("Archived", Theme.colors.textSecondary)
                }
                current.description?.let { Text(it, color = Theme.colors.textSecondary) }
            }
            FormSection("Price") {
                LabeledValue("Price", session.money(current.unitPriceMinor, current.currency))
                LabeledValue("Unit", "${session.unitLabel(current.unit)} (${current.unit})")
                if (session.chargesTax) LabeledValue("Price includes ${labels.taxName}", if (current.priceIncludesTax) "Yes" else "No")
            }
            FormSection(labels.taxName) {
                LabeledValue("Rate", session.rate(current.rateId)?.label ?: current.rateId)
                current.productCode?.let { LabeledValue(labels.productCodeName, it) }
            }
        }
    }
}

/** New / edit item (wireframe 7, `spec/setup.md` §10). iOS: `CatalogItemEditorView`. */
@Composable
fun CatalogItemEditor(session: Session, route: EditorRoute, onDone: () -> Unit) {
    val key = "itemEditor-$route"
    val model = session.retained(key) { CatalogItemEditorViewModel(session, route) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(model) { model.load() }
    fun close() { session.release(key); onDone() }
    EditorSheet(if (model.isNew) "New item" else "Edit item", onCancel = ::close,
        onSave = { scope.launch { if (model.save() != null) close() } }, saveEnabled = model.isLoaded, isBusy = model.isSaving, saveTag = "itemSave") {
        if (!model.isLoaded) CircularProgressIndicator() else CatalogItemForm(model, session)
    }
    ErrorAlert(model.errorMessage, { model.errorMessage = null })
}

@Composable
private fun CatalogItemForm(model: CatalogItemEditorViewModel, session: Session) {
    val labels = session.config.labels
    val draft = model.draft
    fun message(field: CatalogItemField, name: String) = model.visibleIssue(field)?.let { IssueMessages.text(it, name) }
    fun update(change: (CatalogItemDraft) -> CatalogItemDraft) { model.draft = change(model.draft) }

    if (model.attemptedSave && model.issues.isNotEmpty()) IssueText("Check the highlighted fields.")
    FormSection {
        FormTextField("Name", draft.name, { v -> update { it.copy(name = v) } }, prompt = "As it appears on invoices",
            issue = message(CatalogItemField.Name, "name"), tag = "itemName")
        FormTextField("Description (optional)", draft.description, { v -> update { it.copy(description = v) } }, multiline = true)
        SegmentedChoice(listOf(ItemKind.service to "Service", ItemKind.goods to "Goods"), draft.kind, { v -> update { it.settingKind(v) } })
    }
    FormSection("Price") {
        FormTextField("Price per unit (${model.currencySymbol})", draft.priceText, { v -> update { it.copy(priceText = v) } }, prompt = "0.00",
            issue = message(CatalogItemField.Price, "price"), keyboard = KeyboardType.Decimal, tag = "itemPrice")
        PickerField("Unit", draft.unit, session.container.reference.units.map { it.id to "${it.label} (${it.id})" },
            { v -> if (v != null) update { it.copy(unit = v) } }, searchable = true)
        if (model.rules.showsInclusivePrice) {
            SwitchRow("Price includes ${labels.taxName}", draft.priceIncludesTax, { v -> update { it.copy(priceIncludesTax = v) } })
        }
    }
    FormSection(labels.taxName,
        if (!session.chargesTax) "You don't charge ${labels.taxName} now, so this rate isn't applied. It's kept in case you register later." else null) {
        PickerField("Rate", draft.rateId, model.rateChoices.map { it.id to it.label }, { v -> update { it.copy(rateId = v) } },
            none = if (draft.rateId == null) "Choose" else null, issue = message(CatalogItemField.Rate, "rate"), tag = "itemRate")
        model.rateWarning?.let {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Warning, null, tint = Theme.colors.warning)
                Text("  $it", style = MaterialTheme.typography.bodySmall, color = Theme.colors.warning)
            }
        }
    }
    FormSection(footer = model.productCodeHint) {
        FormTextField("${labels.productCodeName} (optional)", draft.productCode, { v -> update { it.copy(productCode = v) } },
            prompt = if (session.config.family == "IN") "e.g. 998314" else null, issue = message(CatalogItemField.ProductCode, labels.productCodeName),
            keyboard = if (session.config.family == "IN") KeyboardType.Number else KeyboardType.Text,
            capitalization = KeyboardCapitalization.Characters, autocorrect = false)
    }
}
