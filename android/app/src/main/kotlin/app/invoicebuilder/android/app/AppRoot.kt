package app.invoicebuilder.android.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.testTag
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.android.catalog.CatalogSection
import app.invoicebuilder.android.clients.ClientsSection
import app.invoicebuilder.android.documents.DocumentsSection
import app.invoicebuilder.android.home.HomeScreen
import app.invoicebuilder.android.onboarding.OnboardingScreen
import app.invoicebuilder.android.settings.SettingsSection
import app.invoicebuilder.core.designsystem.Theme

/** The session for the screens below the shell (≈ `.environment(session)`). */
val LocalSession = staticCompositionLocalOf<Session> { error("No session") }

/** The root: onboarding until a business exists, then the adaptive shell. iOS: `AppRootView`. */
@Composable
fun AppRoot(model: AppModel, requestNotificationPermission: () -> Unit) {
    Surface(Modifier.fillMaxSize(), color = Theme.colors.background) {
        when (val phase = model.phase) {
            AppModel.Phase.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            is AppModel.Phase.Onboarding -> OnboardingScreen(phase.model)
            is AppModel.Phase.Ready -> {
                LaunchedEffect(phase.session) { phase.session.requestNotificationPermission = requestNotificationPermission }
                MainShell(phase.session)
            }
            is AppModel.Phase.Failed -> Column(
                Modifier.fillMaxSize().padding(Theme.Space.xl), verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(Icons.Filled.Warning, null, tint = Theme.colors.warning)
                Text("Your data couldn't be opened", style = MaterialTheme.typography.titleMedium)
                Text(phase.message, color = Theme.colors.textSecondary)
            }
        }
    }
}

private data class TabItem(val tab: AppTab, val title: String, val icon: ImageVector)

private val tabs = listOf(
    TabItem(AppTab.home, "Home", Icons.Filled.Home),
    TabItem(AppTab.documents, "Invoices", Icons.Filled.Description),
    TabItem(AppTab.clients, "Clients", Icons.Filled.People),
    TabItem(AppTab.items, "Items", Icons.Filled.Inventory2),
    TabItem(AppTab.settings, "Settings", Icons.Filled.Settings),
)

/**
 * A bottom bar on phones, a rail on tablets and unfolded foldables, a drawer on wide desktop windows — chosen from
 * the window size (≈ `TabView` with `.sidebarAdaptable`, ADR-0014). Each section is a list/detail layout whose
 * state lives in `session.router`.
 */
@Composable
fun MainShell(session: Session) {
    val router = session.router
    CompositionLocalProvider(LocalSession provides session) {
        NavigationSuiteScaffold(
            // Hardware keyboards (tablets, Chromebooks, DeX): Ctrl+N new invoice, Ctrl+Shift+N new quote (≈ ⌘N / ⇧⌘N).
            modifier = Modifier.onPreviewKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown || !event.isCtrlPressed || event.key != Key.N) return@onPreviewKeyEvent false
                session.startNewDocument(if (event.isShiftPressed) DocumentType.quote else DocumentType.invoice)
                true
            },
            navigationSuiteItems = {
                for (item in tabs) {
                    item(
                        selected = router.selectedTab == item.tab,
                        onClick = { router.selectedTab = item.tab },
                        icon = { Icon(item.icon, null) },
                        label = { Text(item.title) },
                        modifier = Modifier.testTag("tab-${item.tab}"),
                    )
                }
            },
            containerColor = Theme.colors.background,
        ) {
            when (router.selectedTab) {
                AppTab.home -> HomeScreen(session)
                AppTab.documents -> DocumentsSection(session)
                AppTab.clients -> ClientsSection(session)
                AppTab.items -> CatalogSection(session)
                AppTab.settings -> SettingsSection(session)
            }
        }
    }
}
