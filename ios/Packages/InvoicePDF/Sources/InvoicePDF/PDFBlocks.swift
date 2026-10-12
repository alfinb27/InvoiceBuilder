import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import InvoiceCore
import UIKit

/// The blocks of `spec/pdf/RENDERING.md` §2, drawn in the order the template lists them.
extension PDFComposer {
    // MARK: Header

    func drawHeader(_ variant: PDFTemplate.Block.Variant) {
        if variant == .band {
            drawHeaderBand()
            return
        }
        let logo = image(request.logo)
        let logoWidth = logo == nil ? 0 : style.logo.maxWidth + style.blockSpacing
        let metaWidth = max(contentWidth * 0.34, 150)
        let titleX = variant == .logoLeft ? left + logoWidth : left
        let titleWidth = contentWidth - metaWidth - logoWidth - style.blockSpacing
        let top = y

        if let logo {
            let box = CGRect(x: variant == .logoLeft ? left : left + contentWidth - style.logo.maxWidth, y: top,
                             width: style.logo.maxWidth, height: style.logo.maxHeight)
            draw(logo, in: box, alignRight: variant != .logoLeft)
        }

        var titleBottom = top
        titleBottom += text(model.title,
                            textStyle(style.fontSizes.title, weight: .bold,
                                      color: template.uses(.title) ? accent : textColor),
                            x: titleX, width: titleWidth, at: titleBottom)
        if let number = model.number {
            titleBottom += 2
            titleBottom += text("\(model.numberLabel) \(number)",
                                textStyle(style.fontSizes.heading, weight: .semibold), x: titleX, width: titleWidth,
                                at: titleBottom)
        }

        let metaX = left + contentWidth - metaWidth
        let metaBottom = drawFields(model.meta, x: metaX, width: metaWidth, top: variant == .logoRight && logo != nil
                                    ? top + style.logo.maxHeight + 6 : top)
        y = max(max(titleBottom, metaBottom), logo == nil ? top : top + style.logo.maxHeight)
        y += 6
        rule(at: y)
        y += style.blockSpacing * 0.75
    }

    /// An accent band across the top with the title and number reversed out of it.
    private func drawHeaderBand() {
        let onAccent = UIColor(pdfHex: style.colors.onAccent)
        let width = contentWidth * 0.6
        let titleStyle = textStyle(style.fontSizes.title, weight: .bold, color: onAccent)
        let numberStyle = textStyle(style.fontSizes.heading, weight: .semibold, color: onAccent)
        let numberText = model.number.map { "\(model.numberLabel) \($0)" }
        // Measure first: the band must be tall enough for the title and the number, whatever the type sizes are.
        let bandHeight = 18 + PDFText.height(model.title, style: titleStyle, width: width)
            + (numberText.map { PDFText.height($0, style: numberStyle, width: width) } ?? 0) + 16
        fill(CGRect(x: 0, y: 0, width: pageSize.width, height: bandHeight), color: accent)
        var top: CGFloat = 18
        top += text(model.title, titleStyle, x: left, width: width, at: top)
        if let numberText {
            top += text(numberText, numberStyle, x: left, width: width, at: top)
        }
        if let logo = image(request.logo) {
            draw(logo, in: CGRect(x: left + contentWidth - style.logo.maxWidth, y: 14, width: style.logo.maxWidth,
                                  height: min(style.logo.maxHeight, bandHeight - 28)), alignRight: true)
        }
        y = bandHeight + style.blockSpacing
        let metaWidth = max(contentWidth * 0.34, 150)
        y = drawFields(model.meta, x: left + contentWidth - metaWidth, width: metaWidth, top: y)
        y += style.blockSpacing
    }

