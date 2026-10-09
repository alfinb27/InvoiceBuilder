package app.invoicebuilder.core.pdf

import android.graphics.Bitmap
import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.invoicebuilder.core.domain.models.TemplateID
import app.invoicebuilder.core.domain.pdf.PDFDocumentModel
import app.invoicebuilder.core.domain.pdf.PDFDocumentModel.Align
import app.invoicebuilder.core.domain.pdf.PDFDocumentModel.Column
import app.invoicebuilder.core.domain.pdf.PDFDocumentModel.Field
import app.invoicebuilder.core.domain.pdf.PDFTemplateStore
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * The drawing, on a real Android graphics stack (iOS: `RenderTests.swift`, the same cases). The strings themselves
 * are proven by the `pdf` fixtures in `:core:domain`; these tests are about pagination, fonts, images and size.
 */
@RunWith(AndroidJUnit4::class)
class RenderTests {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val fonts: File get() = context.cacheDir
    private val templates = PDFTemplateStore.bundled()

    @Before fun setUp() = PDFBoxResourceLoader.init(context)

    private fun invoice(lines: Int = 2, isDraft: Boolean = false, description: String = "Website development", withUPI: Boolean = true): PDFDocumentModel {
        val columns = listOf(
            Column("index", "#", Align.leading), Column("description", "Description", Align.leading),
            Column("productCode", "HSN/SAC", Align.leading), Column("quantity", "Qty", Align.trailing),
            Column("unitPrice", "Rate", Align.trailing), Column("taxable", "Taxable value", Align.trailing),
            Column("tax:CGST", "CGST 9%", Align.trailing), Column("tax:SGST", "SGST 9%", Align.trailing),
            Column("amount", "Amount", Align.trailing),
        )
        val rows = (1..maxOf(lines, 1)).map { listOf("$it", "$description $it", "998314", "2", "₹5,000.00", "₹10,000.00", "₹900.00", "₹900.00", "₹11,800.00") }
        return PDFDocumentModel(
            title = "Tax Invoice", isDraft = isDraft, draftLabel = if (isDraft) "DRAFT" else null,
            number = if (isDraft) null else "INV/26-27/0042", numberLabel = "Invoice no.",
            meta = listOf(Field("Date", "19 Sep 2026"), Field("Due date", "4 Oct 2026"), Field("Place of supply", "Karnataka")),
            seller = PDFDocumentModel.Party("From", "Bharat Web Studio", listOf("Bharat Web Studio LLP", "12 MG Road", "Bengaluru 560001", "Karnataka"),
                listOf(Field("GSTIN", "29AAGCB7383J1Z4"))),
            buyer = PDFDocumentModel.Party("Bill to", "Rao Traders", listOf("5 Residency Road", "Bengaluru 560025"), listOf(Field("GSTIN", "29AABCR1234C1ZU"))),
            columns = columns, rows = rows,
            totals = listOf(
                PDFDocumentModel.TotalRow("Subtotal", "₹10,000.00"), PDFDocumentModel.TotalRow("Taxable value", "₹10,000.00"),
                PDFDocumentModel.TotalRow("CGST 9%", "₹900.00"), PDFDocumentModel.TotalRow("SGST 9%", "₹900.00"),
                PDFDocumentModel.TotalRow("Total", "₹11,800.00", PDFDocumentModel.Emphasis.strong),
            ),
            taxSummary = PDFDocumentModel.Table(
                listOf(Column("rate", "GST rate", Align.leading), Column("taxable", "Taxable value", Align.trailing), Column("tax", "GST", Align.trailing)),
                listOf(listOf("CGST 9%", "₹10,000.00", "₹900.00"), listOf("SGST 9%", "₹10,000.00", "₹900.00"), listOf("Total GST", "₹10,000.00", "₹1,800.00")),
            ),
            amountInWords = "Indian Rupees Eleven Thousand Eight Hundred Only",
            notes = listOf(PDFDocumentModel.Note("Notes", "Thank you for your business.", "bottom")),
            payment = PDFDocumentModel.Payment(
                listOf(Field("Account name", "Bharat Web Studio LLP"), Field("IFSC", "EXMP0001234")),
                if (withUPI) PDFDocumentModel.Payment.UPI("bharatweb@examplebank", "Scan to pay with any UPI app",
                    "upi://pay?pa=bharatweb@examplebank&pn=Bharat%20Web%20Studio&am=11800.00&cu=INR") else null,
            ),
            signature = PDFDocumentModel.Signature(forBusiness = "For Bharat Web Studio", authorisedSignatory = "Authorised signatory"),
            footer = PDFDocumentModel.Footer("Page {page} of {pages}", "Continued on next page"),
        )
    }

