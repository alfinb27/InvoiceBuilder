package app.invoicebuilder.core.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// The components of `docs/design/design.md` §5, drawn from the theme tokens. iOS: `DesignSystem/Components.swift`,
// same names.

private fun Modifier.tagged(tag: String?): Modifier = if (tag != null) testTag(tag) else this

// region Buttons

/** The large full-width brand button (height 56, radius 16), optionally with a leading icon or a trailing arrow. */
@Composable
fun PrimaryButton(
    title: String, onClick: () -> Unit, modifier: Modifier = Modifier, isBusy: Boolean = false, enabled: Boolean = true,
    tag: String? = null, icon: ImageVector? = null, trailingArrow: Boolean = false,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val active = enabled && !isBusy
    val shape = RoundedCornerShape(Theme.Radius.button)
    Box(
        modifier.fillMaxWidth().heightIn(min = Theme.Layout.primaryButtonHeight).clip(shape)
            .background(if (pressed) Theme.colors.brandPressed else Theme.colors.brand.copy(alpha = if (active) 1f else 0.45f))
            .clickable(interaction, indication = null, enabled = active, role = Role.Button, onClick = onClick)
            .tagged(tag).padding(horizontal = Theme.Space.l),
        contentAlignment = Alignment.Center,
    ) {
        if (isBusy) {
            CircularProgressIndicator(Modifier.size(22.dp), color = Theme.colors.brandOn, strokeWidth = 2.dp)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                if (icon != null) Icon(icon, null, tint = Theme.colors.brandOn)
                Text(title, style = Theme.Fonts.button, color = Theme.colors.brandOn, textAlign = TextAlign.Center)
                if (trailingArrow) Icon(Icons.AutoMirrored.Filled.ArrowForward, null, tint = Theme.colors.brandOn)
            }
        }
    }
}

/** A brand-coloured text button with no fill, at least 44 high ("I've used this app before", "Keep as draft"). */
@Composable
fun TextLinkButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, tag: String? = null, enabled: Boolean = true) {
    Box(
        modifier.heightIn(min = Theme.Layout.minTouchTarget).clip(RoundedCornerShape(Theme.Radius.m))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick).tagged(tag).padding(horizontal = Theme.Space.s),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = Theme.Fonts.callout.copy(fontWeight = FontWeight.SemiBold),
            color = if (enabled) Theme.colors.brand else Theme.colors.textSecondary)
    }
}

/** A quiet secondary button: surface fill, strong border, primary text. */
@Composable
fun SecondaryButton(
    title: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: ImageVector? = null, tag: String? = null,
    fillsWidth: Boolean = false,
) {
    val shape = RoundedCornerShape(Theme.Radius.input)
    Row(
        modifier.let { if (fillsWidth) it.fillMaxWidth() else it }.heightIn(min = Theme.Layout.minTouchTarget).clip(shape)
            .background(Theme.colors.surface).border(1.dp, Theme.colors.borderStrong, shape)
            .clickable(role = Role.Button, onClick = onClick).tagged(tag).padding(horizontal = Theme.Space.l),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Theme.Space.s, Alignment.CenterHorizontally),
    ) {
        if (icon != null) Icon(icon, null, tint = Theme.colors.textPrimary, modifier = Modifier.size(20.dp))
        Text(title, style = Theme.Fonts.rowTitle, color = Theme.colors.textPrimary)
    }
}

// endregion

// region Selection