    /// Label / value pairs, right aligned. Returns the bottom edge.
    @discardableResult
    func drawFields(_ fields: [PDFDocumentModel.Field], x: CGFloat, width: CGFloat, top: CGFloat,
                    labelColor: UIColor? = nil) -> CGFloat {
        var bottom = top
        let labelWidth = width * 0.5
        for field in fields {
            let labelStyle = textStyle(style.fontSizes.small, color: labelColor ?? mutedColor, align: .right)
            let valueStyle = textStyle(style.fontSizes.body, weight: .semibold, align: .right)
            let height = max(PDFText.height(field.label, style: labelStyle, width: labelWidth),
                             PDFText.height(field.value, style: valueStyle, width: width - labelWidth - 6))
            text(field.label, labelStyle, x: x, width: labelWidth, at: bottom + 1)
            text(field.value, valueStyle, x: x + labelWidth + 6, width: width - labelWidth - 6, at: bottom)
            bottom += height + 2
        }
        return bottom
    }

    // MARK: Parties

    func drawParties(_ variant: PDFTemplate.Block.Variant) {
        let stacked = variant == .stacked || model.buyer == nil
        let columnWidth = stacked ? contentWidth : (contentWidth - style.blockSpacing) / 2
        let top = y
        var leftBottom = drawParty(model.seller, x: left, width: columnWidth, top: top)
        var rightBottom = top
        if let buyer = model.buyer {
            if stacked {
                leftBottom = drawParty(buyer, x: left, width: columnWidth, top: leftBottom + style.blockSpacing / 2)
                if let shipTo = model.shipTo {
                    leftBottom = drawParty(shipTo, x: left, width: columnWidth,
                                           top: leftBottom + style.blockSpacing / 2)
                }
            } else {
                let x = left + columnWidth + style.blockSpacing
                rightBottom = drawParty(buyer, x: x, width: columnWidth, top: top)
                if let shipTo = model.shipTo {
                    rightBottom = drawParty(shipTo, x: x, width: columnWidth, top: rightBottom + style.blockSpacing / 2)
                }
            }
        }
        y = max(leftBottom, rightBottom) + style.blockSpacing
    }

    private func drawParty(_ party: PDFDocumentModel.Party, x: CGFloat, width: CGFloat, top: CGFloat) -> CGFloat {
        var bottom = top
        if let heading = party.heading {
            bottom += text(heading, textStyle(style.fontSizes.small, weight: .semibold, color: mutedColor,
                                              uppercase: true), x: x, width: width, at: bottom)
            bottom += 2
        }
        if !party.name.isEmpty {
            bottom += text(party.name, textStyle(style.fontSizes.body + 1, weight: .semibold), x: x, width: width,
                           at: bottom)
        }
        for line in party.lines {
            bottom += text(line, textStyle(style.fontSizes.body, color: mutedColor), x: x, width: width, at: bottom)
        }
        for field in party.fields {
            bottom += text("\(field.label) \(field.value)", textStyle(style.fontSizes.body), x: x, width: width,
                           at: bottom)
        }
        return bottom
    }

    // MARK: Items table

    func drawItems(_ variant: PDFTemplate.Block.Variant) {
        let table = TableLayout(composer: self, columns: model.columns, rows: model.rows, width: contentWidth,
                                compact: variant == .compact)
        drawTableHeader(table)
        for (index, row) in model.rows.enumerated() {
            let height = table.rowHeights[index]
            if y + height > contentBottom {
                tableContinues = true  // this page ends mid-table, so its footer says "continued"
                newPage()
                tableContinues = false
                drawTableHeader(table)
            }
            let fill: UIColor? = variant == .zebra && index.isMultiple(of: 2)
                ? style.colors.zebraFill.map { UIColor(pdfHex: $0) } : nil
            drawTableRow(row, table: table, height: height, fill: fill,
                         rule: style.table.rowRule == .below || variant == .ruled)
        }
        y += style.blockSpacing / 2
    }