    private fun request(model: PDFDocumentModel, template: TemplateID = TemplateID.classic, paper: String = "A4", logo: ByteArray? = null, signature: ByteArray? = null) =
        PDFRenderRequest(model, templates.template(template)!!, paper, "#1F6FEB", logo, signature)

    private fun render(request: PDFRenderRequest) = PDFRenderer.render(request, fonts)

    /** The text of every page, as a reader (or a tax office) would extract it. */
    private fun pageTexts(data: ByteArray): List<String> = PDDocument.load(data).use { document ->
        (1..document.numberOfPages).map { page -> PDFTextStripper().apply { startPage = page; endPage = page }.getText(document) }
    }

    private fun png(width: Int, height: Int, color: Int): ByteArray {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply { eraseColor(color) }
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    @Test fun everyTemplateDrawsOnePageWithTheKeyFacts() {
        for (template in TemplateID.known) {
            val pages = pageTexts(render(request(invoice(), template)))
            assertEquals("${template.rawValue}: pages", 1, pages.size)
            for (expected in listOf("Tax Invoice", "INV/26-27/0042", "Rao Traders", "Bharat Web Studio", "29AAGCB7383J1Z4",
                "Website development 1", "₹11,800.00", "Total", "Page 1 of 1", "Indian Rupees Eleven Thousand Eight Hundred Only", "Authorised signatory")) {
                assertTrue("${template.rawValue} is missing \"$expected\"", pages[0].contains(expected))
            }
        }
    }

    @Test fun aLongInvoicePaginatesWithRepeatedHeadersAndPageNumbers() {
        val pages = pageTexts(render(request(invoice(lines = 60))))
        assertTrue("60 lines should not fit on one page", pages.size >= 2)
        val withRows = pages.indices.filter { pages[it].contains("998314") }
        pages.forEachIndexed { index, text ->
            assertTrue("page ${index + 1} number", text.contains("Page ${index + 1} of ${pages.size}"))
            if (index in withRows) assertTrue("page ${index + 1} repeats no table header", text.lowercase().contains("description"))
        }
        for (index in withRows.dropLast(1)) assertTrue("page ${index + 1} is missing the note", pages[index].contains("Continued on next page"))
        val withTotals = pages.indexOfFirst { it.contains("Total") }
        assertTrue(withTotals == withRows.last() || withTotals == withRows.last() + 1)
        assertTrue(pages.last().contains("Authorised signatory"))
        val all = pages.joinToString("")
        for (index in 1..60) assertTrue("line $index", all.contains("Website development $index"))
    }

    @Test fun devanagariIsDrawnWithTheBundledFontAndStaysSelectable() {
        val data = render(request(invoice(description = "वेबसाइट विकास")))
        assertTrue("Hindi text must be embedded and extractable", pageTexts(data).joinToString("").contains("वेबसाइट"))
        assertTrue("the bundled Devanagari font must be embedded", String(data, Charsets.ISO_8859_1).contains("NotoSansDevanagari"))
    }

    /**
     * The watermark is drawn at -30°, which PDFBox's text extraction skips (it reads 0/90/180/270° text only), so
     * this looks at the pixels instead: a draft has watermark-grey pixels across the middle of the page, an issued
     * document has none there.
     */
    @Test fun draftsCarryTheWatermark() {
        fun watermarkPixels(data: ByteArray): Int {
            val file = File(context.cacheDir, "watermark-test.pdf").also { it.writeBytes(data) }
            android.os.ParcelFileDescriptor.open(file, android.os.ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                android.graphics.pdf.PdfRenderer(descriptor).use { renderer ->
                    renderer.openPage(0).use { page ->
                        val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.WHITE) }
                        page.render(bitmap, null, null, android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        // A band through the centre, left of the tables' text columns: count light-grey pixels.
                        var count = 0
                        for (y in page.height * 2 / 5 until page.height * 3 / 5) for (x in page.width / 4 until page.width * 3 / 4) {
                            val pixel = bitmap.getPixel(x, y)
                            val (r, g, b) = Triple(Color.red(pixel), Color.green(pixel), Color.blue(pixel))
                            if (r in 225..245 && kotlin.math.abs(r - g) < 4 && kotlin.math.abs(r - b) < 4) count++
                        }
                        return count
                    }
                }
            }
        }
        val draft = watermarkPixels(render(request(invoice(isDraft = true))))
        val issued = watermarkPixels(render(request(invoice())))
        assertTrue("draft $draft grey pixels against issued $issued", draft > issued + 500)
    }

