package app.invoicebuilder.android.clients

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.People
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.invoicebuilder.android.app.EditorRoute
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.common.ConfirmDialog
import app.invoicebuilder.android.common.DetailColumn
import app.invoicebuilder.android.common.EditorSheet
import app.invoicebuilder.android.common.EmptyState
import app.invoicebuilder.android.common.ErrorAlert
import app.invoicebuilder.android.common.ListDetail
import app.invoicebuilder.android.common.RegionPicker
import app.invoicebuilder.android.common.SearchField
import app.invoicebuilder.android.common.TaxIDFeedback
import app.invoicebuilder.android.documents.StatusTag
import app.invoicebuilder.android.documents.displayText
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.FormTextField
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.designsystem.IssueText
import app.invoicebuilder.core.designsystem.LabeledValue
import app.invoicebuilder.core.designsystem.PickerField
import app.invoicebuilder.core.designsystem.SuccessText
import app.invoicebuilder.core.designsystem.SwitchRow
import app.invoicebuilder.core.designsystem.Tag
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.documents.outstandingByCurrency
import app.invoicebuilder.core.domain.models.Address
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.reference.Country
import app.invoicebuilder.core.domain.setup.AddressDraft
import app.invoicebuilder.core.domain.setup.ClientField
import app.invoicebuilder.core.domain.setup.SetupSearch
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** The Clients tab: list and detail side by side on wide windows, pushed on phones (wireframe 6). iOS: `ClientsSection`. */
@Composable
fun ClientsSection(session: Session) {
    val router = session.router.clients
    val actions = remember(session) { ClientListActions(session) }
    ListDetail(
        hasSelection = router.selection != null,
        onCloseDetail = { router.selection = null },
        list = { ClientList(session, actions) },
        detail = { twoPane -> router.selection?.let { ClientDetail(session, it, showsBack = !twoPane) } },
        empty = { EmptyState("Select a client", Icons.Filled.People, "Their details appear here.") },
    )
    router.editor?.let { route -> ClientEditor(session, route, onDone = { router.editor = null }) }
    ErrorAlert(actions.errorMessage, { actions.errorMessage = null })
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ClientList(session: Session, actions: ClientListActions) {
    val router = session.router.clients
    val all by remember(session.business.id) { session.container.clients.observeClients(session.business.id) }.collectAsStateWithLifecycle(null)
    var pendingDelete by remember { mutableStateOf<Client?>(null) }
    val clients = all?.let { SetupSearch.clients(it.filter { c -> c.isArchived == router.showArchived }, router.searchText) }
    Scaffold(
        containerColor = Theme.colors.background,
        topBar = {
            TopAppBar({ Text("Clients") }, actions = {
                IconButton({ router.editor = EditorRoute.New }, Modifier.testTag("addClient")) { Icon(Icons.Filled.Add, "Add client") }
            }, colors = TopAppBarDefaults.topAppBarColors(containerColor = Theme.colors.background))
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Column(Modifier.padding(horizontal = Theme.Space.l)) {
                SearchField(router.searchText, { router.searchText = it }, "Name, ${session.config.labels.taxIdName}, email or phone")
                FilterChip(router.showArchived, { router.showArchived = !router.showArchived }, { Text("Show archived") },
                    leadingIcon = { Icon(Icons.Filled.Archive, null) })
            }
            when {
                clients == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                clients.isEmpty() -> when {
                    router.searchText.isNotBlank() -> EmptyState("No results for “${router.searchText}”", Icons.Filled.SearchOff)
                    router.showArchived -> EmptyState("No archived clients", Icons.Filled.Archive,
                        "Archived clients are hidden from pickers but kept for old invoices.")
                    else -> EmptyState("No clients yet", Icons.Filled.People, "Add the people and businesses you invoice.",
                        "Add client" to { router.editor = EditorRoute.New })
                }
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    items(clients, key = { it.id }) { client ->
                        ClientRow(client, session, router.selection == client.id, onOpen = { router.selection = client.id },
                            onEdit = { router.edit(client.id) }, onArchive = { actions.setArchived(!client.isArchived, client) },
                            onDelete = { pendingDelete = client })
                        HorizontalDivider(color = Theme.colors.border.copy(alpha = 0.5f))
                    }
                }
            }
        }
    }
    pendingDelete?.let { client ->
        ConfirmDialog("Delete ${client.name}?", "Invoices already sent to this client keep their details.", "Delete",
            { actions.delete(client) }, { pendingDelete = null })
    }
}

