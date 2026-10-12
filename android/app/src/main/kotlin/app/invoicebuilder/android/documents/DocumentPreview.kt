package app.invoicebuilder.android.documents

import android.graphics.Bitmap
import androidx.core.graphics.createBitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.common.ErrorAlert
import app.invoicebuilder.android.common.SystemSheets
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.documents.Document
import app.invoicebuilder.core.domain.models.TemplateID
import app.invoicebuilder.core.domain.pdf.PDFTemplate
import app.invoicebuilder.core.domain.tax.ComputedDocument
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** Renders a document to PDF and keeps the file for sharing and printing. iOS: `DocumentPreviewViewModel`. */
class DocumentPreviewViewModel(
    private val session: Session,
    private var document: Document,
    private val computed: ComputedDocument,
    /** Set only when opened from "Send reminder" (`spec/reminders.md` §4): shared alongside the PDF. */
    val reminderMessage: String?,
    /** Set when opened by Review & send: the channel opens as soon as the PDF is ready (`documents.md` §6.1). */
    channel: SendChannel? = null,
    private val onSent: (Long) -> Unit,
) {
    var pendingChannel by mutableStateOf(channel)
        private set

    /** The Review & send channel, once. */
    fun takePendingChannel(): SendChannel? = pendingChannel.also { pendingChannel = null }

    /** The client's email, for "Send by email". */
    val recipient: String? get() = document.buyerSnapshot?.email
    val emailSubject: String get() = "${DocumentText.noun(document.docType).replaceFirstChar { it.uppercase() }} ${document.number ?: ""} from ${session.business.name}"

    @set:JvmName("assignTemplate")
    var template by mutableStateOf(document.templateId)
        private set
    var file by mutableStateOf<File?>(null)
        private set
    var isRendering by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
    var askToMarkSent by mutableStateOf(false)
    var sentAt by mutableStateOf(document.sentAt)
        private set

    val templates: List<PDFTemplate> get() = session.pdfLibrary.allTemplates
    val title: String get() = document.number ?: DocumentText.title(document, true)
    val canMarkSent: Boolean get() = !document.isDraft && sentAt == null
    val paperSize: String get() = session.container.taxConfigs.config(document.taxConfigRef)?.paperSize ?: session.config.paperSize

    suspend fun render() {
        isRendering = true
        try {
            val cached = session.pdfLibrary.file(document, session.business, computed, template).file
            file = session.pdfLibrary.shareableCopy(cached, DocumentText.pdfFileName(document), document.id)
        } catch (error: Exception) {
            errorMessage = "The PDF couldn't be created."
        } finally {
            isRendering = false
        }
    }

    fun setTemplate(id: TemplateID) {
        if (id == template) return
        template = id
        file = null
        session.scope.launch { render() }
    }

    /** Back from the share sheet or the printer: offer to mark the document as sent. */
    fun didShare() { if (canMarkSent) askToMarkSent = true }

    fun markSent() {
        session.scope.launch {
            try {
                val now = session.container.time.now()
                session.container.documents.markSent(document.id, now)
                sentAt = now
                document = document.copy(sentAt = now)
                onSent(now)
            } catch (error: Exception) {
                errorMessage = "The ${DocumentText.noun(document.docType)} couldn't be marked as sent."
            }
        }
    }
}

