package app.invoicebuilder.core.pdf

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import app.invoicebuilder.core.domain.pdf.PDFDocumentModel
import app.invoicebuilder.core.domain.pdf.PDFLabels
import app.invoicebuilder.core.domain.pdf.PDFTemplate
import app.invoicebuilder.core.domain.support.SpecResources
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** What a render needs: the strings, the template, the page size and the images. iOS: `PDFRenderRequest`. */
data class PDFRenderRequest(
    val model: PDFDocumentModel,
    val template: PDFTemplate,
    /** `A4` or `Letter`, from the tax config. */
    val paperSize: String = "A4",
    /** The business accent colour (`#RRGGBB`); the template decides where it is used. */
    val accentHex: String? = null,
    val logo: ByteArray? = null,
    val signature: ByteArray? = null,
)

/**
 * Draws a document natively (ADR-0006): `StaticLayout` text on a `PdfDocument` canvas, laid out twice so every page
 * can say "Page x of y" (`spec/pdf/RENDERING.md` §3). A port of InvoicePDF's `PDFRenderer` — same blocks, same
 * geometry, same templates — so a document reads the same on both platforms.
 */
object PDFRenderer {
    /** [fontDirectory]: where the bundled Noto fonts are unpacked once (the app's cache directory). */
    fun render(request: PDFRenderRequest, fontDirectory: File): ByteArray {
        val fonts = PDFFonts.get(fontDirectory)
        val pages = PDFComposer(request, fonts).run(null, null)
        val document = PdfDocument()
        PDFComposer(request, fonts).run(pages, document)
        val output = ByteArrayOutputStream()
        document.writeTo(output)
        document.close()
        return output.toByteArray()
    }

    /** The number of pages the document needs, without drawing it. */
    fun pageCount(request: PDFRenderRequest, fontDirectory: File): Int = PDFComposer(request, PDFFonts.get(fontDirectory)).run(null, null)
}

/** The bundled static Noto fonts (`spec/pdf/fonts`), with Noto Sans Devanagari as the fallback for Hindi text. */
class PDFFonts private constructor(directory: File) {
    private val faces = mutableMapOf<PDFTemplate.Weight, Typeface>()

    init {
        directory.mkdirs()
        fun file(name: String): File = File(directory, "$name.ttf").also { target ->
            if (!target.exists()) target.writeBytes(SpecResources.bytes("pdf/fonts/$name.ttf"))
        }
        val files = mapOf(
            PDFTemplate.Weight.regular to ("NotoSans-Regular" to "NotoSansDevanagari-Regular"),
            PDFTemplate.Weight.semibold to ("NotoSans-SemiBold" to "NotoSansDevanagari-SemiBold"),
            PDFTemplate.Weight.bold to ("NotoSans-Bold" to "NotoSansDevanagari-Bold"),
        )
        for ((weight, names) in files) {
            faces[weight] = runCatching {
                val latin = file(names.first)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val family = android.graphics.fonts.FontFamily.Builder(android.graphics.fonts.Font.Builder(latin).build()).build()
                    val devanagari = android.graphics.fonts.FontFamily.Builder(android.graphics.fonts.Font.Builder(file(names.second)).build()).build()
                    Typeface.CustomFallbackBuilder(family).addCustomFallback(devanagari).build()
                } else {
                    Typeface.createFromFile(latin) // older systems fall back to their own Devanagari font
                }
            }.getOrElse { if (weight == PDFTemplate.Weight.regular) Typeface.DEFAULT else Typeface.DEFAULT_BOLD }
        }
    }

    fun typeface(weight: PDFTemplate.Weight): Typeface = faces[weight] ?: faces[PDFTemplate.Weight.regular] ?: Typeface.DEFAULT

    companion object {
        @Volatile private var shared: PDFFonts? = null
        fun get(directory: File): PDFFonts = shared ?: synchronized(this) { shared ?: PDFFonts(File(directory, "pdf-fonts")).also { shared = it } }
    }
}

/** How a run of text is drawn. iOS: `PDFTextStyle`. */
data class PDFTextStyle(
    val typeface: Typeface,
    val size: Float,
    val color: Int,
    val alignment: Layout.Alignment = Layout.Alignment.ALIGN_NORMAL,
    val lineHeightMultiple: Float = 1.2f,
    val uppercase: Boolean = false,
) {
    val paint: TextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = this@PDFTextStyle.typeface
        textSize = size
        color = this@PDFTextStyle.color
    }

    fun text(value: String): String = if (uppercase) value.uppercase() else value
}

/** Measuring and drawing text with `StaticLayout` (top-left origin, like the rest of the renderer). iOS: `PDFText`. */
object PDFText {
    fun layout(text: String, style: PDFTextStyle, width: Float): StaticLayout =
        StaticLayout.Builder.obtain(style.text(text), 0, style.text(text).length, style.paint, max(1, width.toInt()))
            .setAlignment(style.alignment)
            .setLineSpacing(0f, style.lineHeightMultiple)
            .setIncludePad(false)
            .build()