/** A row; long-press or ⋮ opens the actions (≈ swipe actions and the context menu). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ClientRow(client: Client, session: Session, selected: Boolean, onOpen: () -> Unit, onEdit: () -> Unit, onArchive: () -> Unit, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val detail = when {
        client.countryCode != session.business.countryCode -> listOfNotNull(session.countryName(client.countryCode), client.taxId).joinToString(" · ")
        client.taxId != null -> "${session.config.labels.taxIdName} ${client.taxId}"
        else -> session.regionName(client.regionCode) ?: client.billingAddress?.city
    }
    ListItem(
        headlineContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                Text(client.name)
                if (client.isBusiness) Tag("B2B")
            }
        },
        supportingContent = detail?.let { { Text(it, maxLines = 1, overflow = TextOverflow.Ellipsis) } },
        trailingContent = {
            Box {
                IconButton({ menu = true }) { Icon(Icons.Filled.MoreVert, "Actions") }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem({ Text("Edit") }, { menu = false; onEdit() }, leadingIcon = { Icon(Icons.Filled.Edit, null) })
                    DropdownMenuItem({ Text(if (client.isArchived) "Restore" else "Archive") }, { menu = false; onArchive() },
                        leadingIcon = { Icon(if (client.isArchived) Icons.Filled.Unarchive else Icons.Filled.Archive, null) })
                    DropdownMenuItem({ Text("Delete", color = Theme.colors.danger) }, { menu = false; onDelete() },
                        leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Theme.colors.danger) })
                }
            }
        },
        colors = ListItemDefaults.colors(containerColor = if (selected) Theme.colors.brand.copy(alpha = 0.12f) else Theme.colors.background),
        modifier = Modifier.combinedClickable(onClick = onOpen, onLongClick = { menu = true }).testTag("client-${client.name}"),
    )
}

/** A client's details (read-only); Edit opens the editor. iOS: `ClientDetailView`. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ClientDetail(session: Session, clientID: String, showsBack: Boolean) {
    val client by remember(clientID) { session.container.clients.observeClient(clientID) }.collectAsStateWithLifecycle(null)
    val documents by remember(clientID) {
        session.container.documents.observeDocuments(session.business.id).map { all -> all.filter { it.clientId == clientID } }
    }.collectAsStateWithLifecycle(emptyList())
    Scaffold(
        containerColor = Theme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(client?.name ?: "") },
                navigationIcon = { if (showsBack) IconButton({ session.router.clients.selection = null }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                actions = { if (client != null) TextButton({ session.router.clients.edit(clientID) }) { Text("Edit") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Theme.colors.background),
            )
        },
    ) { padding ->
        val current = client ?: return@Scaffold Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        DetailColumn(Modifier.padding(padding)) {
            Column(Modifier.padding(vertical = Theme.Space.s), verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                Text(current.name, style = MaterialTheme.typography.titleLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                    Tag(if (current.isBusiness) "Business (B2B)" else "Consumer (B2C)")
                    if (current.isArchived) Tag("Archived", Theme.colors.textSecondary)
                }
            }
            FormSection("Tax") {
                current.taxId?.let { LabeledValue(if (current.countryCode == session.business.countryCode) session.config.labels.taxIdName else "Tax ID", it) }
                session.regionName(current.regionCode)?.let { LabeledValue(session.config.labels.regionName ?: "State", it) }
                LabeledValue("Country", session.countryName(current.countryCode))
                LabeledValue("Currency", (current.defaultCurrency ?: session.business.homeCurrency).rawValue)
            }
            if (current.contactName != null || current.email != null || current.phone != null) {
                FormSection("Contact") {
                    current.contactName?.let { LabeledValue("Contact", it) }
                    current.email?.let { LabeledValue("Email", it) }
                    current.phone?.let { LabeledValue("Phone", it) }
                }
            }
            current.billingAddress?.let { FormSection("Billing address") { AddressText(it, session) } }
            current.shippingAddress?.let { FormSection("Shipping address") { AddressText(it, session) } }
            current.notes?.let { FormSection("Notes") { Text(it) } }
            val outstanding = documents.outstandingByCurrency(session.today)
            if (outstanding.isNotEmpty()) {
                FormSection("Outstanding") {
                    for ((currency, minor) in outstanding) LabeledValue(currency.rawValue, session.money(minor, currency))
                }
            }
            FormSection("Documents") {
                if (documents.isEmpty()) {
                    Text("Invoices and quotes for this client will appear here.", color = Theme.colors.textSecondary)
                } else {
                    for (summary in documents) {
                        Row(Modifier.fillMaxWidth().clickable { session.openDocument(summary.id, summary.docType) }
                            .padding(vertical = Theme.Space.xs), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(summary.number ?: "Draft ${app.invoicebuilder.android.documents.DocumentText.noun(summary.docType)}",
                                    color = if (summary.number == null) Theme.colors.textSecondary else Theme.colors.textPrimary)
                                Text(summary.issueDate.displayText, style = MaterialTheme.typography.labelSmall, color = Theme.colors.textTertiary)
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text(session.money(summary.totalMinor, summary.currency))
                                StatusTag(summary.status(session.today))
                            }
                        }
                    }
                }
            }
        }
    }
}

/** A multi-line postal address. */
@Composable
fun AddressText(address: Address, session: Session) {
    Column {
        Text(address.line1)
        address.line2?.let { Text(it) }
        listOfNotNull(address.city, address.postalCode).joinToString(" ").takeIf { it.isNotEmpty() }?.let { Text(it) }
        session.regionName(address.regionCode)?.let { Text(it) }
        if (address.countryCode != session.business.countryCode) Text(session.countryName(address.countryCode))
    }
}