    /** §3.3: the tax summary sits beside the totals, so an ordinary invoice keeps to one page. */
    @Test fun theTaxSummarySitsBesideTheTotals() {
        val pages = pageTexts(render(request(invoice(lines = 6))))
        assertEquals("six lines with a tax summary must still fit on one page", 1, pages.size)
        for (expected in listOf("GST rate", "Total GST", "Subtotal", "Total", "BANK DETAILS", "Authorised signatory")) {
            assertTrue("missing \"$expected\"", pages[0].contains(expected))
        }
    }

    /** §3.4: payment, notes and signature travel together. */
    @Test fun theClosingBlocksAreNeverStrandedOnAPageOfTheirOwn() {
        for (template in TemplateID.known) for (lines in listOf(1, 3, 5, 7, 9, 12, 14)) {
            val last = pageTexts(render(request(invoice(lines), template))).last()
            assertTrue("${template.rawValue}, $lines lines", last.contains("Authorised signatory"))
            if (!last.contains("Total")) {
                assertTrue("${template.rawValue}, $lines lines: the last page holds only notes and a signature", last.contains("bharatweb@examplebank"))
            }
        }
    }

    @Test fun aLogoAndASignatureAreDrawnWithoutDisturbingTheLayout() {
        val plain = render(request(invoice()))
        val data = render(request(invoice(), logo = png(240, 80, Color.BLUE), signature = png(200, 60, Color.BLACK)))
        val pages = pageTexts(data)
        assertEquals("images must not push the document onto a second page", 1, pages.size)
        assertTrue(pages[0].contains("Authorised signatory") && pages[0].contains("INV/26-27/0042"))
        assertTrue("the images must actually be embedded", data.size > plain.size)
    }

    @Test fun aOnePageInvoiceStaysSmall() {
        val data = render(request(invoice()))
        assertTrue("one page was ${data.size} bytes", data.size < 300_000)
        assertEquals(1, PDFRenderer.pageCount(request(invoice()), fonts))
    }

    @Test fun aLetterPageIsWiderAndShorter() {
        PDDocument.load(render(request(invoice(), paper = "Letter"))).use { document ->
            val box = document.getPage(0).mediaBox
            assertEquals(612, box.width.toInt())
            assertEquals(792, box.height.toInt())
        }
    }

    /** The shape of the cost: 60 lines within a small multiple of one line, and a loose absolute ceiling. */
    @Test fun renderingGrowsWithTheLinesAndNoFaster() {
        render(request(invoice(lines = 1))) // warm the fonts
        fun seconds(lines: Int): Double {
            val start = System.nanoTime()
            render(request(invoice(lines)))
            return (System.nanoTime() - start) / 1e9
        }
        val one = maxOf(seconds(1), 0.001)
        val sixty = seconds(60)
        assertTrue("60 lines took $sixty s against $one s for one line", sixty < one * 12)
        assertTrue("a 60-line invoice took $sixty s", sixty < 3.0)
    }

    /**
     * Review copies (iOS: `SampleDocumentsTests`): every template, one page and a long invoice, written to the app's
     * external files directory. Runs only when asked: `-Pandroid.testInstrumentationRunnerArguments.pdfSamples=1`.
     */
    @Test fun writeSamples() {
        if (InstrumentationRegistry.getArguments().getString("pdfSamples") == null) return
        val directory = File(context.getExternalFilesDir(null), "pdf-samples").also { it.mkdirs() }
        for (template in TemplateID.known) {
            File(directory, "${template.rawValue}.pdf").writeBytes(render(request(invoice(), template)))
            File(directory, "${template.rawValue}-draft-long.pdf").writeBytes(render(request(invoice(lines = 40, isDraft = true), template)))
        }
        File(directory, "hindi.pdf").writeBytes(render(request(invoice(description = "वेबसाइट विकास"))))
    }
}
