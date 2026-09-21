import CoreGraphics
import Foundation
import InvoiceCore
import UIKit

/// What a render needs: the strings (`PDFDocumentModel`), the template, the page size and the images.
public struct PDFRenderRequest: Sendable {
    public var model: PDFDocumentModel
    public var template: PDFTemplate
    /// `A4` or `Letter`, from the tax config.
    public var paperSize: String
    /// The business accent colour (`#RRGGBB`); the template decides where it is used.
    public var accentHex: String?
    public var logo: Data?
    public var signature: Data?

    public init(model: PDFDocumentModel, template: PDFTemplate, paperSize: String = "A4",
                accentHex: String? = nil, logo: Data? = nil, signature: Data? = nil) {
        self.model = model
        self.template = template
        self.paperSize = paperSize
        self.accentHex = accentHex
        self.logo = logo
        self.signature = signature
    }
}

/// Draws a document natively (ADR-0006): Core Text inside `UIGraphicsPDFRenderer`, laid out twice so every page
/// can say "Page x of y" (`spec/pdf/RENDERING.md` §3).
public enum PDFRenderer {
    public static func render(_ request: PDFRenderRequest) -> Data {
        let pages = PDFComposer(request: request).run(totalPages: nil, renderer: nil)
        let size = PDFComposer.pageSize(for: request.paperSize)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: [request.model.title, request.model.number].compactMap { $0 }
                .joined(separator: " "),
            kCGPDFContextCreator as String: "InvoiceBuilder",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size), format: format)
        return renderer.pdfData { context in
            _ = PDFComposer(request: request).run(totalPages: pages, renderer: context)
        }
    }

    /// The number of pages the document needs, without drawing it (the preview shows it while a render runs).
    public static func pageCount(_ request: PDFRenderRequest) -> Int {
        PDFComposer(request: request).run(totalPages: nil, renderer: nil)
    }
}

/// Lays the blocks out top to bottom, breaking pages as `RENDERING.md` §3 requires. The same code runs twice: once
/// to count pages (`renderer == nil`, nothing is drawn), once to draw them.
final class PDFComposer {
    let request: PDFRenderRequest
    let pageSize: CGSize
    let fonts = PDFFonts.shared

    private var renderer: UIGraphicsPDFRendererContext?
    private var totalPages: Int?
    private var pageIndex = 0
    var y: CGFloat = 0
    /// Set while the items table still has rows to draw on the next page (the footer then says so).
    var tableContinues = false
    /// Where the closing notes started, so the signature can sit beside them rather than under them.
    var closingNotesTop: CGFloat?
    /// The bottom of the QR column, and where the closing row starts, so the signature can sit in that same row.
    var closingRightBottom: CGFloat = 0
    var closingRowTop: CGFloat?
    var closingSignatureX: CGFloat?

    var model: PDFDocumentModel { request.model }
    var template: PDFTemplate { request.template }
    var style: PDFTemplate.Style { template.style }
    var context: CGContext? { renderer?.cgContext }

    init(request: PDFRenderRequest) {
        self.request = request
        pageSize = Self.pageSize(for: request.paperSize)
    }

    static func pageSize(for paper: String) -> CGSize {
        paper.caseInsensitiveCompare("Letter") == .orderedSame ? CGSize(width: 612, height: 792)
                                                               : CGSize(width: 595, height: 842)
    }

    // MARK: Geometry

    /// How small the payment QR may get to keep a document on one page (`RENDERING.md` §3.4): 56 pt ≈ 2 cm,
    /// which every UPI app still scans.
    static let minimumQRSize: CGFloat = 56

    var margins: PDFTemplate.Page.Margins { template.page.margins }
    var left: CGFloat { margins.left }
    var contentWidth: CGFloat { pageSize.width - margins.left - margins.right }
    var contentBottom: CGFloat { pageSize.height - margins.bottom - template.page.footerHeight }

    // MARK: Colours

    var accent: UIColor { UIColor(pdfHex: request.accentHex ?? "#1F6FEB") }
    var textColor: UIColor { UIColor(pdfHex: style.colors.text) }
    var mutedColor: UIColor { UIColor(pdfHex: style.colors.muted) }
    var ruleColor: UIColor {
        template.uses(.rules) ? accent.withAlphaComponent(0.5) : UIColor(pdfHex: style.colors.rule)
    }

    func textStyle(_ size: Double, weight: PDFTemplate.Weight = .regular, color: UIColor? = nil,
                   align: NSTextAlignment = .left, uppercase: Bool = false) -> PDFTextStyle {
        PDFTextStyle(font: fonts.font(weight, size: size), color: color ?? textColor, alignment: align,
                     lineHeightMultiple: style.lineHeight, uppercase: uppercase)
    }

