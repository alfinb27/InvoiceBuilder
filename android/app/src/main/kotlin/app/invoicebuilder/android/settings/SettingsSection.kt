package app.invoicebuilder.android.settings

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Draw
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Numbers
import androidx.compose.material.icons.filled.Percent
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Badge
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.invoicebuilder.android.app.AppContainer
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.app.SettingsPage
import app.invoicebuilder.android.backup.BackupPage
import app.invoicebuilder.android.backup.BackupViewModel
import app.invoicebuilder.android.billing.UnlockPage
import app.invoicebuilder.android.common.BankSections
import app.invoicebuilder.android.common.BusinessDetailsSections
import app.invoicebuilder.android.common.DetailColumn
import app.invoicebuilder.android.common.EditorSheet
import app.invoicebuilder.android.common.EmptyState
import app.invoicebuilder.android.common.ErrorAlert
import app.invoicebuilder.android.common.ImagesFormSections
import app.invoicebuilder.android.common.ListDetail
import app.invoicebuilder.android.common.RegistrationSections
import app.invoicebuilder.android.common.SystemSheets
import app.invoicebuilder.core.designsystem.DateField
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.FormTextField
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.designsystem.IssueText
import app.invoicebuilder.core.designsystem.LabeledValue
import app.invoicebuilder.core.designsystem.NavRow
import app.invoicebuilder.core.designsystem.PickerField
import app.invoicebuilder.core.designsystem.SwitchRow
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.designsystem.hexColor
import app.invoicebuilder.core.domain.models.TemplateID
import app.invoicebuilder.core.domain.numbering.NumberingReset
import app.invoicebuilder.core.domain.setup.BusinessRules
import app.invoicebuilder.core.domain.setup.CustomRateField
import app.invoicebuilder.core.domain.setup.CustomRates
import app.invoicebuilder.core.domain.setup.NumberingSeriesField
import app.invoicebuilder.core.domain.tax.RatesSource
import kotlinx.coroutines.launch
import java.io.File

private val SettingsPage.icon: ImageVector
    get() = when (this) {
        SettingsPage.profile -> Icons.Filled.Business
        SettingsPage.images -> Icons.Filled.Draw
        SettingsPage.numbering -> Icons.Filled.Numbers
        SettingsPage.defaults -> Icons.Filled.Description
        SettingsPage.taxRates -> Icons.Filled.Percent
        SettingsPage.unlock -> Icons.Filled.AllInclusive
        SettingsPage.backup -> Icons.Filled.Save
        SettingsPage.about -> Icons.Filled.Info
    }

