package app.invoicebuilder.core.pdf

import android.graphics.RectF
import android.text.Layout
import app.invoicebuilder.core.domain.pdf.PDFDocumentModel
import app.invoicebuilder.core.domain.pdf.PDFTemplate
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// The blocks of `spec/pdf/RENDERING.md` §2, drawn in the order the template lists them (iOS: `PDFBlocks.swift`).

private val Right = Layout.Alignment.ALIGN_OPPOSITE
private val Leading = Layout.Alignment.ALIGN_NORMAL
private fun PDFDocumentModel.Align.layout() = if (this == PDFDocumentModel.Align.trailing) Right else Leading

// Header

fun PDFComposer.drawHeader(variant: String) {
    if (variant == "band") {
        drawHeaderBand()
        return
    }
    val logo = image(request.logo)
    val logoWidth = if (logo == null) 0f else style.logo.maxWidth.toFloat() + style.blockSpacing.toFloat()
    val metaWidth = max(contentWidth * 0.34f, 150f)
    val titleX = if (variant == "logoLeft") left + logoWidth else left
    val titleWidth = contentWidth - metaWidth - logoWidth - style.blockSpacing.toFloat()
    val top = y
    if (logo != null) {
        val x = if (variant == "logoLeft") left else left + contentWidth - style.logo.maxWidth.toFloat()
        draw(logo, RectF(x, top, x + style.logo.maxWidth.toFloat(), top + style.logo.maxHeight.toFloat()), alignRight = variant != "logoLeft")
    }
    var titleBottom = top
    titleBottom += text(model.title, textStyle(style.fontSizes.title, PDFTemplate.Weight.bold, if (template.uses("title")) accent else textColor), titleX, titleWidth, titleBottom)
    model.number?.let { number ->
        titleBottom += 2
        titleBottom += text("${model.numberLabel} $number", textStyle(style.fontSizes.heading, PDFTemplate.Weight.semibold), titleX, titleWidth, titleBottom)
    }
    val metaX = left + contentWidth - metaWidth
    val metaBottom = drawFields(model.meta, metaX, metaWidth, if (variant == "logoRight" && logo != null) top + style.logo.maxHeight.toFloat() + 6 else top)
    y = max(max(titleBottom, metaBottom), if (logo == null) top else top + style.logo.maxHeight.toFloat())
    y += 6
    rule(y)
    y += style.blockSpacing.toFloat() * 0.75f
}

/** An accent band across the top with the title and number reversed out of it. */
private fun PDFComposer.drawHeaderBand() {
    val onAccent = pdfColor(style.colors.onAccent)
    val width = contentWidth * 0.6f
    val titleStyle = textStyle(style.fontSizes.title, PDFTemplate.Weight.bold, onAccent)
    val numberStyle = textStyle(style.fontSizes.heading, PDFTemplate.Weight.semibold, onAccent)
    val numberText = model.number?.let { "${model.numberLabel} $it" }
    val bandHeight = 18 + PDFText.height(model.title, titleStyle, width) + (numberText?.let { PDFText.height(it, numberStyle, width) } ?: 0f) + 16
    fill(RectF(0f, 0f, pageWidth, bandHeight), accent)
    var top = 18f
    top += text(model.title, titleStyle, left, width, top)
    numberText?.let { top += text(it, numberStyle, left, width, top) }
    image(request.logo)?.let { logo ->
        val x = left + contentWidth - style.logo.maxWidth.toFloat()
        draw(logo, RectF(x, 14f, x + style.logo.maxWidth.toFloat(), 14f + min(style.logo.maxHeight.toFloat(), bandHeight - 28)), alignRight = true)
    }
    y = bandHeight + style.blockSpacing.toFloat()
    val metaWidth = max(contentWidth * 0.34f, 150f)
    y = drawFields(model.meta, left + contentWidth - metaWidth, metaWidth, y)
    y += style.blockSpacing.toFloat()
}

