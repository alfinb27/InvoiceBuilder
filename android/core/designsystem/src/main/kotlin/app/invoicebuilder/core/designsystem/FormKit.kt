package app.invoicebuilder.core.designsystem

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

// The grouped-form pieces SwiftUI gives for free (`Form`, `Section`, `Picker`, `Toggle`, `LabeledContent`). Material
// has no grouped form, so these draw one: a titled card per section with a footer underneath.

/** ≈ `Section(header) { … } footer: { … }` in a grouped `Form`. */
@Composable
fun FormSection(
    header: String? = null,
    footer: String? = null,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(horizontal = Theme.Space.l, vertical = Theme.Space.s),
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier.fillMaxWidth().padding(vertical = Theme.Space.s)) {
        if (header != null) {
            Text(
                header.uppercase(), Modifier.padding(start = Theme.Space.l, bottom = Theme.Space.xs),
                style = MaterialTheme.typography.labelMedium, color = Theme.colors.textSecondary,
            )
        }
        Card(
            colors = CardDefaults.cardColors(containerColor = Theme.colors.surface),
            shape = MaterialTheme.shapes.medium,
        ) {
            Column(Modifier.fillMaxWidth().padding(contentPadding), verticalArrangement = Arrangement.spacedBy(Theme.Space.xs), content = content)
        }
        if (footer != null) {
            Text(
                footer, Modifier.padding(start = Theme.Space.l, end = Theme.Space.l, top = Theme.Space.xs),
                style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary,
            )
        }
    }
}

/** A row that selects one option (≈ a `Button` row with a checkmark when selected). */
@Composable
fun ChoiceRow(title: String, selected: Boolean, onSelect: () -> Unit, subtitle: String? = null, enabled: Boolean = true, tag: String? = null) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Theme.Layout.minTouchTarget)
            .selectable(selected, enabled = enabled, role = Role.RadioButton, onClick = onSelect)
            .let { if (tag != null) it.testTag(tag) else it }
            .padding(vertical = Theme.Space.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, color = if (enabled) Theme.colors.textPrimary else Theme.colors.textTertiary)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
        }
        if (selected) Icon(Icons.Filled.Check, "Selected", tint = Theme.colors.brand)
    }
}

/** A tappable row that opens something (≈ a `NavigationLink` row). */
@Composable
fun NavRow(title: String, onClick: () -> Unit, value: String? = null, icon: ImageVector? = null, subtitle: String? = null, tag: String? = null, tint: androidx.compose.ui.graphics.Color? = null) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Theme.Layout.minTouchTarget).clickable(onClick = onClick)
            .let { if (tag != null) it.testTag(tag) else it }.padding(vertical = Theme.Space.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = tint ?: Theme.colors.brand)
            Spacer(Modifier.size(Theme.Space.m))
        }
        Column(Modifier.weight(1f)) {
            Text(title, color = tint ?: Theme.colors.textPrimary)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
        }
        if (value != null) Text(value, color = Theme.colors.textSecondary, modifier = Modifier.padding(start = Theme.Space.s))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Theme.colors.textTertiary)
    }
}

/** ≈ `Toggle(title, isOn:)`. */
@Composable
fun SwitchRow(title: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit, subtitle: String? = null, enabled: Boolean = true, tag: String? = null) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Theme.Layout.minTouchTarget)
            .toggleable(checked, enabled = enabled, role = Role.Switch, onValueChange = onCheckedChange)
            .let { if (tag != null) it.testTag(tag) else it },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
        }
        Switch(checked, onCheckedChange = null, enabled = enabled)
    }
}

/** ≈ `LabeledContent(title) { value }`. */
@Composable
fun LabeledValue(title: String, value: String, modifier: Modifier = Modifier, emphasized: Boolean = false, valueTag: String? = null) {
    Row(modifier.fillMaxWidth().heightIn(min = 32.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), color = if (emphasized) Theme.colors.textPrimary else Theme.colors.textSecondary,
            fontWeight = if (emphasized) FontWeight.SemiBold else null)
        Text(value, fontWeight = if (emphasized) FontWeight.Bold else null,
            modifier = if (valueTag != null) Modifier.testTag(valueTag) else Modifier)
    }
}

/**
 * ≈ `Picker(title, selection:)` with `.navigationLink` style: a field that opens a searchable list of options in a
 * dialog. [options] are (value, label) pairs; [none] adds a "Choose"/"None" first entry for optional values.
 */
@Composable
fun <T> PickerField(
    title: String,
    selection: T?,
    options: List<Pair<T, String>>,
    onSelect: (T?) -> Unit,
    modifier: Modifier = Modifier,
    none: String? = null,
    issue: String? = null,
    searchable: Boolean = options.size > 12,
    enabled: Boolean = true,
    tag: String? = null,
) {
    var open by rememberSaveable { mutableStateOf(false) }
    val label = options.firstOrNull { it.first == selection }?.second ?: none ?: "Choose"
    Column(modifier.fillMaxWidth()) {
        Box {
            OutlinedTextField(
                value = label, onValueChange = {}, readOnly = true, enabled = enabled, label = { Text(title) },
                isError = issue != null, trailingIcon = { Icon(Icons.Filled.ArrowDropDown, null) },
                modifier = Modifier.fillMaxWidth(),
            )
            // A transparent layer takes the tap: a read-only text field would otherwise swallow it.
            Box(Modifier.matchParentSize().clickable(enabled = enabled, role = Role.DropdownList) { open = true }
                .let { if (tag != null) it.testTag(tag) else it })
        }
        if (issue != null) IssueText(issue, Modifier.padding(top = Theme.Space.xxs))
    }
    if (open) {
        var query by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { open = false },
            title = { Text(title) },
            text = {
                Column {
                    if (searchable) {
                        OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth(), placeholder = { Text("Search") }, singleLine = true)
                        Spacer(Modifier.size(Theme.Space.s))
                    }
                    val shown = options.filter { query.isBlank() || it.second.contains(query.trim(), ignoreCase = true) }
                    LazyColumn(Modifier.heightIn(max = 420.dp)) {
                        if (none != null && query.isBlank()) {
                            item { ChoiceRow(none, selection == null, { onSelect(null); open = false }) }
                        }
                        items(shown) { (value, text) ->
                            ChoiceRow(text, value == selection, { onSelect(value); open = false })
                            HorizontalDivider(color = Theme.colors.border.copy(alpha = 0.5f))
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton({ open = false }) { Text("Cancel") } },
        )
    }
}

/** A segmented choice (≈ `Picker` with `.segmented` style). */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun <T> SegmentedChoice(options: List<Pair<T, String>>, selection: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier, tagPrefix: String? = null) {
    androidx.compose.material3.SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { index, (value, label) ->
            SegmentedButton(
                selected = value == selection, onClick = { onSelect(value) },
                shape = androidx.compose.material3.SegmentedButtonDefaults.itemShape(index, options.size),
                modifier = if (tagPrefix != null) Modifier.testTag("$tagPrefix-$value") else Modifier,
            ) { Text(label, maxLines = 1) }
        }
    }
}

/** A short red alert row with an icon, inside a section. */
@Composable
fun SectionDivider() = HorizontalDivider(color = Theme.colors.border.copy(alpha = 0.6f))