/** The ring of a radio choice, filled when selected. */
@Composable
fun RadioMark(isSelected: Boolean) {
    val brand = Theme.colors.brand
    val control = Theme.colors.control
    Canvas(Modifier.size(22.dp)) {
        drawCircle(if (isSelected) brand else control, radius = size.minDimension / 2 - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
        if (isSelected) drawCircle(brand, radius = 5.dp.toPx())
    }
}

/**
 * One choice of a radio group drawn as a card: an icon tile, a title and hint, and a radio ring. Selected: a 2 dp brand
 * border and a filled dot.
 */
@Composable
fun SelectableCard(
    title: String, isSelected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier, hint: String? = null,
    badge: String? = null, icon: ImageVector? = null, tag: String? = null,
) {
    val shape = RoundedCornerShape(Theme.Radius.l)
    Row(
        modifier.fillMaxWidth().heightIn(min = 68.dp).clip(shape).background(Theme.colors.surface)
            .border(if (isSelected) 2.dp else 1.dp, if (isSelected) Theme.colors.brand else Theme.colors.border, shape)
            .selectable(isSelected, role = Role.RadioButton, onClick = onClick).tagged(tag)
            .padding(horizontal = 14.dp, vertical = Theme.Space.m),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        if (badge != null || icon != null) {
            Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(Theme.colors.brandTint), contentAlignment = Alignment.Center) {
                if (icon != null) Icon(icon, null, tint = Theme.colors.brandPressed)
                else Text(badge!!, style = Theme.Fonts.subhead.copy(fontWeight = FontWeight.Bold), color = Theme.colors.brandPressed)
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = Theme.Fonts.body.copy(fontWeight = FontWeight.SemiBold), color = Theme.colors.textPrimary)
            if (hint != null) Text(hint, style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
        }
        RadioMark(isSelected)
    }
}

/** A single-choice pill (44 high). Off: surface with a strong border; on: brand tint with a 2 dp brand border. */
@Composable
fun ChoiceChip(
    title: String, isSelected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier, fillsWidth: Boolean = false,
    tag: String? = null, contentDescription: String? = null,
) {
    val shape = RoundedCornerShape(if (fillsWidth) 12.dp else 22.dp)
    Box(
        modifier.heightIn(min = Theme.Layout.minTouchTarget).clip(shape)
            .background(if (isSelected) Theme.colors.brandTint else Theme.colors.surface)
            .border(if (isSelected) 2.dp else 1.dp, if (isSelected) Theme.colors.brand else Theme.colors.borderStrong, shape)
            .selectable(isSelected, role = Role.RadioButton, onClick = onClick)
            .semantics { if (contentDescription != null) this.contentDescription = contentDescription }
            .tagged(tag).padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = Theme.Fonts.subhead.copy(fontWeight = if (fillsWidth) FontWeight.Bold else FontWeight.SemiBold),
            color = Theme.colors.textPrimary, textAlign = TextAlign.Center)
    }
}

/** Chips in rows, wrapping to the next row when one is full (iOS: `FlowLayout`). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ChipFlow(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    FlowRow(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Theme.Space.s),
        verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) { content() }
}

// endregion

// region Cards and sections

/** A surface card: white (surface) fill, radius 20, a 1 dp border. */
@Composable
fun SurfaceCard(modifier: Modifier = Modifier, padding: Dp = Theme.Space.l, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(Theme.Radius.card)
    Column(
        modifier.fillMaxWidth().clip(shape).background(Theme.colors.surface).border(1.dp, Theme.colors.border, shape).padding(padding),
        verticalArrangement = Arrangement.spacedBy(Theme.Space.m), content = content,
    )
}

/** A numbered question card of the guided builder: a 24 dp brand circle with the step number and the question. */
@Composable
fun NumberedCard(
    number: Int, title: String, modifier: Modifier = Modifier, trailing: (@Composable RowScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    SurfaceCard(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(24.dp).clip(CircleShape).background(Theme.colors.brand), contentAlignment = Alignment.Center) {
                Text("$number", style = Theme.Fonts.footnote.copy(fontWeight = FontWeight.Bold), color = Theme.colors.brandOn)
            }
            Text(title, Modifier.weight(1f).semantics { heading(); contentDescription = "Step $number: $title" },
                style = Theme.Fonts.headline, color = Theme.colors.textPrimary)
            trailing?.invoke(this)
        }
        content()
    }
}

/** An uppercase section label ("ONCE YOU START SENDING"). */
@Composable
fun Overline(text: String, modifier: Modifier = Modifier) {
    Text(text.uppercase(), modifier.semantics { heading() }, style = Theme.Fonts.overline, color = Theme.colors.textSecondary)
}

/** A screen's display title with a one-line reason under it. */
@Composable
fun ScreenHeader(title: String, modifier: Modifier = Modifier, subtitle: String? = null, large: Boolean = false) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
        Text(title, Modifier.semantics { heading() }, style = if (large) Theme.Fonts.largeTitle else Theme.Fonts.title,
            color = Theme.colors.textPrimary)
        if (subtitle != null) Text(subtitle, style = Theme.Fonts.callout, color = Theme.colors.textSecondary)
    }
}

// endregion

// region Progress