    private func drawTableHeader(_ table: TableLayout) {
        let height = table.headerHeight
        if y + height > contentBottom { newPage() }
        let headerFill: UIColor? = template.uses(.tableHeaderFill) ? accent.withAlphaComponent(0.12)
            : style.colors.tableHeaderFill.map { UIColor(pdfHex: $0) }
        if let headerFill {
            fill(CGRect(x: left, y: y, width: contentWidth, height: height), color: headerFill)
        }
        let color = template.uses(.tableHeaderText) ? accent : textColor
        var x = left
        for (index, column) in model.columns.enumerated() {
            let width = table.widths[index]
            let headerStyle = textStyle(style.fontSizes.small, weight: style.table.headerWeight, color: color,
                                        align: column.align == .trailing ? .right : .left,
                                        uppercase: style.table.headerUppercase)
            text(column.label, headerStyle, x: x + table.padding.horizontal,
                 width: width - table.padding.horizontal * 2, at: y + table.padding.vertical)
            x += width
        }
        y += height
        rule(at: y)
    }

    private func drawTableRow(_ row: [String], table: TableLayout, height: CGFloat, fill background: UIColor?,
                              rule drawRule: Bool) {
        if let background {
            fill(CGRect(x: left, y: y, width: contentWidth, height: height), color: background)
        }
        var x = left
        for (index, column) in model.columns.enumerated() {
            let width = table.widths[index]
            let cellStyle = textStyle(style.fontSizes.body,
                                      align: column.align == .trailing ? .right : .left)
            text(row[index], cellStyle, x: x + table.padding.horizontal,
                 width: width - table.padding.horizontal * 2, at: y + table.padding.vertical)
            x += width
        }
        y += height
        if drawRule { rule(at: y) }
    }

    // MARK: Totals

    func drawTotals() {
        let width = max(contentWidth * 0.42, 190)
        let summaryWidth = min(contentWidth * 0.55, contentWidth - width - style.blockSpacing)
        // The tax summary sits beside the totals, not above them, whenever it still gets a readable width — that
        // is how an invoice normally reads, and it keeps a short document on one page (`RENDERING.md` §1.2).
        let sideBySide = model.taxSummary != nil && summaryWidth >= 170
        let summaryHeight = taxSummaryHeight(width: sideBySide ? summaryWidth : nil)
        let totalsHeight = totalsBlockHeight()
        need(sideBySide ? max(summaryHeight, totalsHeight) : summaryHeight + totalsHeight + style.blockSpacing)
        let top = y
        var summaryBottom = y
        if let summary = model.taxSummary {
            drawSummary(summary, width: sideBySide ? summaryWidth : nil)
            summaryBottom = y
            if sideBySide { y = top } else { y += style.blockSpacing / 2 }
        }
        let x = left + contentWidth - width
        for row in model.totals {
            let strong = row.emphasis == .strong
            if strong {
                rule(at: y, x: x, width: width)
                y += 4
            }
            let labelStyle = textStyle(style.fontSizes.body, weight: strong ? .bold : .regular,
                                       color: strong ? textColor : mutedColor)
            let valueStyle = textStyle(strong ? style.fontSizes.heading + 1 : style.fontSizes.body,
                                       weight: strong ? .bold : .regular,
                                       color: strong && template.uses(.totalRow) ? accent : textColor, align: .right)
            let height = max(PDFText.height(row.label, style: labelStyle, width: width * 0.55),
                             PDFText.height(row.value, style: valueStyle, width: width * 0.45))
            text(row.label, labelStyle, x: x, width: width * 0.55, at: y)
            text(row.value, valueStyle, x: x + width * 0.55, width: width * 0.45, at: y)
            y += height + 3
        }
        y = max(y + 4, summaryBottom)
        for line in [model.reverseChargeNote, model.homeTotals, model.amountInWords].compactMap({ $0 }) {
            y += text(line, textStyle(style.fontSizes.small, color: mutedColor), x: left, width: contentWidth,
                      at: y) + 2
        }
        y += style.blockSpacing / 2
    }

