package app.invoicebuilder.android.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Send
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.invoicebuilder.android.app.SampleData
import app.invoicebuilder.core.designsystem.AppFonts
import app.invoicebuilder.core.designsystem.PrimaryButton
import app.invoicebuilder.core.designsystem.ScreenHeader
import app.invoicebuilder.core.designsystem.TextLinkButton
import app.invoicebuilder.core.designsystem.Theme

/**
 * The first screen (`docs/design/design.md` §6.1): what the app does in three promises, then "Let's get started".
 * "I've used this app before" restores; "Just looking?" opens the sample business. iOS: `WelcomeView`.
 */
@Composable
fun WelcomeScreen(model: OnboardingViewModel, onRestore: () -> Unit) {
    var showsRestore by rememberSaveable { mutableStateOf(false) }
    var showsSamples by rememberSaveable { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().background(Theme.colors.background).statusBarsPadding().navigationBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Column(
            Modifier.weight(1f).widthIn(max = 560.dp).fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = Theme.Space.xl, vertical = 20.dp),
        ) {
            Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.size(32.dp).clip(RoundedCornerShape(10.dp)).background(Theme.colors.brand), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.Description, null, tint = Theme.colors.brandOn, modifier = Modifier.size(18.dp))
                }
                Text("InvoiceBuilder", style = Theme.Fonts.title3, color = Theme.colors.textPrimary)
            }
            WelcomeIllustration(Modifier.padding(top = 20.dp))
            ScreenHeader("Send a proper invoice in about a minute.", Modifier.padding(top = Theme.Space.xl),
                subtitle = "No accounting jargon. We'll guide you one simple question at a time.", large = true)
            Column(Modifier.padding(top = 22.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Promise(1, "Tell us about your business", "Once, about 2 minutes")
                Promise(2, "Add who you're billing and what you sold", "We work out the GST or VAT for you")
                Promise(3, "Send it on WhatsApp or email", "Then see at a glance who has paid")
            }
        }
        Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = Theme.Space.xl, vertical = Theme.Space.s),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Theme.Space.xs)) {
            Row(Modifier.padding(bottom = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Outlined.Lock, null, tint = Theme.colors.textSecondary, modifier = Modifier.size(15.dp))
                Text("Your data stays on your phone. No account needed.", style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
            }
            PrimaryButton("Let's get started", model::start, tag = "onboarding.start", trailingArrow = true)
            Row(horizontalArrangement = Arrangement.spacedBy(Theme.Space.l)) {
                TextLinkButton("I've used this app before", { showsRestore = true }, tag = "onboarding.usedBefore")
                TextLinkButton("Just looking?", { showsSamples = true }, tag = "onboarding.justLooking")
            }
        }
    }
    if (showsRestore) {
        AlertDialog(
            { showsRestore = false }, title = { Text("Welcome back") },
            text = { Text("Start from an InvoiceBuilder backup file, saved from this app on any phone or iPhone.") },
            confirmButton = {
                TextButton({ showsRestore = false; onRestore() }, Modifier.testTag("onboarding.restore")) { Text("Restore from a backup file") }
            },
            dismissButton = { TextButton({ showsRestore = false }) { Text("Cancel") } },
        )
    }
    if (showsSamples) {
        AlertDialog(
            { showsSamples = false }, title = { Text("Try a sample business") },
            text = { Text("See invoices, quotes and payments in a sample business. Nothing you do there is saved.") },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    TextButton({ showsSamples = false; model.tryDemo(SampleData.Country.india) }, Modifier.testTag("onboarding.demoIN")) {
                        Text("A sample Indian business")
                    }
                    TextButton({ showsSamples = false; model.tryDemo(SampleData.Country.uk) }, Modifier.testTag("onboarding.demoGB")) {
                        Text("A sample UK business")
                    }
                }
            },
            dismissButton = { TextButton({ showsSamples = false }) { Text("Cancel") } },
        )
    }
}

/** One numbered promise on the Welcome screen. */
@Composable
private fun Promise(number: Int, title: String, hint: String) {
    Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.size(30.dp).clip(CircleShape).background(Theme.colors.surface).border(1.5.dp, Theme.colors.borderStrong, CircleShape),
            contentAlignment = Alignment.Center) {
            Text("$number", style = Theme.Fonts.subhead.copy(fontWeight = FontWeight.Bold), color = Theme.colors.textPrimary)
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = Theme.Fonts.rowTitle, color = Theme.colors.textPrimary)
            Text(hint, style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
        }
    }
}

/** The hero: an invoice card, a "PAID" stamp and a paper plane on the brand tint. Decoration only. */
@Composable
private fun WelcomeIllustration(modifier: Modifier = Modifier) {
    val ink = Color(0xFF2A2135)
    Box(modifier.fillMaxWidth().height(196.dp).clip(RoundedCornerShape(Theme.Radius.hero)).background(Theme.colors.brandTint)
        .clearAndSetSemantics {}) {
        Column(
            Modifier.offset(x = 62.dp, y = 26.dp).rotate(-4f).width(176.dp).height(196.dp)
                .shadow(12.dp, RoundedCornerShape(12.dp), ambientColor = ink.copy(alpha = 0.12f), spotColor = ink.copy(alpha = 0.12f))
                .clip(RoundedCornerShape(12.dp)).background(Theme.colors.surface).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(22.dp).clip(RoundedCornerShape(7.dp)).background(Theme.colors.brand))
                Spacer(Modifier.weight(1f))
                Text("INVOICE", fontFamily = AppFonts.display, fontWeight = FontWeight.Bold, fontSize = 10.sp, letterSpacing = 1.sp,
                    color = Theme.colors.textSecondary)
            }
            Bar(0.7f); Bar(0.5f)
            Box(Modifier.fillMaxWidth().height(1.dp).background(Theme.colors.surfaceMuted))
            Row { Bar(0.55f); Spacer(Modifier.weight(1f)); Bar(0.2f) }
            Row { Bar(0.45f); Spacer(Modifier.weight(1f)); Bar(0.2f) }
            Row(verticalAlignment = Alignment.Bottom) {
                Text("Total", fontSize = 10.sp, color = Theme.colors.textSecondary)
                Spacer(Modifier.weight(1f))
                Text("₹20,060", fontFamily = AppFonts.display, fontWeight = FontWeight.Bold, fontSize = 18.sp, color = Theme.colors.textPrimary)
            }
        }
        Text("PAID", Modifier.align(Alignment.TopEnd).offset(x = (-54).dp, y = 112.dp).rotate(10f).clip(RoundedCornerShape(10.dp))
            .background(Theme.colors.highlight).border(2.5.dp, ink, RoundedCornerShape(10.dp)).padding(horizontal = 14.dp, vertical = 6.dp),
            fontFamily = AppFonts.display, fontWeight = FontWeight.Bold, fontSize = 18.sp, letterSpacing = 1.sp, color = ink)
        Box(Modifier.align(Alignment.TopEnd).offset(x = (-28).dp, y = 28.dp).size(46.dp).shadow(6.dp, CircleShape).clip(CircleShape)
            .background(Theme.colors.surface), contentAlignment = Alignment.Center) {
            Icon(Icons.AutoMirrored.Outlined.Send, null, tint = Theme.colors.brand, modifier = Modifier.size(22.dp))
        }
    }
}

@Composable
private fun Bar(fraction: Float) {
    Box(Modifier.width((144 * fraction).dp).height(6.dp).clip(RoundedCornerShape(3.dp)).background(Theme.colors.border))
}
