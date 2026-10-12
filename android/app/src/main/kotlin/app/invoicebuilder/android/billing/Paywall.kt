package app.invoicebuilder.android.billing

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Devices
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.automirrored.filled.NoteAdd
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.common.ErrorAlert
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.LabeledValue
import app.invoicebuilder.core.designsystem.NavRow
import app.invoicebuilder.core.designsystem.PrimaryButton
import app.invoicebuilder.core.designsystem.ReadableColumn
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.billing.EntitlementState
import app.invoicebuilder.core.domain.billing.FreeTier
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The unlock (`spec/billing.md`): the store's localised price, Refresh purchases, and the pending-payment state.
 * Shown when Issue is tapped at the limit, and from Settings. Nothing else is ever locked. iOS: `PaywallView`.
 */
@Composable
fun PaywallDialog(session: Session, onDismiss: () -> Unit) {
    val status = session.entitlement
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isWorking by remember { mutableStateOf(false) }
    var refreshFailed by remember { mutableStateOf(false) }
    LaunchedEffect(status.state) {
        if (status.state == EntitlementState.unlocked) { delay(1000); onDismiss() }
    }
    Dialog(onDismiss, DialogProperties(usePlatformDefaultWidth = false)) {
        androidx.compose.material3.Surface(Modifier.fillMaxWidth().padding(Theme.Space.l), shape = MaterialTheme.shapes.large, color = Theme.colors.surface) {
            Column(Modifier.verticalScroll(rememberScrollState()).padding(Theme.Space.xl), verticalArrangement = Arrangement.spacedBy(Theme.Space.m),
                horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(if (status.isUnlocked) Icons.Filled.Verified else Icons.Filled.AllInclusive, null, Modifier.size(56.dp), tint = Theme.colors.brand)
                Text(
                    when (status.state) {
                        EntitlementState.unlocked -> "Unlimited invoices are on"
                        EntitlementState.limitReached -> "You've used your ${FreeTier.LIMIT} free invoices"
                        else -> "${status.remaining} of ${FreeTier.LIMIT} free invoices left"
                    },
                    style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center,
                )
                Text(if (status.isUnlocked) "Thank you. Send as many invoices as you need." else "Unlock unlimited invoices once, on every device you use.",
                    color = Theme.colors.textSecondary, textAlign = TextAlign.Center)
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                    Benefit("Send as many invoices as you need", Icons.AutoMirrored.Filled.NoteAdd)
                    Benefit("One payment, no subscription", Icons.Filled.CreditCard)
                    Benefit("On every device with your Google account", Icons.Filled.Devices)
                    Benefit("Your invoices, quotes and backups were never locked", Icons.Filled.LockOpen)
                }
                when (status.state) {
                    EntitlementState.unlocked -> {}
                    EntitlementState.pending -> Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.HourglassTop, null, tint = Theme.colors.textSecondary)
                        Text("  Payment pending. You can keep working; invoices unlock when the payment completes.", color = Theme.colors.textSecondary)
                    }
                    else -> {
                        PrimaryButton(status.displayPrice?.let { "Unlock for $it" } ?: "Unlock", {
                            val activity = context.findActivity() ?: return@PrimaryButton
                            scope.launch {
                                isWorking = true
                                session.container.entitlements.purchase(activity)
                                isWorking = false
                            }
                        }, isBusy = isWorking || status.state == EntitlementState.purchasing, enabled = status.displayPrice != null, tag = "paywall.buy")
                        if (status.displayPrice == null) {
                            Text("Google Play can't be reached right now.", style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
                        }
                    }
                }
                TextButton({
                    scope.launch {
                        isWorking = true
                        refreshFailed = !session.container.entitlements.restore()
                        isWorking = false
                    }
                }, enabled = !isWorking, modifier = Modifier.testTag("paywall.restore")) { Text("Refresh purchases") }
                if (refreshFailed) {
                    Text(BillingText.refreshFailed, Modifier.testTag("paywall.refreshFailed"), style = MaterialTheme.typography.bodySmall,
                        color = Theme.colors.warning, textAlign = TextAlign.Center)
                }
                Text("A one-time purchase, charged to your Google Play account at confirmation.",
                    style = MaterialTheme.typography.bodySmall, color = Theme.colors.textTertiary, textAlign = TextAlign.Center)
                TextButton(onDismiss) { Text("Close") }
            }
        }
    }
}

@Composable
private fun Benefit(text: String, icon: ImageVector) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Theme.colors.brand)
        Text("  $text", fontWeight = FontWeight.Medium)
    }
}

/** Settings → Unlimited invoices. iOS: `UnlockPage`. */
@Composable
fun UnlockPage(session: Session) {
    var showsPaywall by remember { mutableStateOf(false) }
    var refreshing by remember { mutableStateOf(false) }
    var refreshMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val status = session.entitlement
    ReadableColumn {
        FormSection(footer = "Quotes, drafts, sharing and backups are always free. Only issuing invoices beyond ${FreeTier.LIMIT} needs the unlock.") {
            LabeledValue("Status", when (status.state) {
                EntitlementState.unlocked -> "Unlocked"
                EntitlementState.pending -> "Payment pending"
                EntitlementState.purchasing -> "Purchasing…"
                EntitlementState.unknown -> "Checking…"
                else -> "Free"
            }, valueTag = "unlock.status")
            if (!status.isUnlocked) {
                LabeledValue("Free invoices left", "${status.remaining} of ${FreeTier.LIMIT}")
                NavRow("Unlock unlimited invoices", { showsPaywall = true })
            }
            NavRow("Refresh purchases", {
                if (refreshing) return@NavRow
                scope.launch {
                    refreshing = true
                    if (!session.container.entitlements.restore()) refreshMessage = BillingText.refreshFailed
                    refreshing = false
                }
            }, value = if (refreshing) "Checking…" else null, tag = "unlock.refresh")
        }
    }
    if (showsPaywall) PaywallDialog(session) { showsPaywall = false }
    ErrorAlert(refreshMessage, { refreshMessage = null }, title = "Purchases not refreshed")
}

/** What the unlock screens say. */
object BillingText {
    /** Play didn't answer "Refresh purchases" (`spec/billing.md`, Android): nothing changed, so say so. */
    const val refreshFailed = "Google Play can't be reached right now, so your purchases weren't refreshed. " +
        "Check your connection and try again."
}

tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