    private func drawSummary(_ summary: PDFDocumentModel.Table, width: CGFloat? = nil) {
        let width = width ?? min(contentWidth * 0.62, contentWidth)
        let table = TableLayout(composer: self, columns: summary.columns, rows: summary.rows, width: width,
                                compact: true)
        var x = left
        for (index, column) in summary.columns.enumerated() {
            let headerStyle = textStyle(style.fontSizes.small, weight: .semibold, color: mutedColor,
                                        align: column.align == .trailing ? .right : .left)
            text(column.label, headerStyle, x: x + table.padding.horizontal,
                 width: table.widths[index] - table.padding.horizontal * 2, at: y)
            x += table.widths[index]
        }
        y += table.headerHeight - table.padding.vertical
        rule(at: y, x: left, width: width)
        y += 2
        for (rowIndex, row) in summary.rows.enumerated() {
            let last = rowIndex == summary.rows.count - 1
            x = left
            var height: CGFloat = 0
            for (index, column) in summary.columns.enumerated() {
                let cellStyle = textStyle(style.fontSizes.small, weight: last ? .semibold : .regular,
                                          align: column.align == .trailing ? .right : .left)
                let cellWidth = table.widths[index] - table.padding.horizontal * 2
                height = max(height, PDFText.height(row[index], style: cellStyle, width: cellWidth))
                text(row[index], cellStyle, x: x + table.padding.horizontal, width: cellWidth, at: y)
                x += table.widths[index]
            }
            y += height + 3
            if last { rule(at: y - 1, x: left, width: width) }
        }
    }

    private func totalsBlockHeight() -> CGFloat {
        let width = max(contentWidth * 0.42, 190)
        var height: CGFloat = 0
        for row in model.totals {
            let strong = row.emphasis == .strong
            let labelStyle = textStyle(style.fontSizes.body, weight: strong ? .bold : .regular)
            let valueStyle = textStyle(strong ? style.fontSizes.heading + 1 : style.fontSizes.body, align: .right)
            height += max(PDFText.height(row.label, style: labelStyle, width: width * 0.55),
                          PDFText.height(row.value, style: valueStyle, width: width * 0.45)) + 3
            if strong { height += 4 }
        }
        for line in [model.reverseChargeNote, model.homeTotals, model.amountInWords].compactMap({ $0 }) {
            height += PDFText.height(line, style: textStyle(style.fontSizes.small), width: contentWidth) + 2
        }
        return height + style.blockSpacing
    }

    private func taxSummaryHeight(width: CGFloat? = nil) -> CGFloat {
        guard let summary = model.taxSummary else { return 0 }
        let width = width ?? min(contentWidth * 0.62, contentWidth)
        let table = TableLayout(composer: self, columns: summary.columns, rows: summary.rows, width: width,
                                compact: true)
        return table.headerHeight + table.rowHeights.reduce(0, +) + style.blockSpacing / 2
    }

    // MARK: Payment, notes, signature

