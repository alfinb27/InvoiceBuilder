package app.invoicebuilder.android.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.invoicebuilder.android.backup.rememberBackupFlows
import app.invoicebuilder.android.common.BankSections
import app.invoicebuilder.android.common.BusinessDetailsSections
import app.invoicebuilder.android.common.ImagesFormSections
import app.invoicebuilder.android.common.TurnoverText
import app.invoicebuilder.android.common.registrationHelp
import app.invoicebuilder.core.designsystem.BoxedTextField
import app.invoicebuilder.core.designsystem.ChipFlow
import app.invoicebuilder.core.designsystem.ChoiceChip
import app.invoicebuilder.core.designsystem.FormTextField
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.designsystem.IssueText
import app.invoicebuilder.core.designsystem.MutedDivider
import app.invoicebuilder.core.designsystem.PickerField
import app.invoicebuilder.core.designsystem.PrimaryButton
import app.invoicebuilder.core.designsystem.ScreenHeader
import app.invoicebuilder.core.designsystem.SelectableCard
import app.invoicebuilder.core.designsystem.SteppedProgress
import app.invoicebuilder.core.designsystem.SurfaceCard
import app.invoicebuilder.core.designsystem.TextLinkButton
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.designsystem.TipCallout
import app.invoicebuilder.core.designsystem.readableWidth
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.setup.BusinessField
import app.invoicebuilder.core.domain.setup.BusinessRules
import app.invoicebuilder.core.domain.setup.OnboardingStage
import app.invoicebuilder.core.domain.tax.TaxRegistration

/**
 * Onboarding (`spec/setup.md` §3, ADR-0020): the Welcome screen, then three stages. One guided column on phones; a
 * stage list beside the form on wide windows. The state lives in the view model, so folding, rotating or resizing
 * mid-way keeps every answer. iOS: `OnboardingView`.
 */
@Composable
fun OnboardingScreen(model: OnboardingViewModel) {
    val flows = rememberBackupFlows(model.backup)
    BackHandler(enabled = !model.showsWelcome) { model.back() }
    model.errorMessage?.let {
        AlertDialog({ model.errorMessage = null }, title = { Text("Something went wrong") }, text = { Text(it) },
            confirmButton = { TextButton({ model.errorMessage = null }) { Text("OK") } })
    }
    if (model.showsWelcome) {
        WelcomeScreen(model, onRestore = flows.pickFile)
        return
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(Theme.colors.background)) {
        if (maxWidth >= Theme.Layout.regularWidthBreakpoint) {
            Row(Modifier.fillMaxSize()) {
                StageList(model, Modifier.width(260.dp).fillMaxHeight())
                Box(Modifier.weight(1f)) { StageScreen(model, showsProgress = false) }
            }
        } else {
            StageScreen(model, showsProgress = true)
        }
    }
}

/** Wide windows: the three stages; finished ones are ticked and can be revisited. */
@Composable
private fun StageList(model: OnboardingViewModel, modifier: Modifier) {
    Surface(modifier, color = Theme.colors.surface) {
        Column(Modifier.padding(top = Theme.Space.xl)) {
            Text("Set up", style = Theme.Fonts.title3, modifier = Modifier.padding(Theme.Space.l))
            for (stage in OnboardingStage.entries) {
                val enabled = model.canVisit(stage)
                ListItem(
                    headlineContent = { Text(model.title(stage), color = if (enabled) Theme.colors.textPrimary else Theme.colors.textSecondary) },
                    trailingContent = { if (stage < model.stage) Icon(Icons.Filled.CheckCircle, "Done", tint = Theme.colors.brand) },
                    colors = ListItemDefaults.colors(containerColor = if (stage == model.stage) Theme.colors.brandTint else Theme.colors.surface),
                    modifier = Modifier.clickable(enabled = enabled) { model.go(stage) },
                )
            }
        }
    }
}

