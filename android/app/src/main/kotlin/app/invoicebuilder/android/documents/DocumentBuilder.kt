package app.invoicebuilder.android.documents

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.billing.PaywallDialog
import app.invoicebuilder.android.common.ConfirmDialog
import app.invoicebuilder.core.designsystem.Avatar
import app.invoicebuilder.core.designsystem.Badge
import app.invoicebuilder.core.designsystem.ChipFlow
import app.invoicebuilder.core.designsystem.ChoiceChip
import app.invoicebuilder.core.designsystem.DateField
import app.invoicebuilder.core.designsystem.FormTextField
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.designsystem.IssueText
import app.invoicebuilder.core.designsystem.MutedDivider
import app.invoicebuilder.core.designsystem.NumberedCard
import app.invoicebuilder.core.designsystem.Overline
import app.invoicebuilder.core.designsystem.PickerField
import app.invoicebuilder.core.designsystem.PrimaryButton
import app.invoicebuilder.core.designsystem.SecondaryButton
import app.invoicebuilder.core.designsystem.SegmentedChoice
import app.invoicebuilder.core.designsystem.SwitchRow
import app.invoicebuilder.core.designsystem.TextLinkButton
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.designsystem.readableWidth
import app.invoicebuilder.core.domain.documents.IssueProblem
import app.invoicebuilder.core.domain.documents.LineItem
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.ComputedDocument
import app.invoicebuilder.core.domain.tax.ComputedLine
import app.invoicebuilder.core.domain.tax.Discount
import app.invoicebuilder.core.domain.tax.EngineIssue
import java.time.LocalDate

private enum class BuilderPane(val label: String) { preview("Preview"), totals("Totals") }

