package app.invoicebuilder.android.common

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.invoicebuilder.core.designsystem.ReadableColumn
import app.invoicebuilder.core.designsystem.Theme

/**
 * List and detail side by side from the regular-width breakpoint (≈ `NavigationSplitView`), or the list with the
 * detail pushed over it on phones; system Back closes the detail. [hasSelection] is the router's selection, so the
 * layout follows the router however the window changes (ADR-0014).
 */
@Composable
fun ListDetail(
    hasSelection: Boolean,
    onCloseDetail: () -> Unit,
    list: @Composable (twoPane: Boolean) -> Unit,
    detail: @Composable (twoPane: Boolean) -> Unit,
    empty: @Composable () -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val width = maxWidth
        val twoPane = width >= Theme.Layout.regularWidthBreakpoint
        if (twoPane) {
            Row(Modifier.fillMaxSize()) {
                Box(Modifier.width(if (width >= 1000.dp) 400.dp else 340.dp).fillMaxHeight()) { list(true) }
                VerticalDivider(color = Theme.colors.border)
                Box(Modifier.weight(1f).fillMaxHeight()) { if (hasSelection) detail(true) else empty() }
            }
        } else {
            BackHandler(enabled = hasSelection, onBack = onCloseDetail)
            if (hasSelection) detail(false) else list(false)
        }
    }
}

/** ≈ `ContentUnavailableView`. */
@Composable
fun EmptyState(title: String, icon: ImageVector, description: String? = null, action: Pair<String, () -> Unit>? = null) {
    Column(Modifier.fillMaxSize().padding(Theme.Space.xl), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, null, Modifier.size(48.dp), tint = Theme.colors.textTertiary)
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = Theme.Space.m), textAlign = TextAlign.Center)
        if (description != null) Text(description, color = Theme.colors.textSecondary, textAlign = TextAlign.Center)
        if (action != null) androidx.compose.material3.Button(action.second, Modifier.padding(top = Theme.Space.m)) { Text(action.first) }
    }
}

/**
 * A modal editor with Cancel and Save (≈ a `.sheet` holding a `NavigationStack` form). Full screen on phones, a
 * centred card on wide windows.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorSheet(
    title: String,
    onCancel: () -> Unit,
    onSave: (() -> Unit)?,
    saveEnabled: Boolean = true,
    saveTitle: String = "Save",
    isBusy: Boolean = false,
    saveTag: String = "editorSave",
    content: @Composable ColumnScope.() -> Unit,
) {
    Dialog(onCancel, DialogProperties(usePlatformDefaultWidth = false, dismissOnClickOutside = false, decorFitsSystemWindows = false)) {
        BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            val wide = maxWidth >= Theme.Layout.regularWidthBreakpoint
            val modifier = if (wide) Modifier.width(640.dp).fillMaxHeight(0.9f) else Modifier.fillMaxSize()
            androidx.compose.material3.Surface(modifier, shape = if (wide) MaterialTheme.shapes.large else androidx.compose.ui.graphics.RectangleShape,
                color = Theme.colors.background) {
                Scaffold(
                    containerColor = Theme.colors.background,
                    topBar = {
                        TopAppBar(
                            title = { Text(title) },
                            navigationIcon = { IconButton(onCancel, Modifier.testTag("editorCancel")) { Icon(Icons.Filled.Close, "Cancel") } },
                            actions = {
                                if (onSave != null) {
                                    if (isBusy) CircularProgressIndicator(Modifier.size(20.dp).padding(end = Theme.Space.m))
                                    TextButton(onSave, enabled = saveEnabled && !isBusy, modifier = Modifier.testTag(saveTag)) { Text(saveTitle) }
                                }
                            },
                            colors = TopAppBarDefaults.topAppBarColors(containerColor = Theme.colors.background),
                        )
                    },
                ) { padding ->
                    Column(Modifier.fillMaxSize().padding(padding).imePadding().verticalScroll(rememberScrollState()).padding(horizontal = Theme.Space.l)) {
                        ReadableColumn { Column(content = content) }
                    }
                }
            }
        }
    }
}

/** ≈ `.searchable(text:prompt:)`. */
@Composable
fun SearchField(text: String, onChange: (String) -> Unit, prompt: String, modifier: Modifier = Modifier) {
    OutlinedTextField(
        text, onChange, modifier.fillMaxWidth().testTag("search"),
        placeholder = { Text(prompt, maxLines = 1) }, singleLine = true,
        leadingIcon = { Icon(Icons.Filled.Search, null) },
        trailingIcon = { if (text.isNotEmpty()) IconButton({ onChange("") }) { Icon(Icons.Filled.Close, "Clear") } },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        shape = MaterialTheme.shapes.extraLarge,
    )
}

/** ≈ `.alert("Something went wrong", …)`. */
@Composable
fun ErrorAlert(message: String?, onDismiss: () -> Unit, title: String = "Something went wrong") {
    if (message == null) return
    AlertDialog(onDismiss, title = { Text(title) }, text = { Text(message) }, confirmButton = { TextButton(onDismiss) { Text("OK") } })
}

/** ≈ `.confirmationDialog` with one destructive action. */
@Composable
fun ConfirmDialog(title: String, message: String?, confirmTitle: String, onConfirm: () -> Unit, onDismiss: () -> Unit, destructive: Boolean = true, confirmTag: String? = null) {
    AlertDialog(
        onDismiss, title = { Text(title) }, text = message?.let { { Text(it) } },
        confirmButton = {
            TextButton({ onConfirm(); onDismiss() }, modifier = if (confirmTag != null) Modifier.testTag(confirmTag) else Modifier) {
                Text(confirmTitle, color = if (destructive) Theme.colors.danger else Theme.colors.brand)
            }
        },
        dismissButton = { TextButton(onDismiss) { Text("Cancel") } },
    )
}

/** Detail panes: a scrolling, readable-width column. */
@Composable
fun DetailColumn(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = Theme.Space.l)) {
        ReadableColumn(Modifier.fillMaxWidth()) { Column(content = content) }
    }
}
