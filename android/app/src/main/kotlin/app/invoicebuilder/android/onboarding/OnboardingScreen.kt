package app.invoicebuilder.android.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import app.invoicebuilder.android.app.SampleData
import app.invoicebuilder.android.backup.rememberBackupFlows
import app.invoicebuilder.android.common.BankSections
import app.invoicebuilder.android.common.BusinessDetailsSections
import app.invoicebuilder.android.common.ImagesFormSections
import app.invoicebuilder.android.common.RegistrationSections
import app.invoicebuilder.core.designsystem.ChoiceRow
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.FormTextField
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.designsystem.IssueText
import app.invoicebuilder.core.designsystem.NavRow
import app.invoicebuilder.core.designsystem.PickerField
import app.invoicebuilder.core.designsystem.PrimaryButton
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.designsystem.readableWidth
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.setup.BusinessField
import app.invoicebuilder.core.domain.setup.OnboardingStep

/**
 * Onboarding: one guided column on phones; a step list beside the form on wide windows (wireframe 1). The state
 * lives in the view model, so folding, rotating or resizing mid-way keeps every answer. iOS: `OnboardingView`.
 */
@Composable
fun OnboardingScreen(model: OnboardingViewModel) {
    val flows = rememberBackupFlows(model.backup)
    BackHandler(enabled = model.step != OnboardingStep.country) { model.back() }
    model.errorMessage?.let {
        AlertDialog({ model.errorMessage = null }, title = { Text("Something went wrong") }, text = { Text(it) },
            confirmButton = { TextButton({ model.errorMessage = null }) { Text("OK") } })
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(Theme.colors.background)) {
        if (maxWidth >= Theme.Layout.regularWidthBreakpoint) {
            Row(Modifier.fillMaxSize()) {
                StepList(model, Modifier.width(260.dp).fillMaxHeight())
                Box(Modifier.weight(1f)) { StepScreen(model, showsProgress = false, onRestore = flows.pickFile) }
            }
        } else {
            StepScreen(model, showsProgress = true, onRestore = flows.pickFile)
        }
    }
}