    /** The height [text] needs at [width], rounded up. */
    fun height(text: String, style: PDFTextStyle, width: Float): Float =
        if (text.isEmpty()) 0f else ceil(layout(text, style, width).height.toFloat())

    /** The width [text] needs on one line, rounded up. */
    fun width(text: String, style: PDFTextStyle): Float =
        if (text.isEmpty()) 0f else ceil(Layout.getDesiredWidth(style.text(text), style.paint))

    fun draw(text: String, style: PDFTextStyle, x: Float, y: Float, width: Float, canvas: Canvas): Float {
        if (text.isEmpty()) return 0f
        val layout = layout(text, style, width)
        canvas.save()
        canvas.translate(x, y)
        layout.draw(canvas)
        canvas.restore()
        return ceil(layout.height.toFloat())
    }
}

/** `#RRGGBB` from a template or a business accent colour; mid grey for anything else. */
fun pdfColor(hex: String, alpha: Float = 1f): Int {
    val digits = hex.removePrefix("#")
    val value = if (digits.length == 6) digits.toIntOrNull(16) else null
    val rgb = value ?: 0x808080
    return Color.argb((alpha * 255).toInt(), (rgb shr 16) and 0xFF, (rgb shr 8) and 0xFF, rgb and 0xFF)
}

/**
 * Lays the blocks out top to bottom, breaking pages as `RENDERING.md` §3 requires. The same code runs twice: once
 * to count pages (no document, nothing is drawn), once to draw them. iOS: `PDFComposer`.
 */
class PDFComposer(val request: PDFRenderRequest, private val fonts: PDFFonts) {
    val model get() = request.model
    val template get() = request.template
    val style get() = template.style
    val pageWidth: Float = if (request.paperSize.equals("Letter", ignoreCase = true)) 612f else 595f
    val pageHeight: Float = if (request.paperSize.equals("Letter", ignoreCase = true)) 792f else 842f

    private var document: PdfDocument? = null
    private var page: PdfDocument.Page? = null
    private var totalPages: Int? = null
    private var pageIndex = 0
    var y = 0f
    var tableContinues = false
    var closingNotesTop: Float? = null
    var closingRightBottom = 0f
    var closingRowTop: Float? = null
    var closingSignatureX: Float? = null

    val canvas: Canvas? get() = page?.canvas

    companion object {
        /** How small the payment QR may get to keep a document on one page (`RENDERING.md` §3.4). */
        const val MINIMUM_QR_SIZE = 56f
        val sharedLabels: PDFLabels? by lazy { runCatching { PDFLabels.bundled() }.getOrNull() }
    }

    val margins get() = template.page.margins
    val left get() = margins.left.toFloat()
    val contentWidth get() = pageWidth - margins.left.toFloat() - margins.right.toFloat()
    val contentBottom get() = pageHeight - margins.bottom.toFloat() - template.page.footerHeight.toFloat()

    val accent get() = pdfColor(request.accentHex ?: "#1F6FEB")
    fun accent(alpha: Float) = pdfColor(request.accentHex ?: "#1F6FEB", alpha)
    val textColor get() = pdfColor(style.colors.text)
    val mutedColor get() = pdfColor(style.colors.muted)
    val ruleColor get() = if (template.uses("rules")) accent(0.5f) else pdfColor(style.colors.rule)

    fun textStyle(
        size: Double, weight: PDFTemplate.Weight = PDFTemplate.Weight.regular, color: Int? = null,
        align: Layout.Alignment = Layout.Alignment.ALIGN_NORMAL, uppercase: Boolean = false,
    ) = PDFTextStyle(fonts.typeface(weight), size.toFloat(), color ?: textColor, align, style.lineHeight.toFloat(), uppercase)

    /** Lays the document out and returns the number of pages. */
    fun run(totalPages: Int?, document: PdfDocument?): Int {
        this.document = document
        this.totalPages = totalPages
        pageIndex = 0
        beginPage()
        for (block in template.blocks) {
            when (block.id) {
                "header" -> drawHeader(block.variant)
                "parties" -> { drawParties(block.variant); drawNotes(model.topNotes) }
                "items" -> drawItems(block.variant)
                "totals" -> drawTotals()
                "payment" -> drawPayment(block.variant)
                "notes" -> drawNotes(model.bottomNotes, closing = true)
                "signature" -> drawSignature(block.variant)
                else -> {} // a block a newer spec adds: skip it rather than fail
            }
        }
        endPage()
        return pageIndex + 1
    }

