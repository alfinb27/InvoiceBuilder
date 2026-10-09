package app.invoicebuilder.android.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.automirrored.filled.NoteAdd
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.RequestQuote
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.invoicebuilder.android.app.AppTab
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.app.SettingsPage
import app.invoicebuilder.android.billing.PaywallDialog
import app.invoicebuilder.android.common.ImageWell
import app.invoicebuilder.android.documents.DocumentText
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.designsystem.readableWidth
import app.invoicebuilder.core.domain.billing.EntitlementState
import app.invoicebuilder.core.domain.billing.FreeTier
import app.invoicebuilder.core.domain.documents.DashboardTotals
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.numbering.DuplicateNumbers
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** Home: the business at a glance, what's owed, what to set up next and quick actions. iOS: `HomeView`. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(session: Session) {
    val container = session.container
    val businessID = session.business.id
    val clientCount by remember(businessID) { container.clients.observeClients(businessID).map { it.size } }.collectAsStateWithLifecycle(0)
    val itemCount by remember(businessID) { container.catalog.observeItems(businessID).map { it.size } }.collectAsStateWithLifecycle(0)
    val dashboard by remember(businessID) { container.documents.observeDashboard(businessID, session.business.homeCurrency) }
        .collectAsStateWithLifecycle(DashboardTotals())
    val duplicates by remember(businessID) { container.numbering.observeDuplicateNumbers(businessID) }.collectAsStateWithLifecycle(emptyList())
    val setupComplete = clientCount > 0 && itemCount > 0 && session.business.logoAssetId != null && session.business.signatureAssetId != null

    Scaffold(
        containerColor = Theme.colors.background,
        topBar = { TopAppBar({ Text("Home") }, colors = TopAppBarDefaults.topAppBarColors(containerColor = Theme.colors.background)) },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()), contentAlignment = Alignment.TopCenter) {
            Column(Modifier.readableWidth().fillMaxWidth().padding(Theme.Space.l), verticalArrangement = Arrangement.spacedBy(Theme.Space.l)) {
                if (session.isDemo) DemoBanner(session)
                BusinessCard(session)
                val entitlement = session.entitlement
                if (!entitlement.isUnlocked && entitlement.state != EntitlementState.unknown && entitlement.remaining <= 3) FreeTierBanner(session)
                for (group in duplicates) DuplicateNumberWarning(group, session)
                if (dashboard != DashboardTotals()) {
                    Card(Modifier.testTag("homeDashboard")) {
                        Header("Money", Icons.Filled.Payments)
                        Row(horizontalArrangement = Arrangement.spacedBy(Theme.Space.l)) {
                            DashboardTile("Outstanding", session.money(dashboard.outstandingMinor), Modifier.weight(1f))
                            DashboardTile("Overdue", session.money(dashboard.overdueMinor), Modifier.weight(1f),
                                if (dashboard.overdueMinor > 0) Theme.colors.danger else null)
                            DashboardTile("Paid this month", session.money(dashboard.paidThisMonthMinor), Modifier.weight(1f))
                        }
                    }
                }
                if (!setupComplete) {
                    Card {
                        Text("Get ready to invoice", style = MaterialTheme.typography.titleMedium)
                        ChecklistRow(true, "Set up your business")
                        ChecklistRow(clientCount > 0, if (clientCount > 0) "$clientCount client${if (clientCount == 1) "" else "s"}" else "Add your first client",
                            "Add client") { session.router.startNewClient() }
                        ChecklistRow(itemCount > 0,
                            if (itemCount > 0) "$itemCount item${if (itemCount == 1) "" else "s"} in your catalogue" else "Add the goods or services you sell",
                            "Add item") { session.router.startNewItem() }
                        ChecklistRow(session.business.logoAssetId != null && session.business.signatureAssetId != null, "Add your logo and signature", "Open") {
                            session.router.settings.selection = SettingsPage.images
                            session.router.selectedTab = AppTab.settings
                        }
                    }
                }
                Card {
                    Header("Invoices and quotes", Icons.AutoMirrored.Filled.NoteAdd)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(Theme.Space.m), verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                        Button({ session.startNewDocument(DocumentType.invoice) }, Modifier.testTag("homeNewInvoice")) {
                            Icon(Icons.AutoMirrored.Filled.NoteAdd, null); Text("  New invoice")
                        }
                        OutlinedButton({ session.startNewDocument(DocumentType.quote) }, Modifier.testTag("homeNewQuote")) {
                            Icon(Icons.Filled.RequestQuote, null); Text("  New quote", color = Theme.colors.textPrimary)
                        }
                    }
                }
                if (session.config.reviewStatus != "reviewed") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Info, null, tint = Theme.colors.textSecondary)
                        Text("  ${session.config.labels.taxName} rules in this build are awaiting review by a professional.",
                            style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
                    }
                }
            }
        }
    }
}

