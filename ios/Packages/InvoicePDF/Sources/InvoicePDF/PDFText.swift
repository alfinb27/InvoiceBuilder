import CoreText
import Foundation
import InvoiceCore
import UIKit

/// The bundled static Noto fonts (`spec/pdf/fonts`, ADR-0006): loaded once from the spec copy inside InvoiceCore
/// and handed out as Core Text fonts whose cascade list falls back to Noto Sans Devanagari, so Hindi text is drawn
/// with a bundled font, embedded in the PDF and still searchable.
final class PDFFonts: @unchecked Sendable {
    // CTFontDescriptor and CTFont are immutable and thread-safe; only the references are shared.
    private let latin: [PDFTemplate.Weight: CTFontDescriptor]
    private let devanagari: [PDFTemplate.Weight: CTFontDescriptor]
    /// Building a cascading font costs more than drawing with it, and a render asks for the same few sizes
    /// thousands of times.
    private let cache = NSCache<NSString, CTFontBox>()
    private let lock = NSLock()

    static let shared = PDFFonts()

    init() {
        var latin: [PDFTemplate.Weight: CTFontDescriptor] = [:]
        var devanagari: [PDFTemplate.Weight: CTFontDescriptor] = [:]
        let files: [(String, PDFTemplate.Weight, Bool)] = [
            ("NotoSans-Regular", .regular, false), ("NotoSans-SemiBold", .semibold, false),
            ("NotoSans-Bold", .bold, false), ("NotoSansDevanagari-Regular", .regular, true),
            ("NotoSansDevanagari-SemiBold", .semibold, true), ("NotoSansDevanagari-Bold", .bold, true),
        ]
        for (file, weight, isDevanagari) in files {
            guard let descriptor = Self.descriptor(file) else { continue }
            if isDevanagari { devanagari[weight] = descriptor } else { latin[weight] = descriptor }
        }
        self.latin = latin
        self.devanagari = devanagari
    }

    /// A font of `weight` at `size`; the system font if the bundled files could not be read.
    func font(_ weight: PDFTemplate.Weight, size: CGFloat) -> CTFont {
        let key = "\(weight.rawValue)-\(size)" as NSString
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache.object(forKey: key) { return cached.font }
        let font = makeFont(weight, size: size)
        cache.setObject(CTFontBox(font), forKey: key)
        return font
    }

    private func makeFont(_ weight: PDFTemplate.Weight, size: CGFloat) -> CTFont {
        guard let base = latin[weight] ?? latin[.regular] else {
            return CTFontCreateUIFontForLanguage(.system, size, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
        guard let fallback = devanagari[weight] ?? devanagari[.regular] else {
            return CTFontCreateWithFontDescriptor(base, size, nil)
        }
        let cascaded = CTFontDescriptorCreateCopyWithAttributes(
            base, [kCTFontCascadeListAttribute: [fallback]] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(cascaded, size, nil)
    }

    /// `NSCache` holds objects, and `CTFont` is a CoreFoundation type.
    private final class CTFontBox {
        let font: CTFont
        init(_ font: CTFont) { self.font = font }
    }

    private static func descriptor(_ file: String) -> CTFontDescriptor? {
        guard let data = try? Data(contentsOf: SpecResources.url("pdf/fonts/\(file).ttf")) else { return nil }
        return CTFontManagerCreateFontDescriptorFromData(data as CFData)
    }
}

/// How a run of text is drawn.
struct PDFTextStyle {
    var font: CTFont
    var color: UIColor
    var alignment: NSTextAlignment = .left
    var lineHeightMultiple: CGFloat = 1.2
    var uppercase = false

    func attributed(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineHeightMultiple = lineHeightMultiple
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(
            string: uppercase ? text.uppercased() : text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
        )
    }
}

/// Measuring and drawing text with Core Text, in UIKit's flipped coordinate space.
enum PDFText {
    /// The height `text` needs at `width`, rounded up.
    static func height(_ text: String, style: PDFTextStyle, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let framesetter = CTFramesetterCreateWithAttributedString(style.attributed(text))
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil
        )
        return ceil(size.height)
    }

    /// The width `text` needs on one line, rounded up.
    static func width(_ text: String, style: PDFTextStyle) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let line = CTLineCreateWithAttributedString(style.attributed(text))
        return ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
    }

    /// Draws `text` inside `rect` (top-left origin, as the rest of the renderer uses) and returns the height used.
    @discardableResult
    static func draw(_ text: String, style: PDFTextStyle, in rect: CGRect, context: CGContext,
                     pageHeight: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attributed = style.attributed(text)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let used = height(text, style: style, width: rect.width)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: pageHeight)
        context.scaleBy(x: 1, y: -1)
        let flipped = CGRect(x: rect.minX, y: pageHeight - rect.minY - max(rect.height, used),
                             width: rect.width, height: max(rect.height, used))
        let path = CGPath(rect: flipped, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        context.restoreGState()
        return used
    }
}

extension UIColor {
    /// `#RRGGBB` from a template or a business accent colour; mid grey for anything else.
    convenience init(pdfHex hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self.init(white: 0.5, alpha: 1)
            return
        }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