/** The current stage with Back, "Step n of 3", and Continue (Finish and Skip for now on the last stage). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StageScreen(model: OnboardingViewModel, showsProgress: Boolean) {
    val context = LocalContext.current
    var showsCountries by rememberSaveable { mutableStateOf(false) }
    Scaffold(
        containerColor = Theme.colors.background,
        topBar = {
            TopAppBar(
                title = {
                    Text("Step ${model.stageNumber} of ${model.stageCount}", style = Theme.Fonts.subhead.copy(fontWeight = FontWeight.SemiBold),
                        color = Theme.colors.textSecondary, modifier = Modifier.fillMaxWidth().semantics { heading() },
                        textAlign = TextAlign.Center)
                },
                navigationIcon = {
                    IconButton(model::back, Modifier.testTag("onboarding.back")) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
                },
                actions = { Spacer(Modifier.width(48.dp)) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Theme.colors.background),
            )
        },
        bottomBar = {
            Box(Modifier.fillMaxWidth().background(Theme.colors.background).imePadding(), contentAlignment = Alignment.Center) {
                Column(Modifier.readableWidth().padding(horizontal = Theme.Layout.screenGutter, vertical = Theme.Space.m),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Theme.Space.xs)) {
                    if (model.isLastStage) {
                        PrimaryButton("Finish", model::finish, isBusy = model.isFinishing, tag = "onboarding.finish")
                        TextLinkButton("Skip for now", model::skipAndFinish, tag = "onboarding.skip", enabled = !model.isFinishing)
                    } else {
                        PrimaryButton("Continue", model::continueTapped, tag = "onboarding.continue")
                        if (model.stage == OnboardingStage.whereYouWork) {
                            Text("Bank details and logo are optional. Skip them for now if you like.", style = Theme.Fonts.footnote,
                                color = Theme.colors.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Theme.Space.xs))
                        }
                    }
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
            Column(
                Modifier.readableWidth().fillMaxWidth().verticalScroll(rememberScrollState())
                    .padding(horizontal = Theme.Layout.screenGutter, vertical = Theme.Space.l),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                if (showsProgress) SteppedProgress(OnboardingStage.entries.map(model::title), model.stage.ordinal)
                val rules = model.rules
                when (model.stage) {
                    OnboardingStage.whereYouWork -> WhereYouWork(model, onChooseCountry = { showsCountries = true })
                    OnboardingStage.yourBusiness -> {
                        ScreenHeader("Tell us about your business", subtitle = "This is what your clients see at the top of every invoice.")
                        if (rules != null) BusinessDetailsSections(model.draft, model::update, rules, model::visibleIssue, model.taxIDFeedback)
                    }
                    OnboardingStage.gettingPaid -> {
                        ScreenHeader("How do clients pay you?", subtitle = "Printed on your invoices so clients know where to pay. All optional.")
                        if (rules != null) BankSections(model.draft, model::update, rules, model::visibleIssue)
                        ImagesFormSections(
                            model.logo?.data, model.signature?.data, model.isProcessingImage,
                            if (rules?.isIndia == true) "Tax invoices need the signature of the supplier or an authorised person (GST Rule 46)." else null,
                            onPickLogo = { model.setLogo(it, context.contentResolver) }, onRemoveLogo = model::removeLogo,
                            onSaveSignature = { model.signature = it }, onRemoveSignature = { model.signature = null },
                        )
                    }
                }
            }
        }
    }
    if (showsCountries) CountryPickerSheet(model) { showsCountries = false }
}

/** Stage 1: country as three cards; the registration question appears below once a country is chosen. */
@Composable
private fun WhereYouWork(model: OnboardingViewModel, onChooseCountry: () -> Unit) {
    ScreenHeader("Where is your business based?",
        subtitle = "This decides which tax goes on your invoices, so you never have to work it out yourself.")
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SelectableCard("India", model.countryCard == "IN", { model.selectCountry("IN") }, hint = "GST invoices in ₹", badge = "IN",
            tag = "country-IN")
        SelectableCard("United Kingdom", model.countryCard == "GB", { model.selectCountry("GB") }, hint = "VAT invoices in £",
            badge = "UK", tag = "country-GB")
        SelectableCard("Somewhere else", model.countryCard == "other", model::pickOtherCountry,
            hint = "Choose your country and currency", icon = Icons.Filled.Add, tag = "country-other")
    }
    model.visibleIssue(BusinessField.Country)?.let { IssueText(IssueMessages.text(it, "country")) }
    if (model.countryCard == "other") {
        SurfaceCard {
            Row(Modifier.fillMaxWidth().heightIn(min = Theme.Layout.minTouchTarget).clickable(onClick = onChooseCountry)
                .testTag("onboarding.chooseCountry"), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Country", style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
                    Text(model.countryName ?: "Choose", style = Theme.Fonts.rowTitle, color = Theme.colors.textPrimary)
                }
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Theme.colors.textTertiary)
            }
            if (model.rules?.asksForHomeCurrency == true) {
                MutedDivider()
                PickerField("Currency", model.draft.homeCurrency, model.currencies.map { it.code to "${it.name} (${it.code.rawValue})" },
                    { model.update(model.draft.copy(homeCurrency = it)) }, none = "Choose",
                    issue = model.visibleIssue(BusinessField.HomeCurrency)?.let { IssueMessages.text(it, "home currency") }, searchable = true)
                Text("Your invoices total in this currency. You can still bill clients in other currencies.",
                    style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
            }
        }
    }
    model.rules?.let { RegistrationCard(model, it) }
}

