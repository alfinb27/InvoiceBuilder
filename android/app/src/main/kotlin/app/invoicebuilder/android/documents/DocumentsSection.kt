package app.invoicebuilder.android.documents

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.SearchOff
import androidx.compose.material.icons.filled.Share
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
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.invoicebuilder.android.app.DocumentAction
import app.invoicebuilder.android.app.DocumentDateFilter
import app.invoicebuilder.android.app.DocumentRoute
import app.invoicebuilder.android.app.InvoiceStatusFilter
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.common.ConfirmDialog
import app.invoicebuilder.android.common.EmptyState
import app.invoicebuilder.android.common.ErrorAlert
import app.invoicebuilder.android.common.ListDetail
import app.invoicebuilder.android.common.SearchField
import app.invoicebuilder.core.designsystem.SegmentedChoice
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.documents.DocumentStatus
import app.invoicebuilder.core.domain.documents.DocumentSummary
import app.invoicebuilder.core.domain.models.DocumentType
import kotlinx.coroutines.launch

/** The Invoices tab: invoices or quotes on the left, the builder or issued document on the right. iOS: `DocumentsSection`. */
@Composable
fun DocumentsSection(session: Session) {
    val router = session.router.documents
    ListDetail(
        hasSelection = router.selection != null,
        onCloseDetail = { router.selection = null },
        list = { DocumentList(session) },
        detail = { twoPane -> router.selection?.let { DocumentScreen(session, it, showsBack = !twoPane) } },
        empty = { EmptyState("Select an invoice", Icons.Filled.Description, "Or create one with New invoice.") },
    )
}

/** The detail pane: the builder for drafts, the read-only view once issued. iOS: `DocumentScreen`. */
@Composable
fun DocumentScreen(session: Session, route: DocumentRoute, showsBack: Boolean) {
    val key = "document-${route.id}"
    val model = session.retained(key) { DocumentViewModel(session, route) }
    val router = session.router.documents
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(model) { model.load() }
    // A success tap when a draft becomes an issued document.
    var wasDraft by remember(model) { mutableStateOf(model.document.isDraft) }
    LaunchedEffect(model.document.lifecycle) {
        if (wasDraft && model.document.lifecycle == DocumentLifecycle.issued) haptics.performHapticFeedback(HapticFeedbackType.Confirm)
        wasDraft = model.document.isDraft
    }
    LaunchedEffect(model.paymentsRecorded) { if (model.paymentsRecorded > 0) haptics.performHapticFeedback(HapticFeedbackType.Confirm) }
    // Going to the background saves (≈ `scenePhase != .active`); leaving the document closes it for good.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(model, lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) session.scope.launch { model.flush() } }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            session.scope.launch { model.close() }
            // Disposed by rotation or folding, the document is still selected: keep its model for the new activity.
            if (router.selection?.id != route.id) session.release(key)
        }
    }
    val back = { router.selection = null }
    when {
        !model.isLoaded -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        model.notFound -> EmptyState("This document no longer exists", Icons.Filled.Description)
        model.isDraft -> DocumentBuilder(model, session, showsBack, back)
        else -> IssuedDocument(model, session, showsBack, back)
    }
    // Review & send (`documents.md` §6.1); its Send button issues and opens the channel (`DocumentViewModel.send`).
    if (model.confirmingIssue) ReviewSendSheet(model, session)
    model.preview?.let { preview -> DocumentPreviewScreen(preview) { model.preview = null } }
    ErrorAlert(model.errorMessage, { model.errorMessage = null })
}

