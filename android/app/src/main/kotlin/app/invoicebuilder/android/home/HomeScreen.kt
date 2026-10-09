package app.invoicebuilder.android.home

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Draw
import androidx.compose.material.icons.filled.RequestQuote
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.invoicebuilder.android.app.AppTab
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.app.SettingsPage
import app.invoicebuilder.android.billing.PaywallDialog
import app.invoicebuilder.android.documents.DocumentText
import app.invoicebuilder.core.designsystem.Avatar
import app.invoicebuilder.core.designsystem.ChecklistRow
import app.invoicebuilder.core.designsystem.EmptyStatTile
import app.invoicebuilder.core.designsystem.MutedDivider
import app.invoicebuilder.core.designsystem.Overline
import app.invoicebuilder.core.designsystem.PrimaryButton
import app.invoicebuilder.core.designsystem.ProgressBar
import app.invoicebuilder.core.designsystem.SecondaryButton
import app.invoicebuilder.core.designsystem.StatTile
import app.invoicebuilder.core.designsystem.SurfaceCard
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.designsystem.TipCallout
import app.invoicebuilder.core.designsystem.readableWidth
import app.invoicebuilder.core.domain.billing.EntitlementState
import app.invoicebuilder.core.domain.billing.FreeTier
import app.invoicebuilder.core.domain.documents.DashboardTotals
import app.invoicebuilder.core.domain.documents.DocumentSummary
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.numbering.DuplicateNumbers
import app.invoicebuilder.core.domain.setup.FirstRunChecklist
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

/**
 * Home: until the first invoice is sent, a checklist and a big "Create an invoice" (`spec/setup.md` §3.2); then
 * what's owed and quick actions for invoices and quotes. iOS: `HomeView`.
 */
@Composable
fun HomeScreen(session: Session) {
    val container = session.container
    val businessID = session.business.id
    val clientCount by remember(businessID) { container.clients.observeClients(businessID).map { it.size } }.collectAsStateWithLifecycle(0)
    val itemCount by remember(businessID) { container.catalog.observeItems(businessID).map { it.size } }.collectAsStateWithLifecycle(0)
    val documents by remember(businessID) { container.documents.observeDocuments(businessID) }
        .collectAsStateWithLifecycle<List<DocumentSummary>?>(null)
    val dashboard by remember(businessID) { container.documents.observeDashboard(businessID, session.business.homeCurrency) }
        .collectAsStateWithLifecycle(DashboardTotals())
    val duplicates by remember(businessID) { container.numbering.observeDuplicateNumbers(businessID) }.collectAsStateWithLifecycle(emptyList())

    Box(Modifier.fillMaxSize().background(Theme.colors.background).statusBarsPadding().verticalScroll(rememberScrollState()),
        contentAlignment = Alignment.TopCenter) {
        Column(Modifier.readableWidth().fillMaxWidth().padding(horizontal = Theme.Layout.screenGutter, vertical = Theme.Space.xl),
            verticalArrangement = Arrangement.spacedBy(Theme.Space.l)) {
            HomeHeader(session)
            if (session.isDemo) DemoBanner(session)
            val entitlement = session.entitlement
            if (!entitlement.isUnlocked && entitlement.state != EntitlementState.unknown && entitlement.remaining <= 3) FreeTierBanner(session)
            for (group in duplicates) DuplicateNumberWarning(group, session)
            documents?.let { list ->
                val checklist = FirstRunChecklist.of(clientCount, itemCount, list)
                if (checklist.isShown) FirstRun(session, checklist, dashboard) else Dashboard(session, dashboard)
            }
            if (session.config.reviewStatus != "reviewed") {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                    Icon(Icons.Outlined.Info, null, tint = Theme.colors.textSecondary, modifier = Modifier.size(18.dp))
                    Text("${session.config.labels.taxName} rules in this build are awaiting review by a professional.",
                        style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
                }
            }
        }
    }
}