/** "Are you registered for GST?" as chips, India's turnover band, or (elsewhere) the first tax rate. */
@Composable
private fun RegistrationCard(model: OnboardingViewModel, rules: BusinessRules) {
    val taxName = rules.config.labels.taxName
    val draft = model.draft
    SurfaceCard {
        Text("Are you registered for $taxName?", style = Theme.Fonts.headline, color = Theme.colors.textPrimary,
            modifier = Modifier.semantics { heading() })
        ChipFlow {
            for (registration in rules.config.registrations) {
                ChoiceChip(chipLabel(rules.config.family, registration), draft.taxRegistration == registration.id,
                    { model.update(draft.copy(taxRegistration = registration.id)) }, tag = "registration.${registration.id}")
            }
        }
        draft.taxRegistration?.let {
            Text(registrationHelp(rules.config.family, it), style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
        }
        model.visibleIssue(BusinessField.Registration)?.let { IssueText(IssueMessages.text(it, "registration type")) }
        if (rules.showsTurnoverTier(draft)) {
            val formatter = SpecFormatter(model.container.reference.currencies)
            Text("Turnover in the last financial year", style = Theme.Fonts.subhead.copy(fontWeight = FontWeight.Bold),
                color = Theme.colors.textPrimary)
            ChipFlow {
                rules.turnoverTiers.indices.forEach { index ->
                    ChoiceChip(TurnoverText.label(rules, formatter, index), draft.turnoverTier == index,
                        { model.update(draft.copy(turnoverTier = index)) })
                }
            }
            Text(TurnoverText.footer(rules, draft.turnoverTier), style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
        }
        if (rules.asksForFirstTaxRate(draft)) {
            BoxedTextField("Tax name", draft.genericTaxName, { model.update(draft.copy(genericTaxName = it)) }, prompt = "Sales tax",
                issue = model.visibleIssue(BusinessField.GenericTaxName)?.let { IssueMessages.text(it, "tax name") })
            BoxedTextField("Rate (%)", draft.genericTaxPercent, { model.update(draft.copy(genericTaxPercent = it)) }, prompt = "8.875",
                issue = model.visibleIssue(BusinessField.GenericTaxPercent)?.let { IssueMessages.text(it, "rate") },
                keyboard = KeyboardType.Decimal)
            Text("You can add more rates, or a second tax, later in Settings.", style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
        }
        TipCallout("Not sure? Pick “Not registered”. You can change it later in Settings.")
    }
}

/** Everyday answers to "Are you registered?" (`design.md` §6.2); other configs use their own labels. */
private fun chipLabel(family: String, registration: TaxRegistration): String = when ("$family.${registration.id}") {
    "IN.regular" -> "Yes, regular GST"
    "IN.composition" -> "Yes, composition"
    "IN.unregistered", "GB.notRegistered", "GENERIC.notRegistered" -> "Not registered"
    "GB.vatRegistered" -> "Yes, VAT registered"
    "GENERIC.registered" -> "Yes"
    else -> registration.label
}

/** "Somewhere else": every country, searchable. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CountryPickerSheet(model: OnboardingViewModel, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismiss, containerColor = Theme.colors.surface) {
        Column(Modifier.padding(horizontal = Theme.Layout.screenGutter)) {
            Text("Country", style = Theme.Fonts.title3, modifier = Modifier.padding(bottom = Theme.Space.m))
            FormTextField("Search countries", model.countrySearch, { model.countrySearch = it },
                capitalization = KeyboardCapitalization.Words, autocorrect = false)
        }
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 520.dp)) {
            items(model.countries, key = { it.code }) { country ->
                Row(Modifier.fillMaxWidth().heightIn(min = Theme.Layout.minTouchTarget + 4.dp)
                    .clickable { model.selectCountry(country.code); onDismiss() }.testTag("country-${country.code}")
                    .padding(horizontal = Theme.Layout.screenGutter), verticalAlignment = Alignment.CenterVertically) {
                    Text(country.name, Modifier.weight(1f), style = Theme.Fonts.body, color = Theme.colors.textPrimary)
                    if (model.draft.countryCode == country.code) Icon(Icons.Filled.Check, "Selected", tint = Theme.colors.brand)
                }
                MutedDivider(Modifier.padding(horizontal = Theme.Layout.screenGutter))
            }
        }
        Spacer(Modifier.size(Theme.Space.xl))
    }
}