    func drawPayment(_ variant: PDFTemplate.Block.Variant) {
        let payment = model.payment
        guard !payment.bank.isEmpty || payment.upi != nil else { return }
        var qrSize = CGFloat(style.qrSize ?? 80)
        // The closing row is three columns: bank details, the QR with its captions, and the signature. Laying them
        // side by side costs the height of the tallest one, not the sum, so a short invoice stays on one page.
        let qrColumn = max(qrSize, 150)
        // Reserve a signature column beside the QR only when the bank details still get a usable width.
        let signatureColumn: CGFloat = {
            guard template.block(.signature)?.variant == .right, payment.upi != nil else { return 0 }
            let candidate = signatureWidth + style.blockSpacing
            return contentWidth - qrColumn - candidate - style.blockSpacing >= 180 ? candidate : 0
        }()
        let sideBySide = variant != .stacked && payment.upi != nil
        let bankWidth = sideBySide ? contentWidth - qrColumn - signatureColumn - style.blockSpacing : contentWidth
        var bankHeight: CGFloat = 0
        if !payment.bank.isEmpty {
            bankHeight = PDFText.height(model.payment.bank.map { "\($0.label) \($0.value)" }.joined(separator: "\n"),
                                        style: textStyle(style.fontSizes.body), width: bankWidth)
                + style.fontSizes.small * 2
        }
        let captions = style.fontSizes.small * 3
        // Side by side the row costs the tallest column; stacked, the QR sits under the bank details.
        func blockHeight(qr: CGFloat) -> CGFloat {
            guard payment.upi != nil else { return bankHeight }
            return sideBySide ? max(bankHeight, qr + captions)
                              : bankHeight + qr + captions + style.blockSpacing / 2
        }
        var height = blockHeight(qr: qrSize)
        // A page that would hold nothing but the closing blocks is worse than a slightly smaller QR (§3.4).
        let reserve = closingReserve(signatureInRow: sideBySide && signatureColumn > 0)
        let available = contentBottom - y - reserve
        if payment.upi != nil, height > available {
            let room = floor(sideBySide ? available - captions
                                        : available - bankHeight - captions - style.blockSpacing / 2)
            if room >= PDFComposer.minimumQRSize {
                qrSize = min(qrSize, room)
                height = blockHeight(qr: qrSize)
            }
        }
        need(height + reserve)

        let top = y
        var bottom = top
        if !payment.bank.isEmpty {
            bottom += text(labelText("bankDetails"), textStyle(style.fontSizes.small, weight: .semibold,
                                                               color: mutedColor, uppercase: true),
                           x: left, width: bankWidth, at: bottom)
            bottom += 2
            // Label and value in two columns, so "Account name" never runs into the name itself.
            let labelWidth = min(bankWidth * 0.42, 110)
            for field in payment.bank {
                let labelStyle = textStyle(style.fontSizes.body, color: mutedColor)
                let valueStyle = textStyle(style.fontSizes.body)
                let height = max(PDFText.height(field.label, style: labelStyle, width: labelWidth),
                                 PDFText.height(field.value, style: valueStyle, width: bankWidth - labelWidth - 6))
                text(field.label, labelStyle, x: left, width: labelWidth, at: bottom)
                text(field.value, valueStyle, x: left + labelWidth + 6, width: bankWidth - labelWidth - 6,
                     at: bottom)
                bottom += height
            }
        }
        if let upi = payment.upi {
            let stackedQR = !sideBySide
            let columnX = stackedQR ? left : left + contentWidth - signatureColumn - qrColumn
            let columnWidth = stackedQR ? contentWidth : qrColumn
            let qrTop = stackedQR ? bottom + style.blockSpacing / 2 : top
            if let qr = qrImage(upi.payload) {
                draw(qr, in: CGRect(x: stackedQR ? columnX : columnX + columnWidth - qrSize, y: qrTop,
                                    width: qrSize, height: qrSize), alignRight: false, interpolate: false)
            }
            var captionTop = qrTop + qrSize + 2
            let align: NSTextAlignment = stackedQR ? .left : .right
            captionTop += text(upi.id, textStyle(style.fontSizes.small, weight: .semibold, align: align),
                               x: columnX, width: columnWidth, at: captionTop)
            captionTop += text(upi.caption, textStyle(style.fontSizes.small, color: mutedColor, align: align),
                               x: columnX, width: columnWidth, at: captionTop)
            if stackedQR {
                bottom = max(bottom, captionTop)
            } else {
                closingRightBottom = captionTop
                closingRowTop = top
                closingSignatureX = left + contentWidth - signatureWidth
            }
        }
        y = bottom + style.blockSpacing / 2
    }