    // MARK: Run

    /// Lays the document out and returns the number of pages.
    @discardableResult
    func run(totalPages: Int?, renderer: UIGraphicsPDFRendererContext?) -> Int {
        self.renderer = renderer
        self.totalPages = totalPages
        pageIndex = 0
        beginPage()
        for block in template.blocks {
            switch block.id {
            case .header: drawHeader(block.variant)
            case .parties:
                drawParties(block.variant)
                drawNotes(model.topNotes)
            case .items: drawItems(block.variant)
            case .totals: drawTotals()
            case .payment: drawPayment(block.variant)
            case .notes: drawNotes(model.bottomNotes, closing: true)
            case .signature: drawSignature(block.variant)
            default: break // a block a newer spec adds: skip it rather than fail
            }
        }
        endPage()
        return pageIndex + 1
    }

    // MARK: Pages

    private func beginPage() {
        renderer?.beginPage()
        y = margins.top
        closingRightBottom = 0
        closingNotesTop = nil
        closingRowTop = nil
        closingSignatureX = nil
        if let context, model.isDraft, let draft = model.draftLabel { drawWatermark(draft, context: context) }
        if pageIndex > 0 { drawContinuationHeader() }
    }

    private func endPage() {
        guard let context else { return }
        let page = pageIndex + 1
        let text = model.footer.pageLabel
            .replacingOccurrences(of: "{page}", with: String(page))
            .replacingOccurrences(of: "{pages}", with: String(totalPages ?? page))
        let rect = CGRect(x: left, y: pageSize.height - margins.bottom - template.page.footerHeight,
                          width: contentWidth, height: template.page.footerHeight)
        PDFText.draw(text, style: textStyle(style.fontSizes.small, color: mutedColor, align: .center), in: rect,
                     context: context, pageHeight: pageSize.height)
        if tableContinues {
            PDFText.draw(model.footer.continued,
                         style: textStyle(style.fontSizes.small, color: mutedColor, align: .right),
                         in: CGRect(x: left, y: rect.minY - style.fontSizes.small * 1.6, width: contentWidth,
                                    height: style.fontSizes.small * 1.6),
                         context: context, pageHeight: pageSize.height)
        }
    }

    func newPage() {
        endPage()
        pageIndex += 1
        beginPage()
    }

    /// Starts a new page when `height` would not fit under the current cursor.
    func need(_ height: CGFloat) {
        if y + height > contentBottom { newPage() }
    }

    /// The compact header repeated on later pages (§3.1).
    private func drawContinuationHeader() {
        let line = [model.title, model.number].compactMap { $0 }.joined(separator: " · ")
        if let context {
            PDFText.draw(line, style: textStyle(style.fontSizes.heading, weight: .semibold, color: mutedColor),
                         in: CGRect(x: left, y: y, width: contentWidth, height: style.fontSizes.heading * 1.6),
                         context: context, pageHeight: pageSize.height)
        }
        y += style.fontSizes.heading * 1.6 + style.blockSpacing / 2
    }

    private func drawWatermark(_ text: String, context: CGContext) {
        let font = fonts.font(.bold, size: 96)
        let attributed = PDFTextStyle(font: font, color: UIColor(white: 0.85, alpha: 0.55), alignment: .center)
            .attributed(text)
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.saveGState()
        context.translateBy(x: pageSize.width / 2, y: pageSize.height / 2)
        context.rotate(by: -.pi / 6)
        context.textMatrix = .identity
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: -width / 2, y: 0)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    // MARK: Primitives

    @discardableResult
    func text(_ string: String, _ style: PDFTextStyle, x: CGFloat, width: CGFloat, at top: CGFloat? = nil)
        -> CGFloat {
        let height = PDFText.height(string, style: style, width: width)
        if let context {
            PDFText.draw(string, style: style, in: CGRect(x: x, y: top ?? y, width: width, height: height),
                         context: context, pageHeight: pageSize.height)
        }
        return height
    }

    func rule(at top: CGFloat, x: CGFloat? = nil, width: CGFloat? = nil, color: UIColor? = nil) {
        guard let context else { return }
        context.saveGState()
        context.setStrokeColor((color ?? ruleColor).cgColor)
        context.setLineWidth(style.rule.width)
        context.move(to: CGPoint(x: x ?? left, y: top))
        context.addLine(to: CGPoint(x: (x ?? left) + (width ?? contentWidth), y: top))
        context.strokePath()
        context.restoreGState()
    }

    func fill(_ rect: CGRect, color: UIColor) {
        guard let context else { return }
        context.saveGState()
        context.setFillColor(color.cgColor)
        context.fill(rect)
        context.restoreGState()
    }
}