/** The Settings tab: the pages beside the selected page on wide windows, pushed on phones. iOS: `SettingsSection`. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSection(session: Session) {
    val router = session.router.settings
    val status by remember(session) { session.container.backup.observeStatus() }.collectAsStateWithLifecycle(null)
    val backupDue = status?.isDue(session.today) ?: false
    // Tax rates appear only for businesses that define their own (GENERIC).
    val pages = SettingsPage.entries.filter { it != SettingsPage.taxRates || session.config.ratesFrom == RatesSource.business }
    ListDetail(
        hasSelection = router.selection != null,
        onCloseDetail = { router.selection = null },
        list = {
            Scaffold(containerColor = Theme.colors.background,
                topBar = { TopAppBar({ Text("Settings") }, colors = TopAppBarDefaults.topAppBarColors(containerColor = Theme.colors.background)) }) { padding ->
                LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                    items(pages) { page ->
                        ListItem(
                            headlineContent = { Text(page.title) },
                            leadingContent = { Icon(page.icon, null, tint = Theme.colors.brand) },
                            trailingContent = { if (page == SettingsPage.backup && backupDue) Badge { Text("Due") } },
                            colors = ListItemDefaults.colors(containerColor = if (router.selection == page) Theme.colors.brand.copy(alpha = 0.12f) else Theme.colors.background),
                            modifier = Modifier.clickable { router.selection = page }.semantics { selected = router.selection == page }.testTag("settings-${page.name}"),
                        )
                    }
                }
            }
        },
        detail = { twoPane -> router.selection?.let { SettingsPageScreen(session, it, showsBack = !twoPane) } },
        empty = { EmptyState("Settings", Icons.Filled.Settings, "Choose what to change.") },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsPageScreen(session: Session, page: SettingsPage, showsBack: Boolean) {
    val profile = if (page == SettingsPage.profile || page == SettingsPage.defaults) {
        session.retained("profile-${page.name}") { BusinessProfileViewModel(session) }
    } else null
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(profile?.didSave) { if (profile?.didSave == true) haptics.performHapticFeedback(HapticFeedbackType.Confirm) }
    Scaffold(
        containerColor = Theme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(page.title) },
                navigationIcon = { if (showsBack) IconButton({ session.router.settings.selection = null }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                actions = {
                    if (profile != null) {
                        if (profile.hasChanges) TextButton(profile::discardChanges) { Text("Revert") }
                        TextButton(profile::save, enabled = profile.hasChanges && !profile.isSaving, modifier = Modifier.testTag("profileSave")) { Text("Save") }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Theme.colors.background),
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding)) {
            when (page) {
                SettingsPage.profile -> BusinessProfilePage(session, profile!!)
                SettingsPage.defaults -> DefaultsPage(profile!!)
                SettingsPage.images -> BusinessImagesPage(session)
                SettingsPage.numbering -> NumberingPage(session)
                SettingsPage.taxRates -> TaxRatesPage(session)
                SettingsPage.unlock -> DetailColumn { UnlockPage(session) }
                SettingsPage.backup -> {
                    val context = LocalContext.current
                    val model = session.retained("backup") {
                        BackupViewModel(session.container, session.deviceID, session.scope, AppContainer.appVersion(context)) {
                            session.pdfLibrary.forgetAll()
                            session.reloadApp()
                        }.also { it.observe() }
                    }
                    BackupPage(session, model)
                }
                SettingsPage.about -> AboutPage(session)
            }
        }
    }
    profile?.let { ErrorAlert(it.errorMessage, { it.errorMessage = null }) }
}

@Composable
private fun BusinessProfilePage(session: Session, model: BusinessProfileViewModel) {
    DetailColumn {
        if (model.attemptedSave && model.issues.isNotEmpty()) IssueText("Check the highlighted fields.")
        FormSection(footer = "Country and currency are fixed once your business is set up.") {
            LabeledValue("Country", session.countryName(session.business.countryCode))
            LabeledValue("Currency", session.business.homeCurrency.rawValue)
        }
        RegistrationSections(model.draft, model::update, model.rules, session.formatter, model::visibleIssue, asksForFirstRate = false)
        BusinessDetailsSections(model.draft, model::update, model.rules, model::visibleIssue, model.taxIDFeedback)
        if (model.rules.showsLUT(model.draft)) {
            val draft = model.draft
            FormSection("Exports under LUT", "Needed to invoice exports without IGST. Printed on those invoices.") {
                FormTextField("LUT ARN (optional)", draft.lutReference, { model.update(draft.copy(lutReference = it)) }, prompt = "AD2903260123456",
                    capitalization = KeyboardCapitalization.Characters, autocorrect = false)
                SwitchRow("Valid until", draft.lutValidUntil != null, { on ->
                    model.update(draft.copy(lutValidUntil = if (on) session.today.plusDays(365) else null))
                })
                draft.lutValidUntil?.let { DateField("Valid until", it, { date -> model.update(draft.copy(lutValidUntil = date)) }) }
            }
        }
        BankSections(model.draft, model::update, model.rules, model::visibleIssue)
    }
}

@Composable
private fun DefaultsPage(model: BusinessProfileViewModel) {
    val draft = model.draft
    DetailColumn {
        FormSection(footer = "New invoices are due this many days after their date.") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Payment due", Modifier.weight(1f))
                IconButton({ model.update(draft.copy(paymentTermsDays = (draft.paymentTermsDays - 1).coerceIn(BusinessRules.paymentTermsRange))) },
                    enabled = draft.paymentTermsDays > BusinessRules.paymentTermsRange.first) { Icon(Icons.Filled.Remove, "Fewer days") }
                Text(if (draft.paymentTermsDays == 0) "On receipt" else "${draft.paymentTermsDays} days", Modifier.testTag("paymentTerms"))
                IconButton({ model.update(draft.copy(paymentTermsDays = (draft.paymentTermsDays + 1).coerceIn(BusinessRules.paymentTermsRange))) },
                    enabled = draft.paymentTermsDays < BusinessRules.paymentTermsRange.last) { Icon(Icons.Filled.Add, "More days") }
            }
        }
        FormSection("Overdue reminders", "A reminder on this device for unpaid invoices. You can change it on each invoice.") {
            PickerField("Remind me", draft.reminderDaysAfterDue, listOf(0, 1, 3, 7, 14, 30).map { it to if (it == 0) "On the due date" else "$it days after the due date" },
                { model.update(draft.copy(reminderDaysAfterDue = it)) }, none = "Never", tag = "defaultReminder")
        }
        FormSection("Invoice design") {
            PickerField("Template", draft.templateId, TemplateID.known.map { it to it.rawValue.replaceFirstChar(Char::uppercase) },
                { it?.let { t -> model.update(draft.copy(templateId = t)) } })
            AccentPicker(draft.accentColor) { model.update(draft.copy(accentColor = it)) }
        }
        FormSection("Notes printed on new invoices") {
            FormTextField("Notes", draft.defaultNotes, { model.update(draft.copy(defaultNotes = it)) }, prompt = "Thank you for your business.", multiline = true)
            FormTextField("Terms", draft.defaultTerms, { model.update(draft.copy(defaultTerms = it)) },
                prompt = "Payment by bank transfer within the due date.", multiline = true)
        }
    }
}

/** The accent colour presets from the design tokens. */
@Composable
private fun AccentPicker(selection: String?, onSelect: (String?) -> Unit) {
    val names = mapOf("#1F6FEB" to "Blue", "#0F766E" to "Teal", "#7C3AED" to "Violet", "#B91C1C" to "Red", "#C2410C" to "Orange", "#111827" to "Charcoal")
    val presets = Theme.accentPresets
    Column(verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
        Text("Accent colour")
        Row(horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
            for (hex in presets) {
                val isSelected = (selection ?: presets.firstOrNull()) == hex
                Box(
                    Modifier.size(Theme.Layout.minTouchTarget).clickable { onSelect(if (hex == presets.firstOrNull()) null else hex) }
                        .semantics { contentDescription = names[hex] ?: hex; selected = isSelected },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.size(32.dp).background(hexColor(hex), CircleShape)
                        .then(if (isSelected) Modifier.border(3.dp, Theme.colors.textPrimary, CircleShape) else Modifier))
                }
            }
        }
    }
}