/** Equal bars, one per stage, with the stage names under them; the current stage is brand and bold. */
@Composable
fun SteppedProgress(stages: List<String>, current: Int, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth().semantics(mergeDescendants = true) {
            contentDescription = "Step ${current + 1} of ${stages.size}: ${stages.getOrNull(current) ?: ""}"
        },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        stages.forEachIndexed { index, stage ->
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.fillMaxWidth().height(5.dp).clip(RoundedCornerShape(3.dp))
                    .background(if (index <= current) Theme.colors.brand else Theme.colors.border))
                Text(stage, style = Theme.Fonts.caption.copy(fontWeight = if (index == current) FontWeight.Bold else FontWeight.Medium),
                    color = if (index == current) Theme.colors.textPrimary else Theme.colors.textSecondary)
            }
        }
    }
}

/** A 6 dp bar with an "n of m" label. */
@Composable
fun ProgressBar(value: Int, total: Int, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = "$value of $total done" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.weight(1f).height(6.dp).clip(RoundedCornerShape(3.dp)).background(Theme.colors.border)) {
            Box(Modifier.fillMaxWidth(value.toFloat() / maxOf(total, 1)).height(6.dp).clip(RoundedCornerShape(3.dp))
                .background(Theme.colors.brand))
        }
        Text("$value of $total", style = Theme.Fonts.footnote.copy(fontWeight = FontWeight.SemiBold), color = Theme.colors.textSecondary)
    }
}

// endregion

// region Callouts and badges

/** A blue tip or notice: an info (or lock) icon and short text. */
@Composable
fun TipCallout(text: String, modifier: Modifier = Modifier, icon: ImageVector = Icons.Outlined.Info, tag: String? = null) {
    TipCallout(androidx.compose.ui.text.AnnotatedString(text), modifier, icon, tag)
}

@Composable
fun TipCallout(text: androidx.compose.ui.text.AnnotatedString, modifier: Modifier = Modifier, icon: ImageVector = Icons.Outlined.Info,
               tag: String? = null) {
    Row(
        modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.Radius.input)).background(Theme.colors.tip)
            .semantics(mergeDescendants = true) {}.tagged(tag).padding(horizontal = 14.dp, vertical = Theme.Space.m),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(icon, null, tint = Theme.colors.tipIcon, modifier = Modifier.size(18.dp))
        Text(text, style = Theme.Fonts.footnote, color = Theme.colors.tipOn, modifier = Modifier.weight(1f))
    }
}

/** A small pill: brand tint fill, pressed-brand text ("added for you"). */
@Composable
fun Badge(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier.clip(RoundedCornerShape(50)).background(Theme.colors.brandTint).padding(horizontal = Theme.Space.s, vertical = 2.dp),
        style = Theme.Fonts.caption, color = Theme.colors.brandPressed)
}

/** Initials in a tinted circle (a client, the business). */
@Composable
fun Avatar(name: String, modifier: Modifier = Modifier, size: Dp = 40.dp, tip: Boolean = false) {
    Box(modifier.size(size).clip(CircleShape).background(if (tip) Theme.colors.tip else Theme.colors.brandTint),
        contentAlignment = Alignment.Center) {
        Text(initials(name), style = Theme.Fonts.subhead.copy(fontWeight = FontWeight.Bold),
            color = if (tip) Theme.colors.tipOn else Theme.colors.brandPressed)
    }
}

/** The first letters of the first two words ("Rao Traders" → "RT"). */
fun initials(name: String): String {
    val letters = name.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }.take(2).joinToString("") { it.first().uppercase() }
    return letters.ifEmpty { "?" }
}

// endregion

// region Rows and fields

/**
 * A checklist row: a ring (or a filled brand check when done), a title and hint, and a chevron when it opens
 * something. Done rows are struck through.
 */
@Composable
fun ChecklistRow(title: String, isDone: Boolean, modifier: Modifier = Modifier, hint: String? = null, onClick: (() -> Unit)? = null,
                 tag: String? = null) {
    val clickable = onClick != null && !isDone
    Row(
        modifier.fillMaxWidth().heightIn(min = if (isDone) 52.dp else 60.dp)
            .let { if (clickable) it.clickable(role = Role.Button) { onClick!!.invoke() } else it }
            .semantics(mergeDescendants = true) { stateDescription = if (isDone) "Done" else "Not done" }.tagged(tag),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Theme.Space.m),
    ) {
        if (isDone) {
            Box(Modifier.size(26.dp).clip(CircleShape).background(Theme.colors.brand), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Check, null, tint = Theme.colors.brandOn, modifier = Modifier.size(16.dp))
            }
        } else {
            Box(Modifier.size(26.dp).border(2.dp, Theme.colors.control, CircleShape))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = if (isDone) Theme.Fonts.callout.copy(textDecoration = TextDecoration.LineThrough) else Theme.Fonts.rowTitle,
                color = if (isDone) Theme.colors.textSecondary else Theme.colors.textPrimary)
            if (hint != null && !isDone) Text(hint, style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
        }
        if (clickable) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Theme.colors.textTertiary)
    }
}

