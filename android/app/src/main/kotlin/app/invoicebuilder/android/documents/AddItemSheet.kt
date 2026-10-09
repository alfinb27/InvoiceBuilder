package app.invoicebuilder.android.documents

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.common.SearchField
import app.invoicebuilder.core.designsystem.BoxedTextField
import app.invoicebuilder.core.designsystem.CheckboxRow
import app.invoicebuilder.core.designsystem.ChipFlow
import app.invoicebuilder.core.designsystem.ChoiceChip
import app.invoicebuilder.core.designsystem.FieldLabel
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.designsystem.IssueText
import app.invoicebuilder.core.designsystem.MutedDivider
import app.invoicebuilder.core.designsystem.PickerField
import app.invoicebuilder.core.designsystem.PrimaryButton
import app.invoicebuilder.core.designsystem.QuantityStepper
import app.invoicebuilder.core.designsystem.SegmentedChoice
import app.invoicebuilder.core.designsystem.SwitchRow
import app.invoicebuilder.core.designsystem.Tag
import app.invoicebuilder.core.designsystem.TextLinkButton
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.designsystem.TipCallout
import app.invoicebuilder.core.domain.documents.LineItemDraft
import app.invoicebuilder.core.domain.documents.LineItemField
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.setup.SetupSearch
import app.invoicebuilder.core.domain.tax.TaxCategory
import app.invoicebuilder.core.domain.tax.TaxRate

private enum class AddItemTab(val label: String) { saved("My saved items"), new("Something new") }

