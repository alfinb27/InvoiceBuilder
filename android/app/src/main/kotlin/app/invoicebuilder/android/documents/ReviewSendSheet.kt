package app.invoicebuilder.android.documents

import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.core.designsystem.PrimaryButton
import app.invoicebuilder.core.designsystem.TextLinkButton
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.designsystem.TipCallout
import app.invoicebuilder.core.designsystem.readableWidth
import app.invoicebuilder.core.domain.models.DocumentType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Review & send (`spec/documents.md` §6.1, `docs/design/design.md` §6.6): what is being sent, the number it will get
 * and that it locks, the channel, and what happens next. Its button closes the review; the document is issued and the
 * channel opens once it is gone (`DocumentViewModel.sendAfterReview`). iOS: `ReviewSendView`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReviewSendSheet(model: DocumentViewModel, session: Session) {
    var channel by rememberSaveable { mutableStateOf(SendChannel.whatsApp) }
    var fullPreview by rememberSaveable { mutableStateOf(false) }
    val document = model.document
    val noun = DocumentText.noun(document.docType)
    Dialog(model::keepAsDraft, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Surface(Modifier.fillMaxSize(), color = Theme.colors.background) {
            Scaffold(
                containerColor = Theme.colors.background,
                topBar = {
                    TopAppBar(
                        title = {},
                        navigationIcon = {
                            IconButton(model::keepAsDraft, Modifier.testTag("review.back")) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back to editing") }
                        },
                        colors = TopAppBarDefaults.topAppBarColors(containerColor = Theme.colors.background),
                    )
                },
                bottomBar = {
                    Box(Modifier.fillMaxWidth().background(Theme.colors.background), contentAlignment = Alignment.Center) {
                        Column(Modifier.readableWidth().padding(horizontal = Theme.Layout.screenGutter, vertical = Theme.Space.m),
                            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Theme.Space.xs)) {
                            PrimaryButton(channel.buttonTitle(document.docType), { model.send(channel) }, tag = "review.send")
                            TextLinkButton("Keep as draft", model::keepAsDraft, tag = "review.keepDraft")
                        }
                    }
                },
            ) { padding ->
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
                    Column(Modifier.readableWidth().fillMaxWidth().verticalScroll(rememberScrollState())
                        .padding(horizontal = Theme.Layout.screenGutter, vertical = Theme.Space.s),
                        verticalArrangement = Arrangement.spacedBy(Theme.Space.m)) {
                        Text("Looks good. Ready to send?", style = Theme.Fonts.title3, color = Theme.colors.textPrimary,
                            modifier = Modifier.semantics { heading() })
                        Summary(model, session, noun) { fullPreview = true }
                        val reason = if (document.docType == DocumentType.invoice && model.chargesTax)
                            "so your ${model.config.labels.taxName} records stay correct." else "so it can't change once your client has it."
                        TipCallout(buildAnnotatedString {
                            append("Sending gives it the number")
                            model.numberPreview?.let { append(" "); withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(it) } }
                            append(" and locks it, $reason Not ready? It stays a draft you can edit.")
                        }, icon = Icons.Outlined.Lock, tag = "review.lockTip")
                        Text("Send it by", style = Theme.Fonts.headline, color = Theme.colors.textPrimary,
                            modifier = Modifier.padding(top = Theme.Space.s).semantics { heading() })
                        Channels(channel) { channel = it }
                        Text("What happens next", style = Theme.Fonts.headline, color = Theme.colors.textPrimary,
                            modifier = Modifier.padding(top = Theme.Space.s).semantics { heading() })
                        Timeline(nextSteps(model, session))
                    }
                }
            }
        }
    }
    if (fullPreview) {
        val computed = model.computed
        if (computed != null) {
            val preview = androidx.compose.runtime.remember(computed) {
                DocumentPreviewViewModel(session, model.documentToRender, computed, null) {}
            }
            DocumentPreviewScreen(preview) { fullPreview = false }
        }
    }
}