/** A row with a switch whose hint changes with its state (iOS: `SwitchRow(title:hintOn:hintOff:isOn:)`). */
@Composable
fun SwitchRow(title: String, hintOn: String, hintOff: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit,
              modifier: Modifier = Modifier, tag: String? = null) {
    Row(
        modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.Radius.input)).background(Theme.colors.background)
            .toggleable(checked, role = Role.Switch, onValueChange = onCheckedChange).tagged(tag)
            .padding(horizontal = 14.dp, vertical = Theme.Space.m),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Theme.Space.m),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = Theme.Fonts.rowTitle, color = Theme.colors.textPrimary)
            Text(if (checked) hintOn else hintOff, style = Theme.Fonts.caption.copy(fontWeight = FontWeight.Normal),
                color = Theme.colors.textSecondary)
        }
        Switch(checked, onCheckedChange = null, colors = SwitchDefaults.colors(
            checkedTrackColor = Theme.colors.brand, uncheckedTrackColor = Theme.colors.control,
            uncheckedThumbColor = Theme.colors.surface, uncheckedBorderColor = Theme.colors.control,
        ))
    }
}

/** A checkbox row: a 20 dp rounded square, filled with brand and ticked when on. */
@Composable
fun CheckboxRow(title: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit, modifier: Modifier = Modifier, tag: String? = null) {
    Row(
        modifier.fillMaxWidth().heightIn(min = Theme.Layout.minTouchTarget)
            .toggleable(checked, role = Role.Checkbox, onValueChange = onCheckedChange).tagged(tag),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        val shape = RoundedCornerShape(5.dp)
        Box(Modifier.size(20.dp).clip(shape).background(if (checked) Theme.colors.brand else Theme.colors.surface)
            .border(2.dp, if (checked) Theme.colors.brand else Theme.colors.control, shape), contentAlignment = Alignment.Center) {
            if (checked) Icon(Icons.Filled.Check, null, tint = Theme.colors.brandOn, modifier = Modifier.size(14.dp))
        }
        Text(title, style = Theme.Fonts.subhead, color = Theme.colors.textPrimary)
    }
}

/** The input look: 50 high, radius 14, a 1.5 dp strong border (2 dp brand while focused). */
fun Modifier.inputBox(colors: AppColors, focused: Boolean = false): Modifier {
    val shape = RoundedCornerShape(Theme.Radius.input)
    return this.fillMaxWidth().heightIn(min = Theme.Layout.inputHeight).clip(shape).background(colors.surface)
        .border(if (focused) 2.dp else 1.5.dp, if (focused) colors.brand else colors.borderStrong, shape)
        .padding(horizontal = 14.dp)
}

/** A field label above an input ("What did you sell?"). */
@Composable
fun FieldLabel(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier, style = Theme.Fonts.subhead.copy(fontWeight = FontWeight.Bold), color = Theme.colors.textPrimary)
}

/**
 * A labelled input outside a form: a label above a boxed text field, and the problem (or a hint) underneath. iOS:
 * `BoxedTextField`.
 */