/** Label / value pairs, right aligned. Returns the bottom edge. */
fun PDFComposer.drawFields(fields: List<PDFDocumentModel.Field>, x: Float, width: Float, top: Float, labelColor: Int? = null): Float {
    var bottom = top
    val labelWidth = width * 0.5f
    for (field in fields) {
        val labelStyle = textStyle(style.fontSizes.small, color = labelColor ?: mutedColor, align = Right)
        val valueStyle = textStyle(style.fontSizes.body, PDFTemplate.Weight.semibold, align = Right)
        val height = max(PDFText.height(field.label, labelStyle, labelWidth), PDFText.height(field.value, valueStyle, width - labelWidth - 6))
        text(field.label, labelStyle, x, labelWidth, bottom + 1)
        text(field.value, valueStyle, x + labelWidth + 6, width - labelWidth - 6, bottom)
        bottom += height + 2
    }
    return bottom
}

// Parties

fun PDFComposer.drawParties(variant: String) {
    val stacked = variant == "stacked" || model.buyer == null
    val columnWidth = if (stacked) contentWidth else (contentWidth - style.blockSpacing.toFloat()) / 2
    val top = y
    var leftBottom = drawParty(model.seller, left, columnWidth, top)
    var rightBottom = top
    model.buyer?.let { buyer ->
        if (stacked) {
            leftBottom = drawParty(buyer, left, columnWidth, leftBottom + style.blockSpacing.toFloat() / 2)
            model.shipTo?.let { leftBottom = drawParty(it, left, columnWidth, leftBottom + style.blockSpacing.toFloat() / 2) }
        } else {
            val x = left + columnWidth + style.blockSpacing.toFloat()
            rightBottom = drawParty(buyer, x, columnWidth, top)
            model.shipTo?.let { rightBottom = drawParty(it, x, columnWidth, rightBottom + style.blockSpacing.toFloat() / 2) }
        }
    }
    y = max(leftBottom, rightBottom) + style.blockSpacing.toFloat()
}

private fun PDFComposer.drawParty(party: PDFDocumentModel.Party, x: Float, width: Float, top: Float): Float {
    var bottom = top
    party.heading?.let {
        bottom += text(it, textStyle(style.fontSizes.small, PDFTemplate.Weight.semibold, mutedColor, uppercase = true), x, width, bottom)
        bottom += 2
    }
    if (party.name.isNotEmpty()) bottom += text(party.name, textStyle(style.fontSizes.body + 1, PDFTemplate.Weight.semibold), x, width, bottom)
    for (line in party.lines) bottom += text(line, textStyle(style.fontSizes.body, color = mutedColor), x, width, bottom)
    for (field in party.fields) bottom += text("${field.label} ${field.value}", textStyle(style.fontSizes.body), x, width, bottom)
    return bottom
}

// Items table

fun PDFComposer.drawItems(variant: String) {
    val table = TableLayout(this, model.columns, model.rows, contentWidth, variant == "compact")
    drawTableHeader(table)
    for ((index, row) in model.rows.withIndex()) {
        val height = table.rowHeights[index]
        if (y + height > contentBottom) {
            tableContinues = true // this page ends mid-table, so its footer says "continued"
            newPage()
            tableContinues = false
            drawTableHeader(table)
        }
        val fill = if (variant == "zebra" && index % 2 == 0) style.colors.zebraFill?.let(::pdfColor) else null
        drawTableRow(row, table, height, fill, style.table.rowRule == PDFTemplate.RowRule.below || variant == "ruled")
    }
    y += style.blockSpacing.toFloat() / 2
}

private fun PDFComposer.drawTableHeader(table: TableLayout) {
    val height = table.headerHeight
    if (y + height > contentBottom) newPage()
    val headerFill = if (template.uses("tableHeaderFill")) accent(0.12f) else style.colors.tableHeaderFill?.let(::pdfColor)
    headerFill?.let { fill(RectF(left, y, left + contentWidth, y + height), it) }
    val color = if (template.uses("tableHeaderText")) accent else textColor
    var x = left
    for ((index, column) in model.columns.withIndex()) {
        val width = table.widths[index]
        val headerStyle = textStyle(style.fontSizes.small, style.table.headerWeight, color, column.align.layout(), style.table.headerUppercase)
        text(column.label, headerStyle, x + table.padding.horizontal.toFloat(), width - table.padding.horizontal.toFloat() * 2, y + table.padding.vertical.toFloat())
        x += width
    }
    y += height
    rule(y)
}