    /// What still has to fit under the payment block: the closing notes, and the signature unless it can sit in
    /// the payment row (otherwise it is pinned to the foot of the page). Reserving it keeps the closing region
    /// together — a page holding nothing but a note and a signature line reads as a mistake (`RENDERING.md` §3.4).
    private func closingReserve(signatureInRow: Bool) -> CGFloat {
        var reserve: CGFloat = 0
        if template.block(.notes) != nil, !model.bottomNotes.isEmpty {
            let width = template.block(.signature) != nil ? contentWidth * 0.6 : contentWidth
            for note in model.bottomNotes {
                reserve += note.label.map {
                    PDFText.height($0, style: textStyle(style.fontSizes.small, weight: .semibold), width: width)
                } ?? 0
                reserve += PDFText.height(note.text, style: textStyle(style.fontSizes.body), width: width) + 4
            }
            reserve += style.blockSpacing / 2
        }
        if !signatureInRow, template.block(.signature) != nil {
            reserve += CGFloat(style.signatureHeight ?? 36) * (request.signature == nil ? 0.5 : 1)
                + style.fontSizes.body * 2.6
        }
        return reserve
    }

    /// Closing notes keep the left ~60% of the row, so the signature can sit beside them.
    func drawNotes(_ notes: [PDFDocumentModel.Note], closing: Bool = false) {
        if closing { closingNotesTop = y }
        guard !notes.isEmpty else { return }
        let width = closing && template.block(.signature) != nil ? contentWidth * 0.6 : contentWidth
        for note in notes {
            let labelHeight = note.label.map {
                PDFText.height($0, style: textStyle(style.fontSizes.small, weight: .semibold), width: width)
            } ?? 0
            let textHeight = PDFText.height(note.text, style: textStyle(style.fontSizes.body), width: width)
            if y + labelHeight + textHeight + 4 > contentBottom {
                newPage()
                if closing { closingNotesTop = y }
            }
            if let label = note.label {
                y += text(label, textStyle(style.fontSizes.small, weight: .semibold, color: mutedColor,
                                           uppercase: true), x: left, width: width, at: y)
            }
            y += text(note.text, textStyle(style.fontSizes.body), x: left, width: width, at: y) + 4
        }
        y += style.blockSpacing / 2
    }

    /// The width of the signature block, also reserved by the closing row.
    var signatureWidth: CGFloat { min(contentWidth * 0.32, 180) }

    func drawSignature(_ variant: PDFTemplate.Block.Variant) {
        let signature = model.signature
        let width = signatureWidth
        // With a signature image the box is full height; without one it leaves half the space to sign by hand.
        let imageHeight = CGFloat(style.signatureHeight ?? 36) * (request.signature == nil ? 0.5 : 1)
        let height = imageHeight + style.fontSizes.body * 2.6
        var x = variant == .left ? left : left + contentWidth - width
        // The foot of the page is the natural place; when the closing row runs too low, sit in that row instead.
        let earliest = max(closingNotesTop ?? y, variant == .left ? y : 0)
        var top = contentBottom - height
        if top + 0.5 < earliest {
            if variant != .left, let rowTop = closingRowTop, rowTop + height <= contentBottom {
                top = rowTop
                x = closingSignatureX ?? x
            } else {
                newPage()
                top = max(y, contentBottom - height)
            }
        }
        if let image = image(request.signature) {
            draw(image, in: CGRect(x: x, y: top, width: width, height: imageHeight), alignRight: variant != .left)
        }
        top += imageHeight
        rule(at: top, x: x, width: width)
        top += 3
        let align: NSTextAlignment = variant == .left ? .left : .right
        top += text(signature.forBusiness, textStyle(style.fontSizes.body, weight: .semibold, align: align), x: x,
                    width: width, at: top)
        top += text(signature.authorisedSignatory, textStyle(style.fontSizes.small, color: mutedColor, align: align),
                    x: x, width: width, at: top)
        y = max(y, top + style.blockSpacing)
    }

    // MARK: Images