/**
 * The guided builder (`docs/design/design.md` §6.4): who, what and when as three numbered cards, everything else
 * under More options, and the totals with Review & send pinned at the bottom. On wide windows the live PDF preview
 * sits beside it. iOS: `DocumentBuilderView`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DocumentBuilder(model: DocumentViewModel, session: Session, showsBack: Boolean, onBack: () -> Unit) {
    var choosingClient by rememberSaveable { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }
    var showsBreakdown by rememberSaveable { mutableStateOf(false) }
    var pane by rememberSaveable { mutableStateOf(BuilderPane.preview) }
    var menu by remember { mutableStateOf(false) }
    val document = model.document
    // The phone's bottom bar steps aside while a draft is open (`AppRoot`).
    DisposableEffect(model) {
        session.router.documents.isEditingDraft = true
        onDispose { session.router.documents.isEditingDraft = false }
    }
    Scaffold(
        containerColor = Theme.colors.background,
        topBar = {
            TopAppBar(
                title = {
                    Column(Modifier.semantics(mergeDescendants = true) {}) {
                        Text(DocumentText.title(document, model.isPersisted), style = Theme.Fonts.headline, color = Theme.colors.textPrimary)
                        when {
                            model.saveFailed -> Text("Not saved yet", style = Theme.Fonts.caption, color = Theme.colors.danger)
                            model.isPersisted -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Icon(Icons.Filled.Check, null, tint = Theme.colors.brand, modifier = Modifier.size(12.dp))
                                Text("Draft saved", style = Theme.Fonts.caption.copy(fontWeight = FontWeight.Normal), color = Theme.colors.textSecondary)
                            }
                        }
                    }
                },
                navigationIcon = { if (showsBack) IconButton(onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                actions = {
                    TextLinkButton("Preview", model::openPreview, tag = "previewButton", enabled = model.canPreview)
                    Box {
                        IconButton({ menu = true }) { Icon(Icons.Filled.MoreVert, "More") }
                        DropdownMenu(menu, { menu = false }) {
                            DropdownMenuItem({ Text("Duplicate ${DocumentText.noun(document.docType)}") }, { menu = false; model.duplicate() },
                                enabled = model.isPersisted || document.lines.isNotEmpty(), leadingIcon = { Icon(Icons.Filled.ContentCopy, null) })
                            DropdownMenuItem({ Text("Delete draft", color = Theme.colors.danger) }, { menu = false; confirmingDelete = true },
                                leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Theme.colors.danger) })
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Theme.colors.background),
            )
        },
    ) { padding ->
        BoxWithConstraints(Modifier.fillMaxSize().padding(padding)) {
            val width = maxWidth
            val twoPane = width >= 700.dp
            Row(Modifier.fillMaxSize()) {
                Column(Modifier.weight(1f).fillMaxHeight()) {
                    Box(Modifier.weight(1f)) { GuidedForm(model, session) { choosingClient = true } }
                    TotalsBar(model, session) { showsBreakdown = true }
                }
                if (twoPane) {
                    VerticalDivider(color = Theme.colors.border)
                    Column(Modifier.width(if (width >= 900.dp) 400.dp else 340.dp).fillMaxHeight().background(Theme.colors.surfaceMuted)) {
                        SegmentedChoice(BuilderPane.entries.map { it to it.label }, pane, { pane = it }, Modifier.padding(Theme.Space.m), tagPrefix = "builderPane")
                        HorizontalDivider(color = Theme.colors.border)
                        when (pane) {
                            BuilderPane.preview -> DocumentPreviewPane(session, model.documentToRender, model.computed, Modifier.testTag("builderPreview"))
                            BuilderPane.totals -> Column(Modifier.verticalScroll(rememberScrollState()).padding(Theme.Space.l)) {
                                TotalsView(model.computed, model.engineError, document.currency, model.config, session)
                            }
                        }
                    }
                }
            }
        }
    }
    if (choosingClient) ClientPickerSheet(session, document.clientId, model::chooseClient) { choosingClient = false }
    if (model.lineEditor != null) AddItemSheet(model, session)
    if (showsBreakdown) {
        ModalBottomSheet({ showsBreakdown = false }, containerColor = Theme.colors.surface) {
            Column(Modifier.padding(horizontal = Theme.Layout.screenGutter).padding(bottom = Theme.Space.xl)) {
                Text("Tax breakdown", style = Theme.Fonts.title3, modifier = Modifier.padding(bottom = Theme.Space.m))
                TotalsView(model.computed, model.engineError, document.currency, model.config, session)
            }
        }
    }
    if (model.showsPaywall) PaywallDialog(session) { model.showsPaywall = false }
    model.seriesChoice?.let { choice ->
        SeriesChoiceSheet(choice, document.docType, model::startOwnSeries, model::takeOver) { model.seriesChoice = null }
    }
    if (confirmingDelete) ConfirmDialog("Delete this draft?", null, "Delete draft", model::deleteDraft, { confirmingDelete = false })
}

/** The three numbered cards and More options. */
@Composable
private fun GuidedForm(model: DocumentViewModel, session: Session, chooseClient: () -> Unit) {
    val document = model.document
    val config = model.config
    var showsMore by rememberSaveable {
        mutableStateOf(model.isForeignCurrency || document.reverseCharge || document.pricesIncludeTax || document.placeOfSupply != null ||
            document.supplyDate != null || document.discount != null || document.shippingMinor != 0L ||
            document.supplyType != config.supplyTypes.firstOrNull()?.id)
    }
    Box(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.readableWidth().fillMaxWidth().padding(horizontal = Theme.Space.l, vertical = Theme.Space.s),
            verticalArrangement = Arrangement.spacedBy(Theme.Space.m)) {
            Text("Three quick parts. We handle the tax maths.", style = Theme.Fonts.subhead, color = Theme.colors.textSecondary,
                modifier = Modifier.padding(horizontal = Theme.Space.xs))
            Banner(model)
            ClientCard(model, session, chooseClient)
            LinesCard(model, session)
            WhenCard(model, session)
            MoreOptions(model, session, showsMore) { showsMore = !showsMore }
        }
    }
}

/** What blocks sending in red, compliance warnings in amber. */
@Composable
private fun Banner(model: DocumentViewModel) {
    val document = model.document
    val config = model.config
    val problems = model.issueProblems.map { DocumentText.message(it, config, model.homeCurrency, document.docType) }
    val blocking = model.issueProblems.any { it is IssueProblem.BlockingIssue }
    val warnings = model.engineIssues.filter { !blocking || it.severity != EngineIssue.Severity.error }
        .map { DocumentText.message(it, config, model.homeCurrency) }.filter { it !in problems }
    if (problems.isEmpty() && warnings.isEmpty()) return
    val shape = RoundedCornerShape(Theme.Radius.card)
    Box(Modifier.fillMaxWidth().clip(shape).background(Theme.colors.surface)
        .border(1.dp, (if (problems.isEmpty()) Theme.colors.warning else Theme.colors.danger).copy(alpha = 0.5f), shape).padding(Theme.Space.l)) {
        DocumentBanner(problems, warnings)
    }
}