@Composable
private fun BusinessImagesPage(session: Session) {
    val model = remember(session) { BusinessImagesViewModel(session) }
    val context = LocalContext.current
    LaunchedEffect(model) { model.load() }
    DetailColumn {
        ImagesFormSections(
            model.logo, model.signature, model.isBusy,
            if (session.config.family == "IN") "Tax invoices need the signature of the supplier or an authorised person (GST Rule 46)." else null,
            onPickLogo = { model.setLogo(it, context.contentResolver) }, onRemoveLogo = model::removeLogo,
            onSaveSignature = { model.setSignature(it) }, onRemoveSignature = { model.setSignature(null) },
        )
    }
    ErrorAlert(model.errorMessage, { model.errorMessage = null })
}

@Composable
private fun NumberingPage(session: Session) {
    val model = session.retained("numbering") { NumberingSettingsViewModel(session) }
    val series by remember(session.business.id) { session.container.numberingSeries.observeSeries(session.business.id) }.collectAsStateWithLifecycle(emptyList())
    val scope = rememberCoroutineScope()
    DetailColumn {
        for (entry in series) {
            FormSection(entry.label) {
                LabeledValue("Next number", model.nextNumber(entry))
                LabeledValue("Pattern", entry.pattern)
                LabeledValue("Starts again", entry.reset.label)
                if (model.rules.isEditable(entry)) {
                    NavRow("Change numbering", { model.edit(entry) }, tag = "editSeries-${entry.docType.rawValue}")
                } else {
                    Text("Numbered on another device. Only that device changes it.", style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
                }
            }
        }
        Text("Numbers are given when a document is issued, never to drafts, so there are no gaps.",
            style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary, modifier = Modifier.padding(Theme.Space.l))
    }
    val draft = model.draft
    if (draft != null) {
        val config = session.config
        fun message(field: NumberingSeriesField, name: String) = model.visibleIssue(field)?.let { IssueMessages.text(it, name, maxLength = config.numbering.maxLength) }
        var help = "{seq:4} is the sequence (0001), {fy} the financial year (26-27), {yyyy}, {yy} and {mm} the date."
        config.numbering.maxLength?.let { help += " Numbers can be up to $it characters: letters, digits, / and -." }
        help += " Moving from another tool? Set the next number to continue where you left off."
        EditorSheet("Change numbering", onCancel = model::cancelEditing, onSave = { scope.launch { model.saveEditing() } }, saveTag = "seriesSave") {
            FormSection(footer = "Preview for a document issued today.") { LabeledValue("Next number", model.preview ?: "—", emphasized = true, valueTag = "seriesPreview") }
            FormSection(footer = help) {
                FormTextField("Name", draft.label, { model.draft = draft.copy(label = it) }, issue = message(NumberingSeriesField.Label, "name"))
                FormTextField("Pattern", draft.pattern, { model.draft = draft.copy(pattern = it) }, prompt = "INV/{fy}/{seq:4}",
                    issue = message(NumberingSeriesField.Pattern, "pattern"), capitalization = KeyboardCapitalization.Characters, autocorrect = false, tag = "seriesPattern")
                PickerField("Start again at 1", draft.reset, NumberingReset.known.map { it to it.label }, { it?.let { r -> model.draft = draft.copy(reset = r) } })
                FormTextField("Next number in this period", draft.nextNumberText, { model.draft = draft.copy(nextNumberText = it) },
                    issue = message(NumberingSeriesField.NextNumber, "next number"), keyboard = KeyboardType.Number)
            }
        }
    }
    ErrorAlert(model.errorMessage, { model.errorMessage = null })
}

@Composable
private fun TaxRatesPage(session: Session) {
    val model = session.retained("taxRates") { TaxRatesViewModel(session) }
    val scope = rememberCoroutineScope()
    DetailColumn {
        FormSection(footer = "\"No tax\" is always available. A rate used by an item can't be removed.") {
            for (rate in model.rates) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (rate.id == CustomRates.noTax.id) {
                        Text(rate.label, Modifier.weight(1f).padding(vertical = Theme.Space.s))
                    } else {
                        Box(Modifier.weight(1f)) { NavRow(rate.label, { model.edit(rate) }) }
                        IconButton({ model.remove(rate) }) { Icon(Icons.Filled.Delete, "Remove ${rate.label}", tint = Theme.colors.danger) }
                    }
                }
                HorizontalDivider(color = Theme.colors.border.copy(alpha = 0.5f))
            }
            NavRow("Add rate", model::startNew, icon = Icons.Filled.Add, tag = "addRate")
        }
    }
    val draft = model.draft
    if (draft != null) {
        fun message(field: CustomRateField, name: String) = model.visibleIssue(field)?.let { IssueMessages.text(it, name) }
        EditorSheet(if (model.editingID == null) "New rate" else "Edit rate", onCancel = model::cancelEditing, onSave = { scope.launch { model.saveEditing() } }) {
            FormSection {
                FormTextField("Tax name", draft.name, { model.draft = draft.copy(name = it) }, prompt = "Sales tax",
                    issue = message(CustomRateField.Name, "tax name"), capitalization = KeyboardCapitalization.Words)
                FormTextField("Rate (%)", draft.percent, { model.draft = draft.copy(percent = it) }, prompt = "8.875",
                    issue = message(CustomRateField.Percent, "rate"), keyboard = KeyboardType.Decimal)
            }
            FormSection(footer = "Some places charge two taxes on the same line, sometimes one on top of the other.") {
                SwitchRow("Add a second tax", draft.hasSecondComponent, { model.draft = draft.copy(hasSecondComponent = it) })
                if (draft.hasSecondComponent) {
                    FormTextField("Second tax name", draft.secondName, { model.draft = draft.copy(secondName = it) },
                        issue = message(CustomRateField.SecondName, "tax name"), capitalization = KeyboardCapitalization.Words)
                    FormTextField("Second rate (%)", draft.secondPercent, { model.draft = draft.copy(secondPercent = it) },
                        issue = message(CustomRateField.SecondPercent, "rate"), keyboard = KeyboardType.Decimal)
                    SwitchRow("Charged on top of the first tax (compound)", draft.secondIsCompound, { model.draft = draft.copy(secondIsCompound = it) })
                }
            }
        }
    }
    ErrorAlert(model.errorMessage, { model.errorMessage = null })
}