@Composable
private fun Summary(model: DocumentViewModel, session: Session, noun: String, onSeeFull: () -> Unit) {
    val document = model.document
    val shape = RoundedCornerShape(Theme.Radius.card)
    val thumbnail by produceState<Bitmap?>(null, document.updatedAt) {
        val computed = model.computed ?: return@produceState
        value = runCatching {
            val file = session.pdfLibrary.file(model.documentToRender, session.business, computed, document.templateId).file
            withContext(Dispatchers.IO) {
                PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)).use { renderer ->
                    renderer.openPage(0).use { page ->
                        val bitmap = Bitmap.createBitmap(276, (276f * page.height / page.width).toInt(), Bitmap.Config.ARGB_8888)
                        bitmap.eraseColor(AndroidColor.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        bitmap
                    }
                }
            }
        }.getOrNull()
    }
    Row(Modifier.fillMaxWidth().clip(shape).background(Theme.colors.surface).border(1.dp, Theme.colors.border, shape).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.width(92.dp).heightIn(min = 122.dp).clip(RoundedCornerShape(8.dp)).background(androidx.compose.ui.graphics.Color.White)
            .border(1.dp, Theme.colors.border, RoundedCornerShape(8.dp))) {
            thumbnail?.let { Image(it.asImageBitmap(), null, Modifier.size(92.dp, 122.dp), contentScale = ContentScale.Fit) }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            val name = model.client?.name ?: document.buyerSnapshot?.name
            val capitalised = noun.replaceFirstChar { it.uppercase() }
            Text(name?.let { "$capitalised to $it" } ?: "$capitalised for a walk-in customer", style = Theme.Fonts.footnote,
                color = Theme.colors.textSecondary)
            Text(model.computed?.let { session.money(it.totals.total, document.currency) } ?: "—", style = Theme.Fonts.amountLarge,
                color = Theme.colors.textPrimary, maxLines = 1)
            val count = document.lines.size
            val taxed = model.computed?.let { it.chargesTax && it.totals.tax != 0L } == true
            Text("$count item${if (count == 1) "" else "s"}" + if (taxed) " · ${model.config.labels.taxName} included" else "",
                style = Theme.Fonts.footnote, color = Theme.colors.textSecondary)
            val dateLine = if (document.docType == DocumentType.quote) document.validUntil?.let { "Valid until ${it.displayText}" }
            else document.dueDate?.let { "Due ${it.displayText}" }
            dateLine?.let { Text(it, style = Theme.Fonts.footnote, color = Theme.colors.textSecondary) }
            TextLinkButton("See full $noun", onSeeFull, tag = "review.seeFull")
        }
    }
}

@Composable
private fun Channels(selected: SendChannel, onSelect: (SendChannel) -> Unit) {
    BoxWithConstraints {
        val columns = if (maxWidth < 300.dp) 2 else 4
        Column(verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
            SendChannel.entries.chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
                    for (option in row) {
                        val on = option == selected
                        val shape = RoundedCornerShape(Theme.Radius.l)
                        Column(Modifier.weight(1f).heightIn(min = 76.dp).clip(shape)
                            .background(if (on) Theme.colors.brandTint else Theme.colors.surface)
                            .border(if (on) 2.dp else 1.dp, if (on) Theme.colors.brand else Theme.colors.border, shape)
                            .selectable(on, role = Role.RadioButton) { onSelect(option) }.testTag("channel-${option.name}")
                            .padding(vertical = Theme.Space.s), horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically)) {
                            Box(Modifier.size(36.dp).clip(CircleShape).background(if (on) Theme.colors.brand else Theme.colors.surfaceMuted),
                                contentAlignment = Alignment.Center) {
                                Icon(option.icon, null, tint = if (on) Theme.colors.brandOn else Theme.colors.textPrimary, modifier = Modifier.size(20.dp))
                            }
                            Text(option.label, style = Theme.Fonts.caption, color = Theme.colors.textPrimary, maxLines = 1)
                        }
                    }
                }
            }
        }
    }
}

private data class NextStep(val title: String, val hint: String? = null)

private fun nextSteps(model: DocumentViewModel, session: Session): List<NextStep> {
    val document = model.document
    if (document.docType == DocumentType.quote) {
        return listOf(NextStep("Shown as “Sent” in your quotes"), NextStep("Mark it accepted or declined when your client answers"),
            NextStep("Turn it into an invoice in one tap"))
    }
    val days = document.reminderDaysAfterDueOverride ?: session.business.reminderDaysAfterDue
    val due = document.dueDate
    val reminder = when {
        due != null && days != null -> NextStep("We nudge you if it's unpaid by ${due.plusDays(days.toLong()).displayText}",
            "A reminder on your phone. Nothing is sent to your client.")
        due != null -> NextStep("It shows as past due if it's unpaid after ${due.displayText}",
            "Turn on payment reminders in Settings to get a nudge on your phone.")
        else -> NextStep("It shows as waiting to be paid until it is")
    }
    return listOf(NextStep("Shown as “Sent” on your home screen"), reminder, NextStep("Tap “Record payment” when the money arrives"))
}

@Composable
private fun Timeline(steps: List<NextStep>) {
    Column {
        steps.forEachIndexed { index, step ->
            Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(Theme.Space.m)) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.padding(top = 4.dp).size(12.dp).clip(CircleShape)
                        .background(if (index == 0) Theme.colors.brand else Theme.colors.background)
                        .border(2.dp, if (index == 0) Theme.colors.brand else Theme.colors.control, CircleShape))
                    if (index < steps.size - 1) Box(Modifier.width(2.dp).heightIn(min = 30.dp).background(Theme.colors.borderStrong))
                }
                Column(Modifier.padding(bottom = if (index < steps.size - 1) Theme.Space.m else 0.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(step.title, style = Theme.Fonts.subhead.copy(fontWeight = FontWeight.SemiBold), color = Theme.colors.textPrimary)
                    step.hint?.let { Text(it, style = Theme.Fonts.caption.copy(fontWeight = FontWeight.Normal), color = Theme.colors.textSecondary) }
                }
            }
        }
    }
}