@Composable
private fun FirstRun(session: Session, checklist: FirstRunChecklist, dashboard: DashboardTotals) {
    SurfaceCard(Modifier.testTag("home.checklist"), padding = 18.dp) {
        Text("Get ready to send your first invoice", style = Theme.Fonts.title3, color = Theme.colors.textPrimary,
            modifier = Modifier.semantics { heading() })
        ProgressBar(checklist.doneCount, FirstRunChecklist.Item.entries.size)
        Column {
            FirstRunChecklist.Item.entries.forEachIndexed { index, item ->
                val (title, hint, action) = when (item) {
                    FirstRunChecklist.Item.setUpBusiness -> Triple("Set up your business", null, null)
                    FirstRunChecklist.Item.addClient -> Triple("Add your first client", "The person or shop you're billing",
                        { session.router.startNewClient() })
                    FirstRunChecklist.Item.saveItem -> Triple("Save something you sell", "Add it once, reuse it on every invoice",
                        { session.router.startNewItem() })
                    FirstRunChecklist.Item.sendInvoice -> Triple("Send your first invoice", "${FreeTier.LIMIT} invoices free, no sign-up",
                        { session.startNewDocument(DocumentType.invoice) })
                }
                ChecklistRow(title, checklist.isDone(item), hint = hint, onClick = action, tag = "checklist.${item.name}")
                if (index < FirstRunChecklist.Item.entries.size - 1) MutedDivider()
            }
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
        PrimaryButton("Create an invoice", { session.startNewDocument(DocumentType.invoice) }, tag = "homeNewInvoice", icon = Icons.Filled.Add)
        Text("You can jump straight in. We'll ask for the client and items as you go.", style = Theme.Fonts.footnote,
            color = Theme.colors.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Overline("Once you start sending")
        MoneyTiles(session, dashboard, empty = true)
    }
}

@Composable
private fun Dashboard(session: Session, dashboard: DashboardTotals) {
    Column(Modifier.testTag("homeDashboard"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Overline("Money")
        MoneyTiles(session, dashboard, empty = false)
    }
    Column(verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
        PrimaryButton("New invoice", { session.startNewDocument(DocumentType.invoice) }, tag = "homeNewInvoice", icon = Icons.Filled.Add)
        SecondaryButton("New quote", { session.startNewDocument(DocumentType.quote) }, icon = Icons.Filled.RequestQuote,
            tag = "homeNewQuote", fillsWidth = true)
    }
    if (session.business.logoAssetId == null || session.business.signatureAssetId == null) {
        Box(Modifier.clip(RoundedCornerShape(Theme.Radius.input)).clickable {
            session.router.settings.selection = SettingsPage.images
            session.router.selectedTab = AppTab.settings
        }) {
            TipCallout("Add your logo and signature so your invoices look like yours.", icon = Icons.Filled.Draw)
        }
    }
}

/** Waiting to be paid, past due and paid this month: dashed and at 0 before the first invoice. */
@Composable
private fun MoneyTiles(session: Session, dashboard: DashboardTotals, empty: Boolean) {
    val tiles = listOf(
        Triple("Waiting to be paid", dashboard.outstandingMinor, false),
        Triple("Past due date", dashboard.overdueMinor, dashboard.overdueMinor > 0),
        Triple("Paid this month", dashboard.paidThisMonthMinor, false),
    )
    BoxWithConstraints {
        val stacked = maxWidth < 300.dp
        val content: @Composable (Modifier) -> Unit = { tileModifier ->
            for ((label, minor, alert) in tiles) {
                if (empty) EmptyStatTile(session.money(0), label, tileModifier)
                else StatTile(session.money(minor), label, tileModifier, if (alert) Theme.colors.danger else null)
            }
        }
        if (stacked) Column(verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) { content(Modifier.fillMaxWidth()) }
        else Row(horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) { content(Modifier.weight(1f)) }
    }
}

/** "Good morning", the business name, and its logo or initials. */
@Composable
private fun HomeHeader(session: Session) {
    val logoID = session.business.logoAssetId
    val logo by produceState<ByteArray?>(null, logoID) { value = logoID?.let { session.container.assets.fetchAsset(it)?.data } }
    val hour = Instant.ofEpochMilli(session.container.time.now()).atZone(ZoneId.systemDefault()).hour
    val greeting = when (hour) { in 5..11 -> "Good morning"; in 12..16 -> "Good afternoon"; else -> "Good evening" }
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Theme.Space.m)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(greeting, style = Theme.Fonts.subhead, color = Theme.colors.textSecondary)
            Text(session.business.name, style = Theme.Fonts.title, color = Theme.colors.textPrimary, modifier = Modifier.semantics { heading() })
        }
        val bitmap = remember(logo) { logo?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
        if (bitmap != null) {
            Image(bitmap, null, Modifier.size(44.dp).clip(CircleShape).background(Theme.colors.surface), contentScale = ContentScale.Fit)
        } else {
            Avatar(session.business.name, size = 44.dp)
        }
    }
}

/** Two issued documents share a number (`spec/sync.md` §4): say so and link to them; nothing is renumbered. */
@Composable
private fun DuplicateNumberWarning(group: DuplicateNumbers.Group, session: Session) {
    val shape = RoundedCornerShape(Theme.Radius.card)
    Column(Modifier.fillMaxWidth().clip(shape).background(Theme.colors.surface).border(1.dp, Theme.colors.warning.copy(alpha = 0.5f), shape)
        .padding(Theme.Space.l), verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
            Icon(Icons.Filled.Warning, null, tint = Theme.colors.warning)
            Text("${group.ids.size} ${DocumentText.noun(group.docType)}s share the number ${group.number}",
                style = Theme.Fonts.subhead.copy(fontWeight = FontWeight.SemiBold), color = Theme.colors.warning)
        }
        Text("Void one of them and send it again, so each number is used once.", style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
        Row(horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
            group.ids.forEachIndexed { index, id -> SecondaryButton("Open ${index + 1}", { session.openDocument(id, group.docType) }) }
        }
    }
}

/** Three or fewer free invoices left (`spec/billing.md`): say so, once, without blocking anything. */
@Composable
private fun FreeTierBanner(session: Session) {
    var showsPaywall by rememberSaveable { mutableStateOf(false) }
    val remaining = session.entitlement.remaining
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.Radius.l)).background(Theme.colors.brandTint).padding(14.dp)
        .testTag("home.freeTier"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Theme.Space.m)) {
        Icon(Icons.Filled.AllInclusive, null, tint = Theme.colors.brandPressed)
        Text(if (remaining == 0) "You've used your ${FreeTier.LIMIT} free invoices" else "$remaining free invoice${if (remaining == 1) "" else "s"} left",
            Modifier.weight(1f), style = Theme.Fonts.rowTitle, color = Theme.colors.textPrimary)
        SecondaryButton("Unlock", { showsPaywall = true })
    }
    if (showsPaywall) PaywallDialog(session) { showsPaywall = false }
}

/** The sample business is not saved; leaving it goes back to setting up the real one. */
@Composable
private fun DemoBanner(session: Session) {
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.Radius.card)).background(Theme.colors.brandTint).padding(Theme.Space.l),
        verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
            Icon(Icons.Filled.AutoAwesome, null, tint = Theme.colors.brandPressed)
            Text("This is a sample business", style = Theme.Fonts.rowTitle, color = Theme.colors.textPrimary)
        }
        Text("Look around and try anything: nothing here is saved.", style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
        SecondaryButton("Set up my business", { scope.launch { session.reloadApp() } }, tag = "demo.leave")
    }
}