private fun PDFComposer.drawTableRow(row: List<String>, table: TableLayout, height: Float, background: Int?, drawRule: Boolean) {
    background?.let { fill(RectF(left, y, left + contentWidth, y + height), it) }
    var x = left
    for ((index, column) in model.columns.withIndex()) {
        val width = table.widths[index]
        text(row[index], textStyle(style.fontSizes.body, align = column.align.layout()), x + table.padding.horizontal.toFloat(),
            width - table.padding.horizontal.toFloat() * 2, y + table.padding.vertical.toFloat())
        x += width
    }
    y += height
    if (drawRule) rule(y)
}

// Totals

fun PDFComposer.drawTotals() {
    val width = max(contentWidth * 0.42f, 190f)
    val summaryWidth = min(contentWidth * 0.55f, contentWidth - width - style.blockSpacing.toFloat())
    // The tax summary sits beside the totals whenever it still gets a readable width (`RENDERING.md` §1.2).
    val sideBySide = model.taxSummary != null && summaryWidth >= 170
    val summaryHeight = taxSummaryHeight(if (sideBySide) summaryWidth else null)
    val totalsHeight = totalsBlockHeight()
    need(if (sideBySide) max(summaryHeight, totalsHeight) else summaryHeight + totalsHeight + style.blockSpacing.toFloat())
    val top = y
    var summaryBottom = y
    model.taxSummary?.let { summary ->
        drawSummary(summary, if (sideBySide) summaryWidth else null)
        summaryBottom = y
        if (sideBySide) y = top else y += style.blockSpacing.toFloat() / 2
    }
    val x = left + contentWidth - width
    for (row in model.totals) {
        val strong = row.emphasis == PDFDocumentModel.Emphasis.strong
        if (strong) {
            rule(y, x, width)
            y += 4
        }
        val labelStyle = textStyle(style.fontSizes.body, if (strong) PDFTemplate.Weight.bold else PDFTemplate.Weight.regular, if (strong) textColor else mutedColor)
        val valueStyle = textStyle(if (strong) style.fontSizes.heading + 1 else style.fontSizes.body,
            if (strong) PDFTemplate.Weight.bold else PDFTemplate.Weight.regular, if (strong && template.uses("totalRow")) accent else textColor, Right)
        val height = max(PDFText.height(row.label, labelStyle, width * 0.55f), PDFText.height(row.value, valueStyle, width * 0.45f))
        text(row.label, labelStyle, x, width * 0.55f, y)
        text(row.value, valueStyle, x + width * 0.55f, width * 0.45f, y)
        y += height + 3
    }
    y = max(y + 4, summaryBottom)
    for (line in listOfNotNull(model.reverseChargeNote, model.homeTotals, model.amountInWords)) {
        y += text(line, textStyle(style.fontSizes.small, color = mutedColor), left, contentWidth, y) + 2
    }
    y += style.blockSpacing.toFloat() / 2
}

private fun PDFComposer.drawSummary(summary: PDFDocumentModel.Table, width: Float? = null) {
    val tableWidth = width ?: min(contentWidth * 0.62f, contentWidth)
    val table = TableLayout(this, summary.columns, summary.rows, tableWidth, true)
    var x = left
    for ((index, column) in summary.columns.withIndex()) {
        text(column.label, textStyle(style.fontSizes.small, PDFTemplate.Weight.semibold, mutedColor, column.align.layout()),
            x + table.padding.horizontal.toFloat(), table.widths[index] - table.padding.horizontal.toFloat() * 2, y)
        x += table.widths[index]
    }
    y += table.headerHeight - table.padding.vertical.toFloat()
    rule(y, left, tableWidth)
    y += 2
    for ((rowIndex, row) in summary.rows.withIndex()) {
        val last = rowIndex == summary.rows.size - 1
        x = left
        var height = 0f
        for ((index, column) in summary.columns.withIndex()) {
            val cellStyle = textStyle(style.fontSizes.small, if (last) PDFTemplate.Weight.semibold else PDFTemplate.Weight.regular, align = column.align.layout())
            val cellWidth = table.widths[index] - table.padding.horizontal.toFloat() * 2
            height = max(height, PDFText.height(row[index], cellStyle, cellWidth))
            text(row[index], cellStyle, x + table.padding.horizontal.toFloat(), cellWidth, y)
            x += table.widths[index]
        }
        y += height + 3
        if (last) rule(y - 1, left, tableWidth)
    }
}

