package app.invoicebuilder.android.common

import android.graphics.Bitmap
import androidx.core.graphics.createBitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Draw
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.IssueText
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.models.ImagePayload
import kotlin.math.max
import kotlin.math.min

/** Logo and signature pickers, shared by onboarding (kept in memory until Finish) and Settings (saved at once). */
@Composable
fun ImagesFormSections(
    logo: ByteArray?,
    signature: ByteArray?,
    isBusy: Boolean,
    signatureNote: String?,
    onPickLogo: (Uri) -> Unit,
    onRemoveLogo: () -> Unit,
    onSaveSignature: (ImagePayload) -> Unit,
    onRemoveSignature: () -> Unit,
) {
    // The system photo picker (≈ `PhotosPicker`): no storage permission needed.
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> if (uri != null) onPickLogo(uri) }
    var showsPad by rememberSaveable { mutableStateOf(false) }

    FormSection("Logo", "Shown at the top of your invoices. Large images are resized to 1024 pixels.") {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Theme.Space.l)) {
            ImageWell(logo, "Logo")
            Column(Modifier.weight(1f)) {
                TextButton({ picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !isBusy,
                    modifier = Modifier.testTag("chooseLogo")) {
                    Icon(Icons.Filled.Image, null); Text("  " + if (logo == null) "Choose logo" else "Replace logo")
                }
                if (logo != null) {
                    TextButton(onRemoveLogo, enabled = !isBusy) {
                        Icon(Icons.Filled.Delete, null, tint = Theme.colors.danger); Text("  Remove logo", color = Theme.colors.danger)
                    }
                }
            }
            if (isBusy) CircularProgressIndicator(Modifier.size(24.dp))
        }
    }
    FormSection("Signature", signatureNote ?: "Printed above \"Authorised signatory\" on your invoices.") {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Theme.Space.l)) {
            ImageWell(signature, "Signature")
            Column(Modifier.weight(1f)) {
                TextButton({ showsPad = true }, enabled = !isBusy, modifier = Modifier.testTag("drawSignature")) {
                    Icon(Icons.Filled.Draw, null); Text("  " + if (signature == null) "Draw signature" else "Draw again")
                }
                if (signature != null) {
                    TextButton(onRemoveSignature, enabled = !isBusy) {
                        Icon(Icons.Filled.Delete, null, tint = Theme.colors.danger); Text("  Remove signature", color = Theme.colors.danger)
                    }
                }
            }
        }
    }
    if (showsPad) SignaturePadDialog(onSave = { onSaveSignature(it); showsPad = false }, onCancel = { showsPad = false })
}

/** A square preview of a stored image, on white as on paper, or a placeholder. */
@Composable
fun ImageWell(data: ByteArray?, label: String) {
    val bitmap = remember(data) { data?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } }
    Box(
        Modifier.size(72.dp).clip(RoundedCornerShape(Theme.Radius.s)).border(1.dp, Theme.colors.border, RoundedCornerShape(Theme.Radius.s))
            .background(if (bitmap != null) Color.White else Theme.colors.surfaceMuted)
            .semantics { contentDescription = if (data == null) "No ${label.lowercase()}" else "$label preview" },
        contentAlignment = Alignment.Center,
    ) {
        if (bitmap != null) Image(bitmap.asImageBitmap(), null, Modifier.padding(Theme.Space.xs), contentScale = ContentScale.Fit)
        else Icon(Icons.Outlined.Image, null, tint = Theme.colors.textTertiary)
    }
}

/** Draw a signature with a finger or stylus; saved as a transparent PNG (`spec/setup.md` §9). iOS: `SignaturePadSheet`. */
@Composable
fun SignaturePadDialog(onSave: (ImagePayload) -> Unit, onCancel: () -> Unit) {
    val strokes = remember { mutableStateListOf<List<Offset>>() }
    var current by remember { mutableStateOf<List<Offset>>(emptyList()) }
    var failed by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text("Signature") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Theme.Space.m)) {
                Box(
                    Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(Theme.Radius.m)).background(Color.White)
                        .border(1.dp, Theme.colors.border, RoundedCornerShape(Theme.Radius.m))
                        .semantics { contentDescription = "Signature pad" }.testTag("signaturePad"),
                ) {
                    Canvas(
                        Modifier.fillMaxWidth().height(200.dp).pointerInput(Unit) {
                            detectDragGestures(
                                onDragStart = { current = listOf(it) },
                                onDrag = { change, _ -> current = current + change.position },
                                onDragEnd = { if (current.size > 1) strokes.add(current); current = emptyList() },
                            )
                        },
                    ) {
                        // A signing line under the ink.
                        drawLine(Color.Gray.copy(alpha = 0.4f), Offset(24.dp.toPx(), size.height - 32.dp.toPx()),
                            Offset(size.width - 24.dp.toPx(), size.height - 32.dp.toPx()))
                        for (stroke in strokes + listOf(current)) {
                            if (stroke.size < 2) continue
                            val path = androidx.compose.ui.graphics.Path().apply {
                                moveTo(stroke[0].x, stroke[0].y)
                                stroke.drop(1).forEach { lineTo(it.x, it.y) }
                            }
                            drawPath(path, Color.Black, style = Stroke(4.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
                        }
                    }
                }
                Text("Sign with your finger or a stylus. It appears above \"Authorised signatory\" on your invoices.",
                    style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
                if (failed) IssueText("The signature couldn't be saved. Try again.")
            }
        },
        confirmButton = {
            TextButton({
                runCatching { exportSignature(strokes) }.onSuccess { it?.let(onSave) }.onFailure { failed = true }
            }, enabled = strokes.isNotEmpty(), modifier = Modifier.testTag("saveSignature")) { Text("Save") }
        },
        dismissButton = {
            Row {
                TextButton({ strokes.clear() }, enabled = strokes.isNotEmpty()) { Text("Clear", color = Theme.colors.danger) }
                TextButton(onCancel) { Text("Cancel") }
            }
        },
    )
}

/** The ink cropped to its bounds plus 8 px, at most 1024 px on its longest side, black on transparent. */
private fun exportSignature(strokes: List<List<Offset>>): ImagePayload? {
    val points = strokes.flatten()
    if (points.isEmpty()) return null
    val minX = points.minOf { it.x }; val maxX = points.maxOf { it.x }
    val minY = points.minOf { it.y }; val maxY = points.maxOf { it.y }
    val longest = max(max(maxX - minX, maxY - minY), 1f)
    val scale = min(3f, (ImageProcessing.MAX_PIXEL_SIZE - 16) / longest)
    val inkWidth = 4f * scale
    val pad = 8f + inkWidth
    val width = ((maxX - minX) * scale + pad * 2).toInt().coerceAtLeast(1)
    val height = ((maxY - minY) * scale + pad * 2).toInt().coerceAtLeast(1)
    val bitmap = createBitmap(width, height)
    val canvas = android.graphics.Canvas(bitmap)
    val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
        color = android.graphics.Color.BLACK; style = android.graphics.Paint.Style.STROKE; strokeWidth = inkWidth
        strokeCap = android.graphics.Paint.Cap.ROUND; strokeJoin = android.graphics.Paint.Join.ROUND
    }
    for (stroke in strokes) {
        val path = android.graphics.Path()
        stroke.forEachIndexed { index, point ->
            val x = (point.x - minX) * scale + pad
            val y = (point.y - minY) * scale + pad
            if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        canvas.drawPath(path, paint)
    }
    return ImageProcessing.signature(bitmap)
}