/**
 * Adding and editing a line (`spec/documents.md` §3.2, `docs/design/design.md` §6.5): "My saved items" adds
 * catalogue lines with a tap; "Something new" asks what was sold, how many, the price for one and the rate, shows the
 * line's total live and can save it for next time. Editing a line opens the same form without the tabs.
 * iOS: `AddItemSheet`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddItemSheet(model: DocumentViewModel, session: Session) {
    val editor = model.lineEditor ?: return
    val items by remember(session.business.id) { session.container.catalog.observeItems(session.business.id) }
        .collectAsStateWithLifecycle(null)
    var tab by rememberSaveable(editor.lineID) { mutableStateOf<AddItemTab?>(null) }
    val added = remember(editor.lineID) { mutableStateMapOf<String, Int>() }
    val live = items?.filter { !it.isArchived }
    // The first time the saved items arrive: open on them when there are any (≈ the iOS `tabChosen` flag).
    LaunchedEffect(live != null) {
        if (tab == null && live != null) tab = if (editor.isNew && !editor.needsPrice && live.isNotEmpty()) AddItemTab.saved else AddItemTab.new
    }
    val current = if (editor.isNew) tab ?: AddItemTab.new else AddItemTab.new
    val noun = DocumentText.noun(model.document.docType)
    ModalBottomSheet(model::cancelLineEditor, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Theme.colors.surface, shape = RoundedCornerShape(topStart = Theme.Radius.sheet, topEnd = Theme.Radius.sheet)) {
        Column(Modifier.fillMaxWidth().imePadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = Theme.Layout.screenGutter), verticalAlignment = Alignment.CenterVertically) {
                Text(if (editor.isNew) "Add an item" else "Edit item", Modifier.weight(1f), style = Theme.Fonts.title3, color = Theme.colors.textPrimary)
                if (!editor.isNew) LineMenu(model, editor.lineID)
                TextLinkButton("Cancel", model::cancelLineEditor, tag = "lineCancel")
            }
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())
                .padding(horizontal = Theme.Layout.screenGutter, vertical = Theme.Space.s),
                verticalArrangement = Arrangement.spacedBy(Theme.Space.l)) {
                if (editor.isNew) {
                    SegmentedChoice(AddItemTab.entries.map { it to it.label }, current, { tab = it }, tagPrefix = "addItemTab")
                }
                if (current == AddItemTab.saved) SavedItems(model, session, live.orEmpty(), added) { tab = it }
                else NewItemForm(model, session, noun)
            }
            Box(Modifier.fillMaxWidth().padding(horizontal = Theme.Layout.screenGutter, vertical = Theme.Space.s).navigationBarsPadding()) {
                if (current == AddItemTab.saved) {
                    PrimaryButton(if (added.isEmpty()) "Close" else "Done", model::cancelLineEditor, tag = "catalogDone")
                } else {
                    PrimaryButton(if (editor.isNew) "Add to $noun" else "Save", { model.commitLineEditor() }, tag = "lineDone")
                }
            }
        }
    }
}

@Composable
private fun LineMenu(model: DocumentViewModel, lineID: String) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton({ open = true }, Modifier.testTag("lineMenu")) { Icon(Icons.Filled.MoreVert, "More") }
        DropdownMenu(open, { open = false }) {
            DropdownMenuItem({ Text("Duplicate") }, { open = false; if (model.commitLineEditor()) model.duplicateLine(lineID) },
                leadingIcon = { Icon(Icons.Filled.ContentCopy, null) })
            DropdownMenuItem({ Text("Delete", color = Theme.colors.danger) }, { open = false; model.cancelLineEditor(); model.deleteLine(lineID) },
                leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Theme.colors.danger) })
        }
    }
}

@Composable
private fun SavedItems(
    model: DocumentViewModel, session: Session, items: List<app.invoicebuilder.core.domain.models.CatalogItem>,
    added: MutableMap<String, Int>, switchTo: (AddItemTab) -> Unit,
) {
    var query by rememberSaveable { mutableStateOf("") }
    val taxName = model.config.labels.taxName
    if (items.isEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
            Text("No saved items yet", style = Theme.Fonts.headline, color = Theme.colors.textPrimary)
            Text("Add something new and keep “Save to my items” on, and it shows up here next time.",
                style = Theme.Fonts.subhead, color = Theme.colors.textSecondary)
            TextLinkButton("Add something new", { switchTo(AddItemTab.new) })
        }
        return
    }
    SearchField(query, { query = it }, "Search by name or ${model.config.labels.productCodeName}")
    Column {
        for (item in SetupSearch.items(items, query)) {
            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable {
                val needsPrice = model.addItem(item)
                added[item.id] = (added[item.id] ?: 0) + 1
                if (needsPrice) switchTo(AddItemTab.new)
            }.semantics(mergeDescendants = true) {}.testTag("catalogItem-${item.name}"), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(item.name, style = Theme.Fonts.rowTitle, color = Theme.colors.textPrimary)
                    val rate = if (model.chargesTax) " · " + (session.rate(item.rateId)?.label ?: "") else ""
                    Text(session.money(item.unitPriceMinor, item.currency) + (if (item.priceIncludesTax) " incl. $taxName" else "") + rate,
                        style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
                }
                val count = added[item.id]
                if (count != null) Tag(if (count == 1) "Added" else "Added ×$count", Theme.colors.success)
                else Icon(Icons.Filled.AddCircle, "Add", tint = Theme.colors.brand, modifier = Modifier.size(26.dp))
            }
            MutedDivider()
        }
    }
}

@Composable
private fun NewItemForm(model: DocumentViewModel, session: Session, noun: String) {
    val editor = model.lineEditor ?: return
    val draft = editor.draft
    val config = model.config
    val taxName = config.labels.taxName
    val document = model.document
    fun message(field: LineItemField, name: String) = model.visibleLineIssue(field)?.let { IssueMessages.text(it, name) }
    fun update(change: (LineItemDraft) -> LineItemDraft) = model.updateLineDraft(change(draft))

    if (editor.needsPrice) {
        TipCallout("Enter the price in ${document.currency.rawValue}: there's no exchange rate to convert the item's saved price.")
    }
    BoxedTextField("What did you sell?", draft.description, { v -> update { it.copy(description = v) } }, prompt = "Website design",
        issue = message(LineItemField.Description, "description"), hint = "This is what your client sees on the $noun.", tag = "lineDescription")
    BoxWithConstraints {
        val stacked = maxWidth < 320.dp
        val quantity: @Composable (Modifier) -> Unit = { modifier ->
            Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                FieldLabel("How many?")
                QuantityStepper(draft.quantityText, { v -> update { it.copy(quantityText = v) } }, { model.stepLineQuantity(-1) },
                    { model.stepLineQuantity(1) }, name = "How many?", tag = "lineQuantity")
                message(LineItemField.Quantity, "quantity")?.let { IssueText(it) }
            }
        }
        val symbol = session.container.reference.currencies[document.currency]?.symbol ?: document.currency.rawValue
        val price: @Composable (Modifier) -> Unit = { modifier ->
            BoxedTextField("Price for one", draft.priceText, { v -> update { it.copy(priceText = v) } }, modifier, prompt = "0",
                issue = message(LineItemField.Price, "price"), keyboard = KeyboardType.Decimal, tag = "linePrice", leading = symbol)
        }
        if (stacked) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) { quantity(Modifier.fillMaxWidth()); price(Modifier.fillMaxWidth()) }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) { quantity(Modifier.weight(1f)); price(Modifier.weight(1f)) }
        }
    }
    if (model.chargesTax) RateSection(model, draft, taxName) { id -> update { it.copy(rateId = id) } }
    if (model.chargesTax) {
        SwitchRow("My price already includes $taxName", "On: $taxName is taken out of your price.", "Off: we add $taxName on top of your price.",
            editor.includesTax, model::setLineIncludesTax, tag = "lineIncludesTax")
    }
    model.lineEditorPreview?.let { preview ->
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.Radius.input)).background(Theme.colors.tip)
            .semantics(mergeDescendants = true) { contentDescription = "Line total ${preview.total}: ${preview.text}" }.testTag("lineTotal")
            .padding(horizontal = 14.dp, vertical = Theme.Space.m), verticalAlignment = Alignment.CenterVertically) {
            Text(preview.text, Modifier.weight(1f), style = Theme.Fonts.subhead, color = Theme.colors.tipOn)
            Text(preview.total, style = Theme.Fonts.title3.copy(fontFeatureSettings = "tnum"), color = Theme.colors.tipOn)
        }
    }
    if (model.canSaveLineToItems) {
        CheckboxRow("Save to my items so I can reuse it", editor.saveToItems, model::setLineSaveToItems, tag = "lineSaveToItems")
    }
    Details(model, session, draft, ::update, ::message)
}

/** The rate chips, "Other rates" and the hint (`design/rate-chips.json`). */
@Composable
private fun RateSection(model: DocumentViewModel, draft: LineItemDraft, taxName: String, onPick: (String) -> Unit) {
    val choices = model.lineRateChoices
    val chips = choices.chips + choices.others.filter { it.id == draft.rateId }
    var others by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            FieldLabel("$taxName rate", Modifier.weight(1f))
            if (choices.others.isNotEmpty()) {
                Box {
                    TextButton({ others = true }, Modifier.testTag("lineOtherRates")) {
                        Text("Other rates", style = Theme.Fonts.footnote.copy(fontWeight = FontWeight.SemiBold))
                    }
                    DropdownMenu(others, { others = false }) {
                        for (rate in choices.others) DropdownMenuItem({ Text(rate.label) }, { others = false; onPick(rate.id) })
                    }
                }
            }
        }
        if (chips.size <= 4) {
            Row(horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                for (rate in chips) {
                    ChoiceChip(chipTitle(rate), rate.id == draft.rateId, { onPick(rate.id) }, Modifier.weight(1f), fillsWidth = true,
                        tag = "rate-${rate.id}", contentDescription = rate.label)
                }
            }
        } else {
            ChipFlow {
                for (rate in chips) ChoiceChip(chipTitle(rate), rate.id == draft.rateId, { onPick(rate.id) }, tag = "rate-${rate.id}",
                    contentDescription = rate.label)
            }
        }
        val issue = model.visibleLineIssue(LineItemField.Rate)
        if (issue != null) IssueText(IssueMessages.text(issue, "rate"))
        else choices.hint?.let { Text(it, style = Theme.Fonts.caption.copy(fontWeight = FontWeight.Normal), color = Theme.colors.textSecondary) }
    }
}