private fun PDFComposer.totalsBlockHeight(): Float {
    val width = max(contentWidth * 0.42f, 190f)
    var height = 0f
    for (row in model.totals) {
        val strong = row.emphasis == PDFDocumentModel.Emphasis.strong
        val labelStyle = textStyle(style.fontSizes.body, if (strong) PDFTemplate.Weight.bold else PDFTemplate.Weight.regular)
        val valueStyle = textStyle(if (strong) style.fontSizes.heading + 1 else style.fontSizes.body, align = Right)
        height += max(PDFText.height(row.label, labelStyle, width * 0.55f), PDFText.height(row.value, valueStyle, width * 0.45f)) + 3
        if (strong) height += 4
    }
    for (line in listOfNotNull(model.reverseChargeNote, model.homeTotals, model.amountInWords)) {
        height += PDFText.height(line, textStyle(style.fontSizes.small), contentWidth) + 2
    }
    return height + style.blockSpacing.toFloat()
}

private fun PDFComposer.taxSummaryHeight(width: Float? = null): Float {
    val summary = model.taxSummary ?: return 0f
    val table = TableLayout(this, summary.columns, summary.rows, width ?: min(contentWidth * 0.62f, contentWidth), true)
    return table.headerHeight + table.rowHeights.sum() + style.blockSpacing.toFloat() / 2
}

// Payment, notes, signature