@Composable
private fun ClientCard(model: DocumentViewModel, session: Session, chooseClient: () -> Unit) {
    val document = model.document
    val config = model.config
    val name = model.client?.name ?: if (document.clientId != null) document.buyerSnapshot?.name else null
    NumberedCard(1, "Who is it for?", trailing = if (name != null) ({ TextLinkButton("Change", chooseClient) }) else null) {
        if (name != null) {
            val client = model.client
            val detail = if (client == null) document.buyerSnapshot?.address else if (client.countryCode != session.business.countryCode) {
                session.countryName(client.countryCode)
            } else {
                val place = listOfNotNull(client.billingAddress?.city?.trimmedOrNull, client.regionCode?.let { config.region(it)?.name }).joinToString(", ")
                listOfNotNull(place.ifEmpty { null }, if (client.taxId?.trimmedOrNull != null) "${config.labels.taxIdName} added" else null)
                    .joinToString(" · ").ifEmpty { null }
            }
            Row(Modifier.fillMaxWidth().clickable(onClick = chooseClient).semantics(mergeDescendants = true) {}.testTag("chooseClient"),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Theme.Space.m)) {
                Avatar(name, tip = true)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(name, style = Theme.Fonts.rowTitle, color = Theme.colors.textPrimary)
                    if (detail != null) Text(detail, style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
                }
            }
        } else {
            SecondaryButton("Choose a client", chooseClient, icon = Icons.Filled.PersonAdd, tag = "chooseClient", fillsWidth = true)
            Text("Or leave it empty for a walk-in customer.", style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
        }
        if (model.clientMissing) {
            Text("This client was deleted. The ${DocumentText.noun(document.docType)} keeps their last details.",
                style = Theme.Fonts.footnote, color = Theme.colors.warning)
        }
    }
}

@Composable
private fun LinesCard(model: DocumentViewModel, session: Session) {
    val document = model.document
    NumberedCard(2, "What are you charging for?") {
        Column {
            document.lines.forEachIndexed { index, line ->
                LineRow(line, model.computed?.lines?.getOrNull(index), document.currency, model.chargesTax, session,
                    onEdit = { model.editLine(line.id) }, onDuplicate = { model.duplicateLine(line.id) }, onDelete = { model.deleteLine(line.id) },
                    onMoveUp = if (index > 0) ({ model.moveLine(index, index - 1) }) else null,
                    onMoveDown = if (index < document.lines.size - 1) ({ model.moveLine(index, index + 1) }) else null)
                MutedDivider()
            }
        }
        val brand = Theme.colors.brand
        Row(Modifier.fillMaxWidth().heightIn(min = 46.dp).clip(RoundedCornerShape(Theme.Radius.input))
            .androidDashed(brand.copy(alpha = 0.45f)).clickable(onClick = model::addLine).testTag("addItem"),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
            Icon(Icons.Filled.Add, null, tint = brand, modifier = Modifier.size(18.dp))
            Text(" Add an item", style = Theme.Fonts.callout.copy(fontWeight = FontWeight.Bold), color = brand)
        }
    }
}

/** The dashed outline of "Add an item". */
private fun Modifier.androidDashed(color: androidx.compose.ui.graphics.Color): Modifier = this.drawBehind {
    drawRoundRect(color, cornerRadius = androidx.compose.ui.geometry.CornerRadius(14.dp.toPx()),
        style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 4.dp.toPx()))))
}