@Composable
private fun AboutPage(session: Session) {
    val context = LocalContext.current
    val reports = remember { Diagnostics.reports(context) }
    DetailColumn {
        FormSection("App") {
            LabeledValue("Version", AppContainer.appVersion(context))
            LabeledValue("Your data", "On this device")
        }
        FormSection("${session.config.labels.taxName} rules", "Tax rules are built into the app and updated with it. Check invoices with your accountant.") {
            LabeledValue("Tax rules", session.config.ref)
            LabeledValue("Status", if (session.config.reviewStatus == "reviewed") "Professionally reviewed" else "Awaiting professional review")
        }
        FormSection("This device") {
            Text(session.deviceID, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
        }
        FormSection("Diagnostics", "Crash and \"not responding\" reports from Android. They stay on this device unless you share them, for example with support.") {
            LabeledValue("Reports", reports.size.toString())
            if (reports.isNotEmpty()) {
                NavRow("Share diagnostic reports…", {
                    val file = File(context.cacheDir, "diagnostics.txt").also { it.writeText(reports.joinToString("\n\n")) }
                    SystemSheets.shareFile(context, file, "text/plain", "InvoiceBuilder diagnostics")
                })
            }
        }
    }
}

/**
 * Why the app's process ended recently (≈ MetricKit diagnostics on iOS): crashes, native crashes and ANRs from
 * `ActivityManager.getHistoricalProcessExitReasons` (Android 11+), newest 20. Nothing leaves the device unless shared.
 */
object Diagnostics {
    fun reports(context: Context): List<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val manager = context.getSystemService(ActivityManager::class.java) ?: return emptyList()
        val interesting = setOf(ApplicationExitInfo.REASON_CRASH, ApplicationExitInfo.REASON_CRASH_NATIVE, ApplicationExitInfo.REASON_ANR)
        return runCatching {
            manager.getHistoricalProcessExitReasons(context.packageName, 0, 20).filter { it.reason in interesting }.map { info ->
                val kind = when (info.reason) {
                    ApplicationExitInfo.REASON_ANR -> "Not responding"
                    ApplicationExitInfo.REASON_CRASH_NATIVE -> "Native crash"
                    else -> "Crash"
                }
                "$kind at ${java.time.Instant.ofEpochMilli(info.timestamp)}: ${info.description ?: ""}"
            }
        }.getOrDefault(emptyList())
    }
}