/** Drafts and issued documents of one type, matching the search, date range and (invoices) status segment. */
fun visibleDocuments(
    documents: List<DocumentSummary>, docType: DocumentType, query: String, statusFilter: InvoiceStatusFilter,
    dateFilter: DocumentDateFilter, today: java.time.LocalDate,
): Pair<List<DocumentSummary>, List<DocumentSummary>> {
    val needle = query.trim()
    val from = dateFilter.from(today)
    val rows = documents.filter { summary ->
        summary.docType == docType &&
            (needle.isEmpty() || summary.buyerName?.contains(needle, true) == true || summary.number?.contains(needle, true) == true) &&
            (from == null || !summary.issueDate.isBefore(from))
    }
    val issued = rows.filter { it.lifecycle != DocumentLifecycle.draft }
    val filtered = if (docType == DocumentType.invoice) issued.filter { statusFilter.matches(it.status(today)) } else issued
    return rows.filter { it.lifecycle == DocumentLifecycle.draft } to filtered
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DocumentList(session: Session) {
    val router = session.router.documents
    val all by remember(session.business.id) { session.container.documents.observeDocuments(session.business.id) }.collectAsStateWithLifecycle(null)
    var pendingDelete by remember { mutableStateOf<DocumentSummary?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var dateMenu by remember { mutableStateOf(false) }
    val noun = DocumentText.noun(router.docType)
    Scaffold(
        containerColor = Theme.colors.background,
        topBar = {
            TopAppBar({ Text(if (router.docType == DocumentType.quote) "Quotes" else "Invoices") }, actions = {
                Box {
                    IconButton({ dateMenu = true }, Modifier.testTag("documentDateFilter")) { Icon(Icons.Filled.CalendarMonth, "Date range") }
                    DropdownMenu(dateMenu, { dateMenu = false }) {
                        for (filter in DocumentDateFilter.entries) {
                            DropdownMenuItem({ Text(filter.label, fontWeight = if (filter == router.dateFilter) FontWeight.SemiBold else null) },
                                { router.dateFilter = filter; dateMenu = false })
                        }
                    }
                }
                IconButton({ session.startNewDocument(router.docType) }, Modifier.testTag("newDocument")) { Icon(Icons.Filled.Add, "New $noun") }
            }, colors = TopAppBarDefaults.topAppBarColors(containerColor = Theme.colors.background))
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Column(Modifier.padding(horizontal = Theme.Space.l), verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                SegmentedChoice(listOf(DocumentType.invoice to "Invoices", DocumentType.quote to "Quotes"), router.docType, { router.docType = it }, tagPrefix = "documentType")
                if (router.docType == DocumentType.invoice) {
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                        for (filter in InvoiceStatusFilter.entries) {
                            FilterChip(router.statusFilter == filter, { router.statusFilter = filter }, { Text(filter.label) },
                                modifier = Modifier.testTag("status-${filter.name}"))
                        }
                    }
                }
                SearchField(router.searchText, { router.searchText = it }, "Client or number")
            }
            val documents = all
            if (documents == null) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                return@Column
            }
            val (drafts, issued) = visibleDocuments(documents, router.docType, router.searchText, router.statusFilter, router.dateFilter, session.today)
            if (drafts.isEmpty() && issued.isEmpty()) {
                when {
                    router.searchText.isNotBlank() -> EmptyState("No results for “${router.searchText}”", Icons.Filled.SearchOff)
                    (router.statusFilter != InvoiceStatusFilter.all || router.dateFilter != DocumentDateFilter.allTime) &&
                        documents.any { it.docType == router.docType } ->
                        EmptyState("No matching ${noun}s", Icons.Filled.FilterList, "Try a different status or date range.")
                    else -> EmptyState("No ${noun}s yet", Icons.Filled.Description,
                        if (router.docType == DocumentType.quote) "Quotes you send appear here. Convert one to an invoice when it's accepted."
                        else "Create an invoice: pick a client, add items and issue it.",
                        "New $noun" to { session.startNewDocument(router.docType) })
                }
                return@Column
            }
            LazyColumn(Modifier.fillMaxSize()) {
                if (drafts.isNotEmpty()) {
                    item { SectionHeader("Drafts") }
                    items(drafts, key = { it.id }) { DocumentRow(it, session, onDelete = { pendingDelete = it }, onError = { errorMessage = it }) }
                }
                if (issued.isNotEmpty()) {
                    item { SectionHeader(if (router.docType == DocumentType.quote) "Sent quotes" else "Sent invoices") }
                    items(issued, key = { it.id }) { DocumentRow(it, session, onDelete = { pendingDelete = it }, onError = { errorMessage = it }) }
                }
            }
        }
    }
    pendingDelete?.let { summary ->
        ConfirmDialog("Delete this draft?", null, "Delete draft", {
            session.scope.launch {
                runCatching { session.container.documentService.deleteDraft(summary.id); router.didRemove(summary.id) }
                    .onFailure { errorMessage = "The draft couldn't be deleted." }
            }
        }, { pendingDelete = null })
    }
    ErrorAlert(errorMessage, { errorMessage = null })
}