/** The preview: the rendered pages, a template switcher and share and print. iOS: `DocumentPreviewView`. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DocumentPreviewScreen(model: DocumentPreviewViewModel, onDone: () -> Unit) {
    val context = LocalContext.current
    // The chooser returns when the user comes back, whatever they did (Android does not report a completed share).
    val shareLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { model.didShare() }
    // "Save PDF": the system file picker (≈ the iOS export picker); a chosen place gets a copy of the file.
    val saveLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")) { uri ->
        val file = model.file
        if (uri != null && file != null) {
            runCatching { context.contentResolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } } }
                .onSuccess { model.didShare() }
        }
    }
    LaunchedEffect(model) {
        if (model.file == null) model.render()
        val file = model.file
        val channel = model.takePendingChannel()
        if (channel != null && file != null) {
            delay(300) // let the preview appear first
            when (channel) {
                SendChannel.whatsApp -> {
                    val send = SystemSheets.pdfIntent(context, file, model.title, null)
                    val direct = listOf("com.whatsapp", "com.whatsapp.w4b").firstNotNullOfOrNull { pkg ->
                        android.content.Intent(send).setPackage(pkg).takeIf { it.resolveActivity(context.packageManager) != null }
                    }
                    shareLauncher.launch(direct ?: android.content.Intent.createChooser(send, null))
                }
                SendChannel.email -> {
                    val send = SystemSheets.pdfIntent(context, file, model.emailSubject, null).apply {
                        model.recipient?.let { putExtra(android.content.Intent.EXTRA_EMAIL, arrayOf(it)) }
                        selector = android.content.Intent(android.content.Intent.ACTION_SENDTO, android.net.Uri.parse("mailto:"))
                    }
                    runCatching { shareLauncher.launch(android.content.Intent.createChooser(send, null)) }
                        .onFailure { shareLauncher.launch(android.content.Intent.createChooser(SystemSheets.pdfIntent(context, file, model.emailSubject, null), null)) }
                }
                SendChannel.print -> { SystemSheets.print(context, file, model.title, model.paperSize); model.didShare() }
                SendChannel.savePDF -> saveLauncher.launch(file.name)
            }
        }
    }
    Dialog(onDone, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Surface(Modifier.fillMaxSize(), color = Theme.colors.background) {
            Scaffold(
                containerColor = Theme.colors.surfaceMuted,
                topBar = {
                    TopAppBar(
                        title = { Text(model.title) },
                        navigationIcon = { IconButton(onDone, Modifier.testTag("previewDone")) { Icon(Icons.Filled.Close, "Done") } },
                        actions = {
                            val file = model.file
                            if (file != null) {
                                IconButton({ SystemSheets.print(context, file, model.title, model.paperSize); model.didShare() }) {
                                    Icon(Icons.Filled.Print, "Print")
                                }
                                IconButton({
                                    val uri = SystemSheets.uri(context, file)
                                    val send = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                                        type = "application/pdf"
                                        putExtra(android.content.Intent.EXTRA_STREAM, uri)
                                        putExtra(android.content.Intent.EXTRA_SUBJECT, model.title)
                                        model.reminderMessage?.let { putExtra(android.content.Intent.EXTRA_TEXT, it) }
                                        clipData = android.content.ClipData.newRawUri(file.name, uri)
                                        addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    }
                                    shareLauncher.launch(android.content.Intent.createChooser(send, null))
                                }, Modifier.testTag("sharePDF")) { Icon(Icons.Filled.Share, "Share") }
                            }
                        },
                    )
                },
                bottomBar = { TemplateSwitcher(model.templates, model.template, model::setTemplate) },
            ) { padding ->
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    val file = model.file
                    when {
                        file != null -> PdfPages(file)
                        model.isRendering -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator(); Text("Preparing the PDF…")
                        }
                        else -> Text("The PDF couldn't be created.", color = Theme.colors.textSecondary)
                    }
                }
            }
        }
    }
    if (model.askToMarkSent) {
        AlertDialog({ model.askToMarkSent = false }, title = { Text("Mark as sent?") },
            text = { Text("The status changes to Sent. You can still share it again.") },
            confirmButton = { TextButton({ model.askToMarkSent = false; model.markSent() }, Modifier.testTag("markSent")) { Text("Mark as sent") } },
            dismissButton = { TextButton({ model.askToMarkSent = false }) { Text("Not yet") } })
    }
    ErrorAlert(model.errorMessage, { model.errorMessage = null })
}

@Composable
private fun TemplateSwitcher(templates: List<PDFTemplate>, selected: TemplateID, onSelect: (TemplateID) -> Unit) {
    Surface(color = Theme.colors.surface) {
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = Theme.Space.l, vertical = Theme.Space.s),
            horizontalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
            for (template in templates) {
                FilterChip(template.id == selected, { onSelect(template.id) }, { Text(template.label) },
                    modifier = Modifier.testTag("template-${template.id.rawValue}"))
            }
        }
    }
}

/** The pages of a PDF file, drawn with the platform `PdfRenderer` (≈ PDFKit's `PDFView`). */
@Composable
fun PdfPages(file: File, modifier: Modifier = Modifier) {
    val pages by produceState<List<Bitmap>?>(null, file, file.lastModified()) {
        value = withContext(Dispatchers.IO) { runCatching { renderPages(file) }.getOrNull() }
    }
    val shown = pages
    if (shown == null) {
        CircularProgressIndicator()
        return
    }
    LazyColumn(modifier.fillMaxSize().semantics { contentDescription = "Document preview, ${shown.size} page${if (shown.size == 1) "" else "s"}" },
        contentPadding = androidx.compose.foundation.layout.PaddingValues(Theme.Space.l), verticalArrangement = Arrangement.spacedBy(Theme.Space.l)) {
        items(shown) { page ->
            Image(page.asImageBitmap(), null, Modifier.fillMaxWidth().background(androidx.compose.ui.graphics.Color.White, RoundedCornerShape(2.dp)),
                contentScale = ContentScale.FillWidth)
        }
    }
}

/** Pages at 2× (144 dpi), enough to read on a tablet without holding huge bitmaps. */
private fun renderPages(file: File, scale: Float = 2f): List<Bitmap> =
    ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
        PdfRenderer(descriptor).use { renderer ->
            (0 until renderer.pageCount).map { index ->
                renderer.openPage(index).use { page ->
                    val bitmap = createBitmap((page.width * scale).toInt(), (page.height * scale).toInt())
                    bitmap.eraseColor(Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    bitmap
                }
            }
        }
    }

/** The live preview beside the builder on wide windows, re-rendered (after a 400 ms pause) as the draft changes. */
@Composable
fun DocumentPreviewPane(session: Session, document: Document, computed: ComputedDocument?, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val key = "${document.updatedAt}-${document.lines}-${computed?.totals?.total}-${document.templateId.rawValue}-${document.currency.rawValue}-${document.buyerSnapshot?.name}-${document.issueDate}"
    var file by androidx.compose.runtime.remember { mutableStateOf<File?>(null) }
    LaunchedEffect(key) {
        if (computed == null) return@LaunchedEffect
        delay(400)
        val bytes = runCatching { session.pdfLibrary.data(document, session.business, computed) }.getOrNull() ?: return@LaunchedEffect
        // A new name per render: the page list re-renders when the file changes, and File equality is by path.
        val previous = file
        file = withContext(Dispatchers.IO) {
            File(context.cacheDir, "live-preview-${document.id}-${System.nanoTime()}.pdf").also { it.writeBytes(bytes) }
        }
        previous?.delete()
    }
    Box(modifier.fillMaxSize().background(Theme.colors.surfaceMuted), contentAlignment = Alignment.Center) {
        val current = file
        when {
            computed == null -> Text("Fix the highlighted problems to see the document.", color = Theme.colors.textSecondary, modifier = Modifier.padding(Theme.Space.xl))
            current != null -> PdfPages(current)
            else -> CircularProgressIndicator()
        }
    }
}