/** New / edit client (`spec/setup.md` §5). [onSaved]: quick add from the document builder. iOS: `ClientEditorView`. */
@Composable
fun ClientEditor(session: Session, route: EditorRoute, onDone: () -> Unit, onSaved: ((Client) -> Unit)? = null) {
    val key = "clientEditor-$route"
    val model = session.retained(key) { ClientEditorViewModel(session, route) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(model) { model.load() }
    fun close() { session.release(key); onDone() }
    EditorSheet(
        if (model.isNew) "New client" else "Edit client", onCancel = ::close,
        onSave = { scope.launch { model.save()?.let { onSaved?.invoke(it); close() } } },
        saveEnabled = model.isLoaded, isBusy = model.isSaving, saveTag = "clientSave",
    ) {
        if (!model.isLoaded) CircularProgressIndicator() else ClientForm(model, session)
    }
    ErrorAlert(model.errorMessage, { model.errorMessage = null })
}

@Composable
private fun ClientForm(model: ClientEditorViewModel, session: Session) {
    val rules = model.rules
    val draft = model.draft
    val taxIDName = session.config.labels.taxIdName
    fun message(field: ClientField, name: String) = model.visibleIssue(field)?.let { IssueMessages.text(it, name, taxIDName) }
    fun update(change: (app.invoicebuilder.core.domain.setup.ClientDraft) -> app.invoicebuilder.core.domain.setup.ClientDraft) { model.draft = change(model.draft) }

    if (model.attemptedSave && model.issues.isNotEmpty()) IssueText("Check the highlighted fields.")
    FormSection(footer = "Business clients can have a $taxIDName printed on their invoices.") {
        FormTextField("Name", draft.name, { v -> update { it.copy(name = v) } }, prompt = "Client or company name",
            issue = message(ClientField.Name, "name"), capitalization = KeyboardCapitalization.Words, tag = "clientName")
        FormTextField("Contact person (optional)", draft.contactName, { v -> update { it.copy(contactName = v) } }, capitalization = KeyboardCapitalization.Words)
        SwitchRow("Business client (B2B)", draft.isBusiness, { v -> update { it.copy(isBusiness = v) } }, tag = "clientIsBusiness")
    }
    FormSection("Location and tax") {
        CountryPicker("Country", draft.countryCode, { v -> update { it.copy(countryCode = v) } }, session.container.reference.countriesByName)
        if (rules.showsRegion(draft)) {
            RegionPicker(session.config.labels.regionName ?: "State", draft.regionCode, { v -> update { it.copy(regionCode = v) } },
                session.config.activeRegionsByName, rules.regionFromTaxID(draft), "From their $taxIDName")
        }
        if (rules.showsTaxID(draft)) {
            FormTextField(
                if (rules.validatesTaxID(draft)) "$taxIDName (optional)" else "Tax ID (optional)", draft.taxId, { v -> update { it.copy(taxId = v) } },
                prompt = if (rules.validatesTaxID(draft)) "As on their registration" else "Their tax or VAT number",
                issue = message(ClientField.TaxId, taxIDName), capitalization = KeyboardCapitalization.Characters, autocorrect = false, tag = "clientTaxId",
            )
            when (val feedback = model.taxIDFeedback) {
                is TaxIDFeedback.Valid -> SuccessText(feedback.region?.let { "Valid · $it" } ?: "Valid")
                is TaxIDFeedback.Invalid -> if (model.visibleIssue(ClientField.TaxId) == null) IssueText(feedback.message)
                null -> {}
            }
            model.duplicate?.let { other ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Warning, null, tint = Theme.colors.warning)
                    Text("  ${other.name} already has this $taxIDName.", style = MaterialTheme.typography.bodySmall, color = Theme.colors.warning)
                }
            }
        }
    }
    FormSection("Contact (optional)") {
        FormTextField("Email", draft.email, { v -> update { it.copy(email = v) } }, prompt = "accounts@example.com",
            issue = message(ClientField.Email, "email"), keyboard = KeyboardType.Email, capitalization = KeyboardCapitalization.None, autocorrect = false)
        FormTextField("Phone", draft.phone, { v -> update { it.copy(phone = v) } }, keyboard = KeyboardType.Phone)
    }
    FormSection("Billing address (optional)") {
        AddressFields(draft.billing, { v -> update { it.copy(billing = v) } }, draft.countryCode,
            message(ClientField.BillingLine1, "address"), message(ClientField.BillingPostalCode, "postcode"))
    }
    FormSection("Shipping address") {
        SwitchRow("Ship to a different address", draft.hasShippingAddress, { v -> update { it.copy(hasShippingAddress = v) } })
        if (draft.hasShippingAddress) {
            AddressFields(draft.shipping, { v -> update { it.copy(shipping = v) } }, draft.countryCode,
                message(ClientField.ShippingLine1, "address"), message(ClientField.ShippingPostalCode, "postcode"))
        }
    }
    FormSection("More") {
        val currencies = session.container.reference.currencies.all.filter { it.code != session.business.homeCurrency }.sortedBy { it.code }
        PickerField("Invoice currency", draft.defaultCurrency, currencies.map { it.code to "${it.code.rawValue} · ${it.name}" },
            { v -> update { it.copy(defaultCurrency = v) } }, none = "${session.business.homeCurrency.rawValue} (your currency)", searchable = true)
        FormTextField("Notes (optional)", draft.notes, { v -> update { it.copy(notes = v) } }, multiline = true)
    }
}