fun PDFComposer.drawPayment(variant: String) {
    val payment = model.payment
    if (payment.bank.isEmpty() && payment.upi == null) return
    var qrSize = (style.qrSize ?: 80.0).toFloat()
    val qrColumn = max(qrSize, 150f)
    // Reserve a signature column beside the QR only when the bank details still get a usable width.
    val signatureColumn = run {
        if (template.block("signature")?.variant != "right" || payment.upi == null) return@run 0f
        val candidate = signatureWidth + style.blockSpacing.toFloat()
        if (contentWidth - qrColumn - candidate - style.blockSpacing.toFloat() >= 180) candidate else 0f
    }
    val sideBySide = variant != "stacked" && payment.upi != null
    val bankWidth = if (sideBySide) contentWidth - qrColumn - signatureColumn - style.blockSpacing.toFloat() else contentWidth
    var bankHeight = 0f
    if (payment.bank.isNotEmpty()) {
        bankHeight = PDFText.height(payment.bank.joinToString("\n") { "${it.label} ${it.value}" }, textStyle(style.fontSizes.body), bankWidth) +
            style.fontSizes.small.toFloat() * 2
    }
    val captions = style.fontSizes.small.toFloat() * 3
    fun blockHeight(qr: Float): Float = when {
        payment.upi == null -> bankHeight
        sideBySide -> max(bankHeight, qr + captions)
        else -> bankHeight + qr + captions + style.blockSpacing.toFloat() / 2
    }
    var height = blockHeight(qrSize)
    // A page that would hold nothing but the closing blocks is worse than a slightly smaller QR (§3.4).
    val reserve = closingReserve(sideBySide && signatureColumn > 0)
    val available = contentBottom - y - reserve
    if (payment.upi != null && height > available) {
        val room = floor(if (sideBySide) available - captions else available - bankHeight - captions - style.blockSpacing.toFloat() / 2)
        if (room >= PDFComposer.MINIMUM_QR_SIZE) {
            qrSize = min(qrSize, room)
            height = blockHeight(qrSize)
        }
    }
    need(height + reserve)

    val top = y
    var bottom = top
    if (payment.bank.isNotEmpty()) {
        bottom += text(labelText("bankDetails"), textStyle(style.fontSizes.small, PDFTemplate.Weight.semibold, mutedColor, uppercase = true), left, bankWidth, bottom)
        bottom += 2
        val labelWidth = min(bankWidth * 0.42f, 110f)
        for (field in payment.bank) {
            val labelStyle = textStyle(style.fontSizes.body, color = mutedColor)
            val valueStyle = textStyle(style.fontSizes.body)
            val rowHeight = max(PDFText.height(field.label, labelStyle, labelWidth), PDFText.height(field.value, valueStyle, bankWidth - labelWidth - 6))
            text(field.label, labelStyle, left, labelWidth, bottom)
            text(field.value, valueStyle, left + labelWidth + 6, bankWidth - labelWidth - 6, bottom)
            bottom += rowHeight
        }
    }
    payment.upi?.let { upi ->
        val stackedQR = !sideBySide
        val columnX = if (stackedQR) left else left + contentWidth - signatureColumn - qrColumn
        val columnWidth = if (stackedQR) contentWidth else qrColumn
        val qrTop = if (stackedQR) bottom + style.blockSpacing.toFloat() / 2 else top
        qrImage(upi.payload)?.let { qr ->
            val x = if (stackedQR) columnX else columnX + columnWidth - qrSize
            draw(qr, RectF(x, qrTop, x + qrSize, qrTop + qrSize), alignRight = false, interpolate = false)
        }
        var captionTop = qrTop + qrSize + 2
        val align = if (stackedQR) Leading else Right
        captionTop += text(upi.id, textStyle(style.fontSizes.small, PDFTemplate.Weight.semibold, align = align), columnX, columnWidth, captionTop)
        captionTop += text(upi.caption, textStyle(style.fontSizes.small, color = mutedColor, align = align), columnX, columnWidth, captionTop)
        if (stackedQR) {
            bottom = max(bottom, captionTop)
        } else {
            closingRightBottom = captionTop
            closingRowTop = top
            closingSignatureX = left + contentWidth - signatureWidth
        }
    }
    y = bottom + style.blockSpacing.toFloat() / 2
}

/** What still has to fit under the payment block: the closing notes, and the signature unless it sits in the row. */
private fun PDFComposer.closingReserve(signatureInRow: Boolean): Float {
    var reserve = 0f
    if (template.block("notes") != null && model.bottomNotes.isNotEmpty()) {
        val width = if (template.block("signature") != null) contentWidth * 0.6f else contentWidth
        for (note in model.bottomNotes) {
            reserve += note.label?.let { PDFText.height(it, textStyle(style.fontSizes.small, PDFTemplate.Weight.semibold), width) } ?: 0f
            reserve += PDFText.height(note.text, textStyle(style.fontSizes.body), width) + 4
        }
        reserve += style.blockSpacing.toFloat() / 2
    }
    if (!signatureInRow && template.block("signature") != null) {
        reserve += (style.signatureHeight ?: 36.0).toFloat() * (if (request.signature == null) 0.5f else 1f) + style.fontSizes.body.toFloat() * 2.6f
    }
    return reserve
}

/** Closing notes keep the left ~60% of the row, so the signature can sit beside them. */
fun PDFComposer.drawNotes(notes: List<PDFDocumentModel.Note>, closing: Boolean = false) {
    if (closing) closingNotesTop = y
    if (notes.isEmpty()) return
    val width = if (closing && template.block("signature") != null) contentWidth * 0.6f else contentWidth
    for (note in notes) {
        val labelHeight = note.label?.let { PDFText.height(it, textStyle(style.fontSizes.small, PDFTemplate.Weight.semibold), width) } ?: 0f
        val textHeight = PDFText.height(note.text, textStyle(style.fontSizes.body), width)
        if (y + labelHeight + textHeight + 4 > contentBottom) {
            newPage()
            if (closing) closingNotesTop = y
        }
        note.label?.let { y += text(it, textStyle(style.fontSizes.small, PDFTemplate.Weight.semibold, mutedColor, uppercase = true), left, width, y) }
        y += text(note.text, textStyle(style.fontSizes.body), left, width, y) + 4
    }
    y += style.blockSpacing.toFloat() / 2
}