@Composable
private fun SectionHeader(title: String) {
    Text(title.uppercase(), Modifier.padding(start = Theme.Space.l, top = Theme.Space.m, bottom = Theme.Space.xs),
        style = MaterialTheme.typography.labelMedium, color = Theme.colors.textSecondary)
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DocumentRow(summary: DocumentSummary, session: Session, onDelete: () -> Unit, onError: (String) -> Unit) {
    val router = session.router.documents
    var menu by remember { mutableStateOf(false) }
    val status = summary.status(session.today)
    ListItem(
        headlineContent = {
            Text(summary.number ?: "Draft", fontWeight = FontWeight.SemiBold,
                color = if (summary.number == null) Theme.colors.textSecondary else Theme.colors.textPrimary)
        },
        supportingContent = {
            Column {
                Text(summary.buyerName ?: "No client", color = Theme.colors.textSecondary)
                Text(summary.issueDate.displayText, style = MaterialTheme.typography.labelSmall, color = Theme.colors.textTertiary)
            }
        },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(horizontalAlignment = Alignment.End) {
                    Text(session.money(summary.totalMinor, summary.currency))
                    StatusTag(status)
                }
                Box {
                    IconButton({ menu = true }) { Icon(Icons.Filled.MoreVert, "Actions") }
                    DropdownMenu(menu, { menu = false }) {
                        DropdownMenuItem({ Text("Duplicate") }, {
                            menu = false
                            session.scope.launch {
                                runCatching { router.open(session.container.documentService.duplicate(summary.id).id) }
                                    .onFailure { onError("The ${DocumentText.noun(summary.docType)} couldn't be duplicated.") }
                            }
                        }, leadingIcon = { Icon(Icons.Filled.ContentCopy, null) })
                        if (summary.lifecycle != DocumentLifecycle.draft) {
                            DropdownMenuItem({ Text("Share") }, { menu = false; router.open(summary.id, DocumentAction.share) }, leadingIcon = { Icon(Icons.Filled.Share, null) })
                        }
                        if (summary.docType == DocumentType.invoice && summary.lifecycle == DocumentLifecycle.issued && status != DocumentStatus.paid) {
                            DropdownMenuItem({ Text("Record payment") }, { menu = false; router.open(summary.id, DocumentAction.recordPayment) },
                                leadingIcon = { Icon(Icons.Filled.Payments, null) })
                        }
                        if (summary.lifecycle == DocumentLifecycle.issued) {
                            DropdownMenuItem({ Text("Void", color = Theme.colors.danger) }, { menu = false; router.open(summary.id, DocumentAction.void) },
                                leadingIcon = { Icon(Icons.Filled.Block, null, tint = Theme.colors.danger) })
                        }
                        if (summary.lifecycle == DocumentLifecycle.draft) {
                            DropdownMenuItem({ Text("Delete", color = Theme.colors.danger) }, { menu = false; onDelete() },
                                leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Theme.colors.danger) })
                        }
                    }
                }
            }
        },
        colors = ListItemDefaults.colors(containerColor = if (router.selection?.id == summary.id) Theme.colors.brand.copy(alpha = 0.12f) else Theme.colors.background),
        modifier = Modifier.combinedClickable(onClick = { router.open(summary.id) }, onLongClick = { menu = true })
            .testTag("document-${summary.number ?: summary.id}"),
    )
    HorizontalDivider(color = Theme.colors.border.copy(alpha = 0.5f))
}