@Composable
private fun WhenCard(model: DocumentViewModel, session: Session) {
    val document = model.document
    val isQuote = document.docType == DocumentType.quote
    NumberedCard(3, if (isQuote) "How long is this quote valid?" else "When should they pay?") {
        ChipFlow {
            for (days in model.termChoices) {
                ChoiceChip(if (days == 0) "Right away" else "$days days", model.selectedTermDays == days, { model.setTerm(days) }, tag = "term-$days")
            }
        }
        val date = if (isQuote) document.validUntil else document.dueDate
        if (date != null) {
            val text = if (date == session.today) "today, ${date.displayText}" else date.displayText
            Row(Modifier.testTag("dueText")) {
                Text(if (isQuote) "Valid until " else "Due ", style = Theme.Fonts.subhead, color = Theme.colors.textSecondary)
                Text(text, style = Theme.Fonts.subhead.copy(fontWeight = FontWeight.Bold), color = Theme.colors.textPrimary)
            }
        }
    }
}

/** Everything most invoices never need, folded away: dates, discount and shipping, tax and currency, notes. */
@Composable
private fun MoreOptions(model: DocumentViewModel, session: Session, expanded: Boolean, toggle: () -> Unit) {
    val document = model.document
    val config = model.config
    Column(verticalArrangement = Arrangement.spacedBy(Theme.Space.m)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).clip(RoundedCornerShape(Theme.Radius.l)).background(Theme.colors.surfaceSubtle)
            .clickable(onClick = toggle).semantics { contentDescription = "More options, ${if (expanded) "shown" else "hidden"}" }
            .testTag("moreOptions").padding(horizontal = Theme.Space.l), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).padding(vertical = Theme.Space.s), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("More options", style = Theme.Fonts.rowTitle, color = Theme.colors.textPrimary)
                Text("Discount, notes, currency. Most invoices don't need these.", style = Theme.Fonts.caption.copy(fontWeight = FontWeight.Normal),
                    color = Theme.colors.textSecondary)
            }
            Icon(if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, tint = Theme.colors.textSecondary)
        }
        AnimatedVisibility(expanded) {
            Column(verticalArrangement = Arrangement.spacedBy(Theme.Space.m)) {
                OptionGroup("Dates") {
                    SegmentedChoice(listOf(DocumentType.invoice to "Invoice", DocumentType.quote to "Quote"), document.docType, model::setDocType,
                        tagPrefix = "docType")
                    DateField("${DocumentText.noun(document.docType).replaceFirstChar { it.uppercase() }} date", document.issueDate, model::setIssueDate,
                        tag = "issueDate")
                    if (document.docType == DocumentType.quote) {
                        DateField("Valid until", document.validUntil ?: document.issueDate, { if (!it.isBefore(document.issueDate)) model.setValidUntil(it) })
                    } else {
                        DateField("Due date", document.dueDate ?: document.issueDate, { if (!it.isBefore(document.issueDate)) model.setDueDate(it) })
                        PickerField("Remind me", document.reminderDaysAfterDueOverride,
                            listOf(0, 1, 3, 7, 14, 30).map { it to if (it == 0) "On the due date" else "$it days after the due date" },
                            model::setReminderOverride, none = "Business default", tag = "reminderOverridePicker")
                    }
                }
                val symbol = session.container.reference.currencies[document.currency]?.symbol ?: document.currency.rawValue
                OptionGroup("Discount and shipping") {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                        FormTextField("Discount", model.discountText, model::setDiscountText, Modifier.weight(1f),
                            issue = model.discountIssue?.let { IssueMessages.text(it, "discount") }, keyboard = KeyboardType.Decimal, tag = "discountField")
                        SegmentedChoice(listOf(true to "%", false to if (document.currency == model.homeCurrency) symbol else document.currency.rawValue),
                            model.discountIsPercent, model::setDiscountIsPercent, Modifier.width(140.dp))
                    }
                    FormTextField("Shipping", model.shippingText, model::setShippingText, prompt = "0",
                        issue = model.shippingIssue?.let { IssueMessages.text(it, "shipping") }, keyboard = KeyboardType.Decimal, tag = "shippingField")
                }
                OptionGroup("Tax and currency", Modifier.testTag("taxAndCurrency")) {
                    if (model.showsSupplyType) {
                        PickerField("Supply", document.supplyType, config.supplyTypes.map { it.id to it.label }, { it?.let(model::setSupplyType) })
                    }
                    if (model.showsPlaceOfSupply) {
                        val automatic = model.derivedPlaceOfSupply?.let { "Automatic (${config.region(it)?.name ?: it})" } ?: "Automatic"
                        PickerField(config.labels.placeOfSupply ?: "Place of supply", document.placeOfSupply,
                            config.activeRegionsByName.map { it.code to it.name }, model::setPlaceOfSupply, none = automatic, searchable = true)
                    }
                    SwitchRow("Different supply date", document.supplyDate != null, { model.setSupplyDate(if (it) document.issueDate else null) })
                    document.supplyDate?.let { DateField("Supply date", it, { date: LocalDate -> model.setSupplyDate(date) }) }
                    if (model.showsReverseCharge) SwitchRow("Reverse charge", document.reverseCharge, model::setReverseCharge)
                    if (model.showsPricesIncludeTax) SwitchRow("Prices include ${config.labels.taxName}", document.pricesIncludeTax, model::setPricesIncludeTax)
                    PickerField("Currency", document.currency, session.container.reference.currencies.all.map { it.code to "${it.code.rawValue} – ${it.name}" },
                        { it?.let(model::setCurrency) }, searchable = true)
                    if (model.isForeignCurrency) {
                        FormTextField("1 ${document.currency.rawValue} = … ${model.homeCurrency.rawValue}", model.exchangeRateText, model::setExchangeRateText,
                            issue = model.exchangeRateIssue?.let { IssueMessages.text(it, "exchange rate") }, keyboard = KeyboardType.Decimal)
                    }
                    if (model.showsRoundOff) SwitchRow(config.rounding.grandTotal?.label ?: "Round off", model.roundOffOn, model::setRoundOff)
                }
                OptionGroup("Notes and terms") {
                    FormTextField("Notes", model.notesText, model::setNotesText, multiline = true)
                    FormTextField("Terms", model.termsText, model::setTermsText, multiline = true)
                }
            }
        }
    }
}