@Composable
fun BoxedTextField(
    title: String, value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier, prompt: String? = null,
    issue: String? = null, hint: String? = null, keyboard: KeyboardType = KeyboardType.Text, tag: String? = null,
    leading: String? = null, singleLine: Boolean = true,
) {
    val colors = Theme.colors
    var focused by remember { mutableStateOf(false) }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        FieldLabel(title)
        BasicTextField(
            value = value,
            onValueChange = { onValueChange(if (keyboard == KeyboardType.Decimal) DecimalPadText.normalized(it) else it) },
            modifier = Modifier.fillMaxWidth().tagged(tag)
                .onFocusChanged { focused = it.isFocused }
                .semantics { contentDescription = title; if (issue != null) error(issue) },
            singleLine = singleLine,
            textStyle = Theme.Fonts.body.copy(color = colors.textPrimary),
            cursorBrush = SolidColor(colors.brand),
            keyboardOptions = KeyboardOptions(keyboardType = keyboard),
            decorationBox = { field ->
                Row(Modifier.inputBox(colors, focused), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (leading != null) Text(leading, style = Theme.Fonts.body, color = colors.textSecondary)
                    Box(Modifier.weight(1f)) {
                        if (value.isEmpty() && prompt != null) Text(prompt, style = Theme.Fonts.body, color = colors.textSecondary)
                        field()
                    }
                }
            },
        )
        when {
            issue != null -> IssueText(issue)
            hint != null -> Text(hint, style = Theme.Fonts.caption.copy(fontWeight = FontWeight.Normal), color = colors.textSecondary)
        }
    }
}

/** An input-shaped box with − / value / + ; the value can also be typed (decimal quantities). */
@Composable
fun QuantityStepper(value: String, onValueChange: (String) -> Unit, onDecrement: () -> Unit, onIncrement: () -> Unit,
                    modifier: Modifier = Modifier, name: String = "Quantity", tag: String? = null) {
    val colors = Theme.colors
    val shape = RoundedCornerShape(Theme.Radius.input)
    Row(
        modifier.fillMaxWidth().heightIn(min = Theme.Layout.inputHeight).clip(shape).background(colors.surface)
            .border(1.5.dp, colors.borderStrong, shape).padding(horizontal = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StepButton(Icons.Filled.Remove, "Fewer", onDecrement)
        BasicTextField(
            value, { onValueChange(DecimalPadText.normalized(it)) },
            Modifier.weight(1f).tagged(tag).semantics { contentDescription = name },
            singleLine = true, textStyle = Theme.Fonts.button.copy(color = colors.textPrimary, textAlign = TextAlign.Center),
            cursorBrush = SolidColor(colors.brand), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        )
        StepButton(Icons.Filled.Add, "More", onIncrement)
    }
}

@Composable
private fun StepButton(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(
        Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(Theme.colors.surfaceMuted)
            .clickable(role = Role.Button, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = Theme.colors.textPrimary, modifier = Modifier.size(18.dp)) }
}

/** A money tile before there is any money: a dashed border, the amount in the display face and a label. */
@Composable
fun EmptyStatTile(amount: String, label: String, modifier: Modifier = Modifier) {
    val dashColor = Theme.colors.borderStrong
    Column(
        modifier.semantics(mergeDescendants = true) {}.drawDashedBorder(dashColor, Theme.Radius.l)
            .padding(horizontal = 10.dp, vertical = Theme.Space.m),
        verticalArrangement = Arrangement.spacedBy(Theme.Space.xs),
    ) {
        Text(amount, style = Theme.Fonts.title3, color = Theme.colors.textPrimary, maxLines = 1)
        Text(label, style = Theme.Fonts.caption.copy(fontWeight = FontWeight.Normal), color = Theme.colors.textSecondary)
    }
}

/** A money tile with a value: the amount in the display face and a label. */
@Composable
fun StatTile(amount: String, label: String, modifier: Modifier = Modifier, emphasis: Color? = null) {
    val shape = RoundedCornerShape(Theme.Radius.l)
    Column(
        modifier.clip(shape).background(Theme.colors.surface).border(1.dp, Theme.colors.border, shape)
            .semantics(mergeDescendants = true) {}.padding(horizontal = 10.dp, vertical = Theme.Space.m),
        verticalArrangement = Arrangement.spacedBy(Theme.Space.xs),
    ) {
        Text(amount, style = Theme.Fonts.title3.copy(fontFeatureSettings = "tnum"), color = emphasis ?: Theme.colors.textPrimary, maxLines = 1)
        Text(label, style = Theme.Fonts.caption.copy(fontWeight = FontWeight.Normal), color = Theme.colors.textSecondary)
    }
}

private fun Modifier.drawDashedBorder(color: Color, radius: Dp): Modifier = this.drawBehind {
    drawRoundRect(
        color = color, cornerRadius = CornerRadius(radius.toPx()),
        style = Stroke(width = 1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))),
    )
}

/** A thin divider in the muted ground colour, as between checklist and line rows. */
@Composable
fun MutedDivider(modifier: Modifier = Modifier) = HorizontalDivider(modifier, color = Theme.colors.surfaceMuted)

// endregion