/** Wide windows: the five steps; finished ones are ticked and can be revisited. */
@Composable
private fun StepList(model: OnboardingViewModel, modifier: Modifier) {
    Surface(modifier, color = Theme.colors.surface) {
        Column(Modifier.padding(top = Theme.Space.xl)) {
            Text("Set up", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(Theme.Space.l))
            for (step in OnboardingStep.entries) {
                val enabled = model.canVisit(step)
                ListItem(
                    headlineContent = { Text(model.title(step), color = if (enabled) Theme.colors.textPrimary else Theme.colors.textTertiary) },
                    trailingContent = { if (step < model.step) Icon(Icons.Filled.CheckCircle, "Done", tint = Theme.colors.success) },
                    colors = ListItemDefaults.colors(containerColor = if (step == model.step) Theme.colors.brand.copy(alpha = 0.12f) else Theme.colors.surface),
                    modifier = Modifier.clickable(enabled = enabled) { model.go(step) },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StepScreen(model: OnboardingViewModel, showsProgress: Boolean, onRestore: () -> Unit) {
    val context = LocalContext.current
    Scaffold(
        containerColor = Theme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(model.title(model.step)) },
                navigationIcon = {
                    if (model.step != OnboardingStep.country) IconButton(model::back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
                },
            )
        },
        bottomBar = {
            Surface(color = Theme.colors.surface, tonalElevation = 2.dp) {
                Box(Modifier.fillMaxWidth().imePadding(), contentAlignment = Alignment.Center) {
                    Column(Modifier.readableWidth().padding(Theme.Space.l), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                        if (model.isLastStep) {
                            PrimaryButton("Finish", model::finish, isBusy = model.isFinishing, tag = "onboarding.finish")
                            Text("You can change all of this later in Settings.", style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
                        } else {
                            PrimaryButton("Continue", model::continueTapped, tag = "onboarding.continue")
                        }
                    }
                }
            }
        },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), horizontalAlignment = Alignment.CenterHorizontally) {
            item {
                Column(Modifier.readableWidth().padding(horizontal = Theme.Space.l)) {
                    if (showsProgress) {
                        Text("Step ${model.stepNumber} of ${model.stepCount}", style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
                        LinearProgressIndicator({ model.stepNumber.toFloat() / model.stepCount }, Modifier.fillMaxWidth().padding(vertical = Theme.Space.s))
                    }
                    val rules = model.rules
                    when (model.step) {
                        OnboardingStep.country -> CountryStepHeader(model, onRestore)
                        OnboardingStep.registration -> if (rules != null) RegistrationSections(model.draft, model::update, rules,
                            SpecFormatter(model.container.reference.currencies), model::visibleIssue)
                        OnboardingStep.business -> if (rules != null) BusinessDetailsSections(model.draft, model::update, rules, model::visibleIssue, model.taxIDFeedback)
                        OnboardingStep.bank -> if (rules != null) BankSections(model.draft, model::update, rules, model::visibleIssue)
                        OnboardingStep.images -> ImagesFormSections(
                            model.logo?.data, model.signature?.data, model.isProcessingImage,
                            if (rules?.isIndia == true) "Tax invoices need the signature of the supplier or an authorised person (GST Rule 46)." else null,
                            onPickLogo = { model.setLogo(it, context.contentResolver) }, onRemoveLogo = model::removeLogo,
                            onSaveSignature = { model.signature = it }, onRemoveSignature = { model.signature = null },
                        )
                    }
                }
            }
            if (model.step == OnboardingStep.country) {
                items(model.countries, key = { it.code }) { country ->
                    Column(Modifier.readableWidth().padding(horizontal = Theme.Space.xl)) {
                        ChoiceRow(country.name, model.draft.countryCode == country.code, { model.selectCountry(country.code) }, tag = "country-${country.code}")
                        HorizontalDivider(color = Theme.colors.border.copy(alpha = 0.5f))
                    }
                }
            }
        }
    }
}

/** Step 1: where the business is registered. India and the UK first, then the demo, restore and every country. */
@Composable
private fun CountryStepHeader(model: OnboardingViewModel, onRestore: () -> Unit) {
    model.visibleIssue(BusinessField.Country)?.let { IssueText(IssueMessages.text(it, "country")) }
    if (model.rules?.asksForHomeCurrency == true) {
        FormSection(footer = "Your invoices total in this currency. You can still bill clients in other currencies.") {
            PickerField("Home currency", model.draft.homeCurrency, model.currencies.map { it.code to "${it.name} (${it.code.rawValue})" },
                { model.update(model.draft.copy(homeCurrency = it)) }, none = "Choose",
                issue = model.visibleIssue(BusinessField.HomeCurrency)?.let { IssueMessages.text(it, "home currency") }, searchable = true)
        }
    }
    FormSection("Suggested") {
        for (country in model.suggestedCountries) {
            ChoiceRow(country.name, model.draft.countryCode == country.code, { model.selectCountry(country.code) }, tag = "suggested-${country.code}")
        }
    }
    FormSection("Just looking?", "See invoices, quotes and payments in a sample business. Nothing you do there is saved.") {
        NavRow("Try it with a sample Indian business", { model.tryDemo(SampleData.Country.india) }, tag = "onboarding.demoIN")
        NavRow("Try it with a sample UK business", { model.tryDemo(SampleData.Country.uk) }, tag = "onboarding.demoGB")
    }
    FormSection("Moving from another device?", "Start from an InvoiceBuilder backup file instead of setting up again.") {
        NavRow("Restore from a backup…", onRestore, tag = "onboarding.restore")
    }
    FormSection("All countries", "India and the UK get their GST and VAT rules built in. Elsewhere you set your own tax rates.") {
        FormTextField("Search countries", model.countrySearch, { model.countrySearch = it }, capitalization = KeyboardCapitalization.Words, autocorrect = false)
    }
}