/** A titled white group of option rows. */
@Composable
private fun OptionGroup(title: String, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
        Overline(title, Modifier.padding(horizontal = Theme.Space.xs))
        val shape = RoundedCornerShape(Theme.Radius.card)
        Column(Modifier.fillMaxWidth().clip(shape).background(Theme.colors.surface).border(1.dp, Theme.colors.border, shape)
            .padding(horizontal = Theme.Space.l, vertical = Theme.Space.m), verticalArrangement = Arrangement.spacedBy(Theme.Space.s), content = content)
    }
}

/** The pinned totals: subtotal, the tax "added for you", the total and Review & send. */
@Composable
private fun TotalsBar(model: DocumentViewModel, session: Session, showBreakdown: () -> Unit) {
    val document = model.document
    val computed = model.computed
    Column(Modifier.fillMaxWidth().background(Theme.colors.surface).navigationBarsPadding()) {
        HorizontalDivider(color = Theme.colors.border)
        Column(Modifier.padding(horizontal = Theme.Layout.screenGutter, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            when {
                computed != null && document.lines.isNotEmpty() -> Summary(model, session, computed, showBreakdown)
                model.engineError != null && document.lines.isNotEmpty() -> IssueText(DocumentText.message(model.engineError!!, model.config))
                else -> Text("Add an item to see the total.", style = Theme.Fonts.subhead, color = Theme.colors.textSecondary)
            }
            PrimaryButton("Review & send", model::requestIssue, Modifier.padding(top = 6.dp), isBusy = model.isWorking,
                enabled = model.canRequestIssue, tag = "reviewAndSend")
        }
    }
}

@Composable
private fun Summary(model: DocumentViewModel, session: Session, computed: ComputedDocument, showBreakdown: () -> Unit) {
    val currency = model.document.currency
    val totals = computed.totals
    fun money(minor: Long) = session.money(minor, currency)
    Column(Modifier.fillMaxWidth().clickable(onClick = showBreakdown).semantics(mergeDescendants = true) {}.testTag("totals"),
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        @Composable fun row(title: String, minor: Long) {
            Row { Text(title, Modifier.weight(1f), style = Theme.Fonts.subhead, color = Theme.colors.textSecondary)
                Text(money(minor), style = Theme.Fonts.subhead.copy(fontFeatureSettings = "tnum"), color = Theme.colors.textSecondary) }
        }
        row("Subtotal", totals.subtotal)
        if (totals.discount != 0L) row("Discount", -totals.discount)
        if (totals.shipping != 0L) row("Shipping", totals.shipping)
        if (computed.chargesTax && totals.tax != 0L) {
            val rates = computed.lines.map { it.rate }.toSet()
            val name = model.config.labels.taxName
            val label = if (rates.size == 1) "$name ${SpecFormatter.percent(rates.first())}" else name
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(label, style = Theme.Fonts.subhead, color = Theme.colors.textSecondary)
                Badge(if (computed.inclusive) "included" else "added for you")
                Box(Modifier.weight(1f))
                Text(money(totals.tax), style = Theme.Fonts.subhead.copy(fontFeatureSettings = "tnum"), color = Theme.colors.textSecondary)
            }
        }
        if (totals.roundOff != 0L) row(model.config.rounding.grandTotal?.label ?: "Round off", totals.roundOff)
        Row(verticalAlignment = Alignment.Bottom) {
            Text("Total", Modifier.weight(1f), style = Theme.Fonts.headline, color = Theme.colors.textPrimary)
            Text(money(totals.total), Modifier.testTag("totalAmount"), style = Theme.Fonts.amountLarge.copy(fontFeatureSettings = "tnum"),
                color = Theme.colors.textPrimary, maxLines = 1, textAlign = TextAlign.End)
        }
    }
}