/** "18%" for a plain percent rate; the rate's label otherwise ("Exempt"). */
private fun chipTitle(rate: TaxRate): String {
    val plain = rate.category == TaxCategory.standard || rate.category == TaxCategory.reduced || rate.category == TaxCategory.zero
    val percent = rate.percent
    return if (plain && rate.components == null && percent != null) SpecFormatter.percent(percent) else rate.label
}

/** Unit, product code and line discount, folded away unless they are needed or already set. */
@Composable
private fun Details(
    model: DocumentViewModel, session: Session, draft: LineItemDraft, update: ((LineItemDraft) -> LineItemDraft) -> Unit,
    message: (LineItemField, String) -> String?,
) {
    val config = model.config
    val needsCode = config.family == "IN" && model.client?.isBusiness == true && model.chargesTax
    val hasDetails = draft.productCode.isNotEmpty() || draft.discountText.isNotEmpty()
    var shows by rememberSaveable { mutableStateOf(false) }
    val open = shows || hasDetails
    val code: @Composable () -> Unit = {
        BoxedTextField("${config.labels.productCodeName}${if (config.family == "IN") "" else " (optional)"}", draft.productCode,
            { v -> update { it.copy(productCode = v) } }, prompt = if (config.family == "IN") "998314" else null,
            issue = message(LineItemField.ProductCode, config.labels.productCodeName),
            hint = if (config.family == "IN") "The code for what you sold, printed on business invoices." else null,
            keyboard = if (config.family == "IN") KeyboardType.Number else KeyboardType.Text)
    }
    if (needsCode) code()
    Row(Modifier.fillMaxWidth().heightIn(min = Theme.Layout.minTouchTarget).clickable { shows = !shows }.testTag("lineMoreDetails"),
        verticalAlignment = Alignment.CenterVertically) {
        Text(if (needsCode) "Unit and discount" else "More details (unit, ${config.labels.productCodeName}, discount)", Modifier.weight(1f),
            style = Theme.Fonts.subhead.copy(fontWeight = FontWeight.SemiBold), color = Theme.colors.textPrimary)
        Icon(if (open) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, if (open) "Hide" else "Show", tint = Theme.colors.textSecondary)
    }
    AnimatedVisibility(open) {
        Column(verticalArrangement = Arrangement.spacedBy(Theme.Space.m)) {
            PickerField("Unit", draft.unit, session.container.reference.units.map { it.id to it.label }, { v -> update { it.copy(unit = v) } },
                none = "No unit", searchable = true)
            if (!needsCode) code()
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                    BoxedTextField("Discount on this item (optional)", draft.discountText, { v -> update { it.copy(discountText = v) } },
                        Modifier.weight(1f), prompt = "0", keyboard = KeyboardType.Decimal)
                    SegmentedChoice(listOf(true to "%", false to model.document.currency.rawValue), draft.discountIsPercent,
                        { v -> update { it.copy(discountIsPercent = v) } }, Modifier.width(140.dp))
                }
                message(LineItemField.Discount, "discount")?.let { IssueText(it) }
            }
        }
    }
}