/** The width of the signature block, also reserved by the closing row. */
val PDFComposer.signatureWidth: Float get() = min(contentWidth * 0.32f, 180f)

fun PDFComposer.drawSignature(variant: String) {
    val signature = model.signature
    val width = signatureWidth
    // With a signature image the box is full height; without one it leaves half the space to sign by hand.
    val imageHeight = (style.signatureHeight ?: 36.0).toFloat() * (if (request.signature == null) 0.5f else 1f)
    val height = imageHeight + style.fontSizes.body.toFloat() * 2.6f
    var x = if (variant == "left") left else left + contentWidth - width
    // The foot of the page is the natural place; when the closing row runs too low, sit in that row instead.
    val earliest = max(closingNotesTop ?: y, if (variant == "left") y else 0f)
    var top = contentBottom - height
    if (top + 0.5f < earliest) {
        val rowTop = closingRowTop
        if (variant != "left" && rowTop != null && rowTop + height <= contentBottom) {
            top = rowTop
            x = closingSignatureX ?: x
        } else {
            newPage()
            top = max(y, contentBottom - height)
        }
    }
    image(request.signature)?.let { draw(it, RectF(x, top, x + width, top + imageHeight), alignRight = variant != "left") }
    top += imageHeight
    rule(top, x, width)
    top += 3
    val align = if (variant == "left") Leading else Right
    top += text(signature.forBusiness, textStyle(style.fontSizes.body, PDFTemplate.Weight.semibold, align = align), x, width, top)
    top += text(signature.authorisedSignatory, textStyle(style.fontSizes.small, color = mutedColor, align = align), x, width, top)
    y = max(y, top + style.blockSpacing.toFloat())
}

/** Column widths and row heights for a table (`RENDERING.md` §1.1). iOS: `TableLayout`. */
class TableLayout(composer: PDFComposer, columns: List<PDFDocumentModel.Column>, rows: List<List<String>>, width: Float, compact: Boolean) {
    val widths: List<Float>
    val rowHeights: List<Float>
    val headerHeight: Float
    val padding = composer.style.table.rowPadding

    init {
        val style = composer.style
        val headerStyle = composer.textStyle(style.fontSizes.small, style.table.headerWeight, uppercase = style.table.headerUppercase)
        val cellStyle = composer.textStyle(style.fontSizes.body)
        val horizontal = padding.horizontal.toFloat() * 2
        val natural = columns.mapIndexed { index, column ->
            var widest = PDFText.width(if (style.table.headerUppercase) column.label.uppercase() else column.label, headerStyle)
            for (row in rows) if (index < row.size) widest = max(widest, PDFText.width(row[index], cellStyle))
            widest + horizontal
        }.toMutableList()
        // The description column is the flexible one; everything else keeps its natural width.
        val flexible = columns.indexOfFirst { it.id == "description" }
        if (flexible >= 0) {
            val minimum = width * (if (compact) 0.18f else 0.22f)
            val others = natural.filterIndexed { index, _ -> index != flexible }.sum()
            natural[flexible] = max(minimum, width - others)
        }
        val total = natural.sum()
        if (total > width && flexible >= 0) {
            val minimum = width * (if (compact) 0.18f else 0.22f)
            natural[flexible] = max(minimum, natural[flexible] - (total - width))
        }
        val corrected = natural.sum()
        val resolved = if (corrected > width) natural.map { it * width / corrected } else natural
        val vertical = padding.vertical.toFloat() * 2
        widths = resolved
        headerHeight = columns.mapIndexed { index, column -> PDFText.height(column.label, headerStyle, resolved[index] - horizontal) }.maxOrNull().let { (it ?: 0f) + vertical }
        rowHeights = rows.map { row ->
            row.mapIndexed { index, cell -> PDFText.height(cell, cellStyle, resolved[min(index, resolved.size - 1)] - horizontal) }.maxOrNull().let { (it ?: 0f) + vertical }
        }
    }
}
