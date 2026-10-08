package app.invoicebuilder.android.documents

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.billing.PaywallDialog
import app.invoicebuilder.android.common.ConfirmDialog
import app.invoicebuilder.android.common.DetailColumn
import app.invoicebuilder.core.designsystem.DateField
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.FormTextField
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.designsystem.NavRow
import app.invoicebuilder.core.designsystem.PickerField
import app.invoicebuilder.core.designsystem.SegmentedChoice
import app.invoicebuilder.core.designsystem.SwitchRow
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.documents.IssueProblem
import app.invoicebuilder.core.domain.documents.LineItem
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.tax.ComputedLine
import app.invoicebuilder.core.domain.tax.Discount
import app.invoicebuilder.core.domain.tax.EngineIssue

private enum class BuilderSheet { client, catalog }
private enum class BuilderPane(val label: String) { preview("Preview"), totals("Totals") }

/**
 * The invoice / quote builder (wireframe 8): a form, and on wide windows the live PDF preview beside it with the
 * totals a tap away. iOS: `DocumentBuilderView`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DocumentBuilder(model: DocumentViewModel, session: Session, showsBack: Boolean, onBack: () -> Unit) {
    var sheet by rememberSaveable { mutableStateOf<BuilderSheet?>(null) }
    var confirmingDelete by remember { mutableStateOf(false) }
    var pane by rememberSaveable { mutableStateOf(BuilderPane.preview) }
    var menu by remember { mutableStateOf(false) }
    val document = model.document
    Scaffold(
        containerColor = Theme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(DocumentText.title(document, model.isPersisted)) },
                navigationIcon = { if (showsBack) IconButton(onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                actions = {
                    IconButton(model::openPreview, enabled = model.canPreview, modifier = Modifier.testTag("previewButton")) {
                        Icon(Icons.Filled.Description, "Preview")
                    }
                    TextButton(model::requestIssue, enabled = model.canRequestIssue, modifier = Modifier.testTag("issueButton")) {
                        if (model.isWorking) CircularProgressIndicator(Modifier.width(18.dp)) else Text("Issue", fontWeight = FontWeight.SemiBold)
                    }
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
                Box(Modifier.weight(1f).fillMaxHeight()) { BuilderForm(model, session, showsTotals = !twoPane, openSheet = { sheet = it }) }
                if (twoPane) {
                    VerticalDivider(color = Theme.colors.border)
                    Column(Modifier.width(if (width >= 900.dp) 400.dp else 340.dp).fillMaxHeight()) {
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
    when (sheet) {
        BuilderSheet.client -> ClientPickerSheet(session, document.clientId, model::chooseClient) { sheet = null }
        BuilderSheet.catalog -> CatalogPickerSheet(session, model::addItem) { sheet = null }
        null -> {}
    }
    if (model.lineEditor != null) LineEditor(model, session)
    if (model.confirmingIssue) {
        val noun = DocumentText.noun(document.docType)
        ConfirmDialog("Issue this $noun?",
            (model.numberPreview?.let { "It will be numbered $it. " } ?: "") + "Issued documents keep their number and can't be deleted.",
            "Issue $noun", model::confirmIssue, { model.confirmingIssue = false }, destructive = false, confirmTag = "confirmIssue")
    }
    if (model.showsPaywall) PaywallDialog(session) { model.showsPaywall = false }
    model.seriesChoice?.let { choice ->
        SeriesChoiceSheet(choice, document.docType, model::startOwnSeries, model::takeOver) { model.seriesChoice = null }
    }
    if (confirmingDelete) ConfirmDialog("Delete this draft?", null, "Delete draft", model::deleteDraft, { confirmingDelete = false })
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BuilderForm(model: DocumentViewModel, session: Session, showsTotals: Boolean, openSheet: (BuilderSheet) -> Unit) {
    val document = model.document
    val config = model.config
    var showsTaxAndCurrency by rememberSaveable {
        mutableStateOf(model.isForeignCurrency || document.reverseCharge || document.pricesIncludeTax || document.placeOfSupply != null ||
            document.supplyDate != null || document.supplyType != config.supplyTypes.firstOrNull()?.id)
    }
    DetailColumn(Modifier.imePadding()) {
        // Banner: what blocks issuing in red, compliance warnings in amber.
        val problems = model.issueProblems.map { DocumentText.message(it, config, model.homeCurrency, document.docType) }
        val blocking = model.issueProblems.any { it is IssueProblem.BlockingIssue }
        val warnings = model.engineIssues.filter { !blocking || it.severity != EngineIssue.Severity.error }
            .map { DocumentText.message(it, config, model.homeCurrency) }.filter { it !in problems }
        if (problems.isNotEmpty() || warnings.isNotEmpty()) FormSection { DocumentBanner(problems, warnings) }

        FormSection("Client") {
            val clientName = model.client?.name ?: if (document.clientId != null) document.buyerSnapshot?.name else null
            val detail = model.client?.let { client ->
                when {
                    client.countryCode != session.business.countryCode -> session.countryName(client.countryCode)
                    client.taxId != null -> "${config.labels.taxIdName} ${client.taxId}"
                    else -> client.billingAddress?.singleLine
                }
            } ?: document.buyerSnapshot?.address
            if (clientName != null) NavRow(clientName, { openSheet(BuilderSheet.client) }, subtitle = detail, tag = "chooseClient")
            else NavRow("Choose client", { openSheet(BuilderSheet.client) }, icon = Icons.Filled.PersonAdd, tag = "chooseClient")
            if (model.clientMissing) {
                Text("This client was deleted. The ${DocumentText.noun(document.docType)} keeps their last details.",
                    style = MaterialTheme.typography.bodySmall, color = Theme.colors.warning)
            }
        }

        FormSection("Details") {
            SegmentedChoice(listOf(DocumentType.invoice to "Invoice", DocumentType.quote to "Quote"), document.docType, model::setDocType, tagPrefix = "docType")
            DateField("Issue date", document.issueDate, model::setIssueDate, tag = "issueDate")
            if (document.docType == DocumentType.quote) {
                DateField("Valid until", document.validUntil ?: document.issueDate, { if (!it.isBefore(document.issueDate)) model.setValidUntil(it) })
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    DateField("Due date", document.dueDate ?: document.issueDate, { if (!it.isBefore(document.issueDate)) model.setDueDate(it) }, Modifier.weight(1f))
                    PaymentTermsMenu(model::setDue)
                }
                PickerField("Remind me", document.reminderDaysAfterDueOverride,
                    listOf(0, 1, 3, 7, 14, 30).map { it to if (it == 0) "On the due date" else "$it days after the due date" },
                    model::setReminderOverride, none = "Business default", tag = "reminderOverridePicker")
            }
        }

        FormSection("Items") {
            document.lines.forEachIndexed { index, line ->
                LineRow(line, model.computed?.lines?.getOrNull(index), document.currency, model.chargesTax, session,
                    onEdit = { model.editLine(line.id) }, onDuplicate = { model.duplicateLine(line.id) }, onDelete = { model.deleteLine(line.id) },
                    onMoveUp = if (index > 0) ({ model.moveLine(index, index - 1) }) else null,
                    onMoveDown = if (index < document.lines.size - 1) ({ model.moveLine(index, index + 1) }) else null)
                HorizontalDivider(color = Theme.colors.border.copy(alpha = 0.5f))
            }
            NavRow("Add from items", { openSheet(BuilderSheet.catalog) }, icon = Icons.Filled.Inventory2, tag = "addFromItems")
            NavRow("Add line", model::addLine, icon = Icons.Filled.Add, tag = "addLine")
        }

        val symbol = session.container.reference.currencies[document.currency]?.symbol ?: document.currency.rawValue
        FormSection("Discount and shipping") {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                FormTextField("Discount", model.discountText, model::setDiscountText, Modifier.weight(1f),
                    issue = model.discountIssue?.let { IssueMessages.text(it, "discount") }, keyboard = KeyboardType.Decimal, tag = "discountField")
                SegmentedChoice(listOf(true to "%", false to if (document.currency == model.homeCurrency) symbol else document.currency.rawValue),
                    model.discountIsPercent, model::setDiscountIsPercent, Modifier.width(140.dp))
            }
            FormTextField("Shipping", model.shippingText, model::setShippingText, prompt = "0",
                issue = model.shippingIssue?.let { IssueMessages.text(it, "shipping") }, keyboard = KeyboardType.Decimal, tag = "shippingField")
        }

        FormSection {
            Row(Modifier.fillMaxWidth().clickable { showsTaxAndCurrency = !showsTaxAndCurrency }.padding(vertical = Theme.Space.s).testTag("taxAndCurrency"),
                verticalAlignment = Alignment.CenterVertically) {
                Text("Tax and currency", Modifier.weight(1f))
                Icon(if (showsTaxAndCurrency) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, if (showsTaxAndCurrency) "Collapse" else "Expand")
            }
            AnimatedVisibility(showsTaxAndCurrency) {
                Column(verticalArrangement = Arrangement.spacedBy(Theme.Space.xs)) {
                    if (model.showsSupplyType) {
                        PickerField("Supply", document.supplyType, config.supplyTypes.map { it.id to it.label }, { it?.let(model::setSupplyType) })
                    }
                    if (model.showsPlaceOfSupply) {
                        val automatic = model.derivedPlaceOfSupply?.let { "Automatic (${config.region(it)?.name ?: it})" } ?: "Automatic"
                        PickerField(config.labels.placeOfSupply ?: "Place of supply", document.placeOfSupply,
                            config.activeRegionsByName.map { it.code to it.name }, model::setPlaceOfSupply, none = automatic, searchable = true)
                    }
                    SwitchRow("Different supply date", document.supplyDate != null, { model.setSupplyDate(if (it) document.issueDate else null) })
                    document.supplyDate?.let { DateField("Supply date", it, { date -> model.setSupplyDate(date) }) }
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
            }
        }

        if (showsTotals) FormSection("Totals") { TotalsView(model.computed, model.engineError, document.currency, config, session) }

        FormSection("Notes and terms",
            if (model.saveFailed) "Couldn't save the latest changes. They'll be saved again with your next change." else "Drafts save automatically.") {
            FormTextField("Notes", model.notesText, model::setNotesText, multiline = true)
            FormTextField("Terms", model.termsText, model::setTermsText, multiline = true)
        }
    }
}

@Composable
private fun PaymentTermsMenu(onPick: (Long) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        TextButton({ open = true }) { Text("Terms") }
        DropdownMenu(open, { open = false }) {
            for (days in listOf(0L, 7L, 15L, 30L, 45L, 60L)) {
                DropdownMenuItem({ Text(if (days == 0L) "Due on receipt" else "$days days") }, { open = false; onPick(days) })
            }
        }
    }
}

/** One line: description, quantity × price, rate and amount; tap to edit, ⋮ for the rest. iOS: `LineRow`. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LineRow(
    line: LineItem, computed: ComputedLine?, currency: CurrencyCode, chargesTax: Boolean, session: Session,
    onEdit: (() -> Unit)? = null, onDuplicate: (() -> Unit)? = null, onDelete: (() -> Unit)? = null,
    onMoveUp: (() -> Unit)? = null, onMoveDown: (() -> Unit)? = null,
) {
    var menu by remember { mutableStateOf(false) }
    val unit = line.unit?.let { " " + session.unitLabel(it) } ?: ""
    var quantity = SpecFormatter.quantity(line.quantity) + unit + " × " + session.money(line.unitPriceMinor, currency)
    when (val discount = line.discount) {
        is Discount.Percent -> quantity += " − ${SpecFormatter.percent(discount.value)}"
        is Discount.Amount -> quantity += " − " + session.money(discount.value, currency)
        null -> {}
    }
    Row(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}
            .let { if (onEdit != null) it.combinedClickable(onClick = onEdit, onLongClick = { menu = true }) else it }
            .padding(vertical = Theme.Space.xs).testTag("line-${line.position}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(line.description.ifEmpty { "No description" }, color = if (line.description.isEmpty()) Theme.colors.danger else Theme.colors.textPrimary)
            Text(quantity, style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
            if (chargesTax) {
                Text(session.rate(line.rateId)?.label ?: line.rateId.ifEmpty { "Choose a rate" }, style = MaterialTheme.typography.labelSmall,
                    color = if (line.rateId.isEmpty()) Theme.colors.danger else Theme.colors.textTertiary)
            }
        }
        Text(computed?.let { session.money(it.amount, currency) } ?: "—")
        if (onEdit != null) {
            Box {
                IconButton({ menu = true }) { Icon(Icons.Filled.MoreVert, "Line actions") }
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