    func image(_ data: Data?) -> UIImage? {
        data.flatMap { UIImage(data: $0) }
    }

    /// Draws `image` inside `box`, keeping its aspect ratio and pinning it to the top (and to the right when asked).
    func draw(_ image: UIImage, in box: CGRect, alignRight: Bool, interpolate: Bool = true) {
        guard let context, image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(box.width / image.size.width, box.height / image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: alignRight ? box.maxX - size.width : box.minX, y: box.minY)
        context.saveGState()
        context.interpolationQuality = interpolate ? .high : .none
        image.draw(in: CGRect(origin: origin, size: size))
        context.restoreGState()
    }

    /// The UPI payment link as a QR code (`ENGINE.md` §9), error correction M. The box it sits in is a fixed size,
    /// so the layout pass (which draws nothing) can skip the work entirely.
    func qrImage(_ payload: String) -> UIImage? {
        guard context != nil else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = Self.ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Building a `CIContext` costs more than drawing the code, and Core Image documents the class as safe to use
    /// from several threads at once (the iOS 27 SDK marks it `Sendable`).
    private static let ciContext = CIContext()

    func labelText(_ key: String) -> String {
        PDFComposer.sharedLabels?.text(key) ?? key
    }

    /// The bundled labels, for the few strings a block needs that are not in the view model (section headings).
    static let sharedLabels = try? PDFLabels.bundled()
}

/// Column widths and row heights for a table (`RENDERING.md` §1.1): every column takes the width its widest cell
/// needs, and the description column absorbs what is left.
struct TableLayout {
    let widths: [CGFloat]
    let rowHeights: [CGFloat]
    let headerHeight: CGFloat
    let padding: PDFTemplate.Style.Table.Padding

    init(composer: PDFComposer, columns: [PDFDocumentModel.Column], rows: [[String]], width: CGFloat,
         compact: Bool) {
        let style = composer.style
        padding = style.table.rowPadding
        let headerStyle = composer.textStyle(style.fontSizes.small, weight: style.table.headerWeight,
                                             uppercase: style.table.headerUppercase)
        let cellStyle = composer.textStyle(style.fontSizes.body)
        let horizontal = padding.horizontal * 2

        var natural = columns.enumerated().map { index, column -> CGFloat in
            var widest = PDFText.width(style.table.headerUppercase ? column.label.uppercased() : column.label,
                                       style: headerStyle)
            for row in rows where index < row.count {
                widest = max(widest, PDFText.width(row[index], style: cellStyle))
            }
            return widest + horizontal
        }
        // The description column is the flexible one; everything else keeps its natural width.
        if let flexible = columns.firstIndex(where: { $0.id == "description" }) {
            let minimum = width * (compact ? 0.18 : 0.22)
            let others = natural.enumerated().filter { $0.offset != flexible }.map(\.element).reduce(0, +)
            natural[flexible] = max(minimum, width - others)
        }
        let total = natural.reduce(0, +)
        if total > width, let flexible = columns.firstIndex(where: { $0.id == "description" }) {
            let minimum = width * (compact ? 0.18 : 0.22)
            natural[flexible] = max(minimum, natural[flexible] - (total - width))
        }
        let corrected = natural.reduce(0, +)
        let resolved = corrected > width ? natural.map { $0 * width / corrected } : natural
        let vertical = padding.vertical * 2

        widths = resolved
        headerHeight = columns.enumerated().reduce(CGFloat(0)) { height, pair in
            max(height, PDFText.height(pair.element.label, style: headerStyle,
                                       width: resolved[pair.offset] - horizontal))
        } + vertical
        rowHeights = rows.map { row in
            row.enumerated().reduce(CGFloat(0)) { height, pair in
                max(height, PDFText.height(pair.element, style: cellStyle,
                                           width: resolved[min(pair.offset, resolved.count - 1)] - horizontal))
            } + vertical
        }
    }
}