/** One line: description, "qty × price · rate" and the amount; tap to edit, ⋮ for the rest. iOS: `LineRow`. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LineRow(
    line: LineItem, computed: ComputedLine?, currency: CurrencyCode, chargesTax: Boolean, session: Session,
    onEdit: (() -> Unit)? = null, onDuplicate: (() -> Unit)? = null, onDelete: (() -> Unit)? = null,
    onMoveUp: (() -> Unit)? = null, onMoveDown: (() -> Unit)? = null,
) {
    var menu by remember { mutableStateOf(false) }
    val unit = line.unit?.let { " " + session.unitLabel(it) } ?: ""
    var detail = SpecFormatter.quantity(line.quantity) + unit + " × " + session.money(line.unitPriceMinor, currency)
    when (val discount = line.discount) {
        is Discount.Percent -> detail += " − ${SpecFormatter.percent(discount.value)}"
        is Discount.Amount -> detail += " − " + session.money(discount.value, currency)
        null -> {}
    }
    if (chargesTax) detail += " · " + (session.rate(line.rateId)?.label ?: line.rateId.ifEmpty { "Choose a rate" })
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).semantics(mergeDescendants = true) {}
            .let { if (onEdit != null) it.combinedClickable(onClick = onEdit, onLongClick = { menu = true }) else it }
            .padding(vertical = Theme.Space.s).testTag("line-${line.position}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(line.description.ifEmpty { "No description" }, style = Theme.Fonts.rowTitle,
                color = if (line.description.isEmpty()) Theme.colors.danger else Theme.colors.textPrimary)
            Text(detail, style = Theme.Fonts.footnote, color = if (chargesTax && line.rateId.isEmpty()) Theme.colors.danger else Theme.colors.textSecondary)
        }
        Text(computed?.let { session.money(it.amount, currency) } ?: "—", style = Theme.Fonts.rowTitle.copy(fontFeatureSettings = "tnum"),
            color = Theme.colors.textPrimary)
        if (onEdit != null) {
            Box {
                IconButton({ menu = true }) { Icon(Icons.Filled.MoreVert, "Item actions", tint = Theme.colors.textSecondary) }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem({ Text("Edit") }, { menu = false; onEdit() }, leadingIcon = { Icon(Icons.Filled.Edit, null) })
                    onDuplicate?.let { DropdownMenuItem({ Text("Duplicate") }, { menu = false; it() }, leadingIcon = { Icon(Icons.Filled.ContentCopy, null) }) }
                    onMoveUp?.let { DropdownMenuItem({ Text("Move up") }, { menu = false; it() }, leadingIcon = { Icon(Icons.Filled.ArrowUpward, null) }) }
                    onMoveDown?.let { DropdownMenuItem({ Text("Move down") }, { menu = false; it() }, leadingIcon = { Icon(Icons.Filled.ArrowDownward, null) }) }
                    onDelete?.let {
                        DropdownMenuItem({ Text("Delete", color = Theme.colors.danger) }, { menu = false; it() },
                            leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Theme.colors.danger) })
                    }
                }
            }
        }
    }
}