/** Address lines, city and postcode for a draft address. */
@Composable
fun AddressFields(address: AddressDraft, onChange: (AddressDraft) -> Unit, countryCode: String, line1Issue: String? = null, postalIssue: String? = null) {
    FormTextField("Address line 1", address.line1, { onChange(address.copy(line1 = it)) }, prompt = "Building, street", issue = line1Issue,
        capitalization = KeyboardCapitalization.Words)
    FormTextField("Address line 2", address.line2, { onChange(address.copy(line2 = it)) }, capitalization = KeyboardCapitalization.Words)
    FormTextField("City", address.city, { onChange(address.copy(city = it)) }, capitalization = KeyboardCapitalization.Words)
    FormTextField(if (countryCode == "IN") "PIN code" else "Postcode", address.postalCode, { onChange(address.copy(postalCode = it)) },
        issue = postalIssue, keyboard = if (countryCode == "IN") KeyboardType.Number else KeyboardType.Text,
        capitalization = KeyboardCapitalization.Characters, autocorrect = false)
}

/** A country field that opens a searchable list. */
@Composable
fun CountryPicker(title: String, selection: String, onSelect: (String) -> Unit, countries: List<Country>) {
    PickerField(title, selection, countries.map { it.code to it.name }, { it?.let(onSelect) }, searchable = true)
}