@Composable
private fun BusinessCard(session: Session) {
    val logoID = session.business.logoAssetId
    val logo by produceState<ByteArray?>(null, logoID) { value = logoID?.let { session.container.assets.fetchAsset(it)?.data } }
    Card(Modifier.semantics(mergeDescendants = true) {}) {
        Row {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Theme.Space.xs)) {
                Text(session.business.name, style = MaterialTheme.typography.titleLarge)
                session.registration?.let { Text(it.label, color = Theme.colors.textSecondary) }
                session.business.taxId?.let { Text("${session.config.labels.taxIdName} $it", fontFamily = FontFamily.Monospace, color = Theme.colors.textSecondary) }
                session.business.address?.let { Text(it.singleLine, color = Theme.colors.textSecondary) }
            }
            if (logo != null) ImageWell(logo, "Logo")
        }
    }
}

@Composable
private fun DashboardTile(title: String, value: String, modifier: Modifier, emphasis: Color? = null) {
    Column(modifier.semantics(mergeDescendants = true) {}) {
        Text(title, style = MaterialTheme.typography.labelSmall, color = Theme.colors.textSecondary)
        Text(value, style = MaterialTheme.typography.titleMedium, color = emphasis ?: Theme.colors.textPrimary)
    }
}

@Composable
private fun ChecklistRow(done: Boolean, title: String, actionTitle: String? = null, action: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
        Icon(if (done) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, if (done) "Done" else "Not done",
            tint = if (done) Theme.colors.success else Theme.colors.textTertiary)
        Text("  $title", Modifier.weight(1f))
        if (!done && actionTitle != null && action != null) OutlinedButton(action) { Text(actionTitle, color = Theme.colors.textPrimary) }
    }
}

@Composable
private fun Header(title: String, icon: ImageVector) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Theme.colors.brand)
        Text("  $title", style = MaterialTheme.typography.titleMedium)
    }
}

/** A rounded surface for Home's content. */
@Composable
fun Card(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().background(Theme.colors.surface, RoundedCornerShape(Theme.Radius.l))
            .border(androidx.compose.ui.unit.Dp.Hairline, Theme.colors.border.copy(alpha = 0.6f), RoundedCornerShape(Theme.Radius.l))
            .padding(Theme.Space.l),
        verticalArrangement = Arrangement.spacedBy(Theme.Space.m), content = content,
    )
}

/** Two issued documents share a number (`spec/sync.md` §4): say so and link to them; nothing is renumbered. */
@Composable
private fun DuplicateNumberWarning(group: DuplicateNumbers.Group, session: Session) {
    Column(Modifier.fillMaxWidth().background(Theme.colors.warning.copy(alpha = 0.1f), RoundedCornerShape(12)).padding(Theme.Space.m),
        verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Warning, null, tint = Theme.colors.warning)
            Text("  ${group.ids.size} ${DocumentText.noun(group.docType)}s share the number ${group.number}", fontWeight = FontWeight.SemiBold, color = Theme.colors.warning)
        }
        Text("Void one of them and issue it again, so each number is used once.", style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
        Row(horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
            group.ids.forEachIndexed { index, id -> OutlinedButton({ session.openDocument(id, group.docType) }) { Text("Open ${index + 1}") } }
        }
    }
}

/** Three or fewer free invoices left (`spec/billing.md`): say so, once, without blocking anything. */
@Composable
private fun FreeTierBanner(session: Session) {
    var showsPaywall by rememberSaveable { mutableStateOf(false) }
    val remaining = session.entitlement.remaining
    Row(Modifier.fillMaxWidth().background(Theme.colors.brand.copy(alpha = 0.08f), RoundedCornerShape(12)).padding(Theme.Space.m).testTag("home.freeTier"),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.AllInclusive, null, tint = Theme.colors.brand)
        Text(
            "  " + if (remaining == 0) "You've used your ${FreeTier.LIMIT} free invoices" else "$remaining free invoice${if (remaining == 1) "" else "s"} left",
            Modifier.weight(1f), fontWeight = FontWeight.Medium,
        )
        OutlinedButton({ showsPaywall = true }) { Text("Unlock") }
    }
    if (showsPaywall) PaywallDialog(session) { showsPaywall = false }
}

/** The sample business is not saved; leaving it goes back to setting up the real one. */
@Composable
private fun DemoBanner(session: Session) {
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxWidth().background(Theme.colors.brand.copy(alpha = 0.08f), RoundedCornerShape(12)).padding(Theme.Space.m),
        verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.AutoAwesome, null, tint = Theme.colors.brand)
            Text("  This is a sample business", fontWeight = FontWeight.SemiBold)
        }
        Text("Look around and try anything: nothing here is saved.", style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
        Button({ scope.launch { session.reloadApp() } }, Modifier.testTag("demo.leave")) { Text("Set up my business") }
    }
}