    private fun beginPage() {
        document?.let { page = it.startPage(PdfDocument.PageInfo.Builder(pageWidth.toInt(), pageHeight.toInt(), pageIndex + 1).create()) }
        y = margins.top.toFloat()
        closingRightBottom = 0f
        closingNotesTop = null
        closingRowTop = null
        closingSignatureX = null
        val canvas = canvas
        if (canvas != null && model.isDraft) model.draftLabel?.let { drawWatermark(it, canvas) }
        if (pageIndex > 0) drawContinuationHeader()
    }

    private fun endPage() {
        val canvas = canvas
        if (canvas != null) {
            val number = pageIndex + 1
            val text = model.footer.pageLabel.replace("{page}", number.toString()).replace("{pages}", (totalPages ?: number).toString())
            val top = pageHeight - margins.bottom.toFloat() - template.page.footerHeight.toFloat()
            PDFText.draw(text, textStyle(style.fontSizes.small, color = mutedColor, align = Layout.Alignment.ALIGN_CENTER), left, top, contentWidth, canvas)
            if (tableContinues) {
                PDFText.draw(model.footer.continued, textStyle(style.fontSizes.small, color = mutedColor, align = Layout.Alignment.ALIGN_OPPOSITE),
                    left, top - style.fontSizes.small.toFloat() * 1.6f, contentWidth, canvas)
            }
        }
        page?.let { document?.finishPage(it) }
        page = null
    }

    fun newPage() {
        endPage()
        pageIndex++
        beginPage()
    }

    /** Starts a new page when [height] would not fit under the current cursor. */
    fun need(height: Float) {
        if (y + height > contentBottom) newPage()
    }

    private fun drawContinuationHeader() {
        val line = listOfNotNull(model.title, model.number).joinToString(" · ")
        canvas?.let { PDFText.draw(line, textStyle(style.fontSizes.heading, PDFTemplate.Weight.semibold, mutedColor), left, y, contentWidth, it) }
        y += style.fontSizes.heading.toFloat() * 1.6f + style.blockSpacing.toFloat() / 2
    }

    private fun drawWatermark(text: String, canvas: Canvas) {
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = fonts.typeface(PDFTemplate.Weight.bold)
            textSize = 96f
            color = Color.argb((0.55f * 255).toInt(), 217, 217, 217)
            textAlign = Paint.Align.CENTER
        }
        canvas.save()
        canvas.translate(pageWidth / 2, pageHeight / 2)
        canvas.rotate(-30f)
        canvas.drawText(text, 0f, 0f, paint)
        canvas.restore()
    }

    // Primitives

    fun text(string: String, style: PDFTextStyle, x: Float, width: Float, top: Float? = null): Float {
        val height = PDFText.height(string, style, width)
        canvas?.let { PDFText.draw(string, style, x, top ?: y, width, it) }
        return height
    }

    fun rule(top: Float, x: Float? = null, width: Float? = null, color: Int? = null) {
        val canvas = canvas ?: return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color ?: ruleColor
            strokeWidth = this@PDFComposer.style.rule.width.toFloat()
            this.style = Paint.Style.STROKE
        }
        val start = x ?: left
        canvas.drawLine(start, top, start + (width ?: contentWidth), top, paint)
    }

    fun fill(rect: RectF, color: Int) {
        canvas?.drawRect(rect, Paint().apply { this.color = color; this.style = Paint.Style.FILL })
    }

    fun image(data: ByteArray?): Bitmap? = data?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }

    /** Draws [image] inside [box], keeping its aspect ratio and pinning it to the top (and to the right when asked). */
    fun draw(image: Bitmap, box: RectF, alignRight: Boolean, interpolate: Boolean = true) {
        val canvas = canvas ?: return
        if (image.width <= 0 || image.height <= 0) return
        val scale = min(min(box.width() / image.width, box.height() / image.height), 1f)
        val width = image.width * scale
        val height = image.height * scale
        val x = if (alignRight) box.right - width else box.left
        canvas.drawBitmap(image, null, RectF(x, box.top, x + width, box.top + height), Paint().apply { isFilterBitmap = interpolate })
    }

    /** The UPI payment link as a QR code (`ENGINE.md` §9), error correction M. Skipped in the layout pass. */
    fun qrImage(payload: String): Bitmap? {
        if (canvas == null) return null
        val matrix = QRCodeWriter().encode(payload, BarcodeFormat.QR_CODE, 0, 0, mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 0))
        val scale = 8
        val bitmap = Bitmap.createBitmap(matrix.width * scale, matrix.height * scale, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.WHITE)
        val paint = Paint().apply { color = Color.BLACK }
        val c = Canvas(bitmap)
        for (row in 0 until matrix.height) for (column in 0 until matrix.width) {
            if (matrix[column, row]) c.drawRect((column * scale).toFloat(), (row * scale).toFloat(), ((column + 1) * scale).toFloat(), ((row + 1) * scale).toFloat(), paint)
        }
        return bitmap
    }

    fun labelText(key: String): String = sharedLabels?.text(key) ?: key
}
