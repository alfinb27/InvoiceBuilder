// Option B prototype: native PDF drawing with Core Text + Core Graphics from the same view models (macOS CLI;
// the drawing code is identical on iOS inside UIGraphicsPDFRenderer). Two-pass pagination: measure rows, then draw
// with a repeated table header, unsplittable rows, a totals block kept whole, and "Page x of y".
// Build & run:  swiftc -O main.swift -o native-render && ./native-render <spikes/pdf dir>
import Foundation
import CoreText
import CoreGraphics

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "..")
let fontsDir = root.appendingPathComponent("fonts")
for f in (try? FileManager.default.contentsOfDirectory(at: fontsDir, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "ttf" {
    CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
}
let useNoto = FileManager.default.fileExists(atPath: fontsDir.appendingPathComponent("NotoSans-Regular.ttf").path)
func font(_ size: CGFloat, _ weight: String = "Regular") -> CTFont {
    let name = useNoto ? "NotoSans-\(weight)" : (weight == "Regular" ? "Inter-Regular" : "Inter-Regular_\(weight)")
    let base = CTFontCreateWithName(name as CFString, size, nil)
    let deva = CTFontDescriptorCreateWithNameAndSize((useNoto ? "NotoSansDevanagari-\(weight)" : "NotoSansDevanagari-Regular") as CFString, size)
    let desc = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base), [kCTFontCascadeListAttribute: [deva]] as CFDictionary)
    return CTFontCreateWithFontDescriptor(desc, size, nil)
}
func color(_ hex: String) -> CGColor {
    let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
    return CGColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
}
let ink = color("#111827"), muted = color("#4B5563"), line = color("#D8DEE6"), soft = color("#F3F5F8")

func attr(_ s: String, _ f: CTFont, _ c: CGColor = ink, align: CTTextAlignment = .left) -> NSAttributedString {
    var a = align
    let ps = withUnsafeBytes(of: &a) { ptr in
        [CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: ptr.baseAddress!)]
    }
    let style = CTParagraphStyleCreate(ps, ps.count)
    return NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: f,
        kCTForegroundColorAttributeName as NSAttributedString.Key: c, kCTParagraphStyleAttributeName as NSAttributedString.Key: style])
}
func height(_ a: NSAttributedString, width: CGFloat) -> CGFloat {
    let fs = CTFramesetterCreateWithAttributedString(a)
    return ceil(CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil).height)
}
// Draws with a top-left origin (y grows downwards) on a flipped-page coordinate system.
func draw(_ a: NSAttributedString, in ctx: CGContext, x: CGFloat, y: CGFloat, width: CGFloat, pageH: CGFloat) -> CGFloat {
    let h = height(a, width: width)
    let fs = CTFramesetterCreateWithAttributedString(a)
    let path = CGPath(rect: CGRect(x: x, y: pageH - y - h, width: width, height: h), transform: nil)
    CTFrameDraw(CTFramesetterCreateFrame(fs, CFRange(), path, nil), ctx)
    return h
}

struct VM: Decodable {
    struct KV: Decodable { let label: String; let value: String }
    struct Party: Decodable { let name: String; let lines: [String]; let ids: [KV] }
    struct Col: Decodable { let key: String; let label: String; let align: String? }
    struct Total: Decodable { let label: String; let value: String; let emphasis: Bool? }
    struct Sign: Decodable { let `for`: String; let label: String }
    let accent: String; let title: String; let topNotes: [String]; let seller: Party; let meta: [KV]; let billTo: Party
    let columns: [Col]; let rows: [[String: String]]; let totals: [Total]; let amountInWords: String?; let home: String?
    let notes: String?; let terms: String?; let bottomNotes: [String]; let signature: Sign
}

let W: CGFloat = 595.28, H: CGFloat = 841.89, M: CGFloat = 34, top: CGFloat = 40, bottom: CGFloat = 45
let contentW = W - 2 * M
func widths(_ cols: [VM.Col]) -> [CGFloat] {
    let fixed: [String: CGFloat] = ["idx": 24, "code": 48, "qty": 30, "rate": 62, "taxable": 72, "taxRate": 40, "amount": 70]
    let used = cols.compactMap { fixed[$0.key] }.reduce(0, +)
    return cols.map { fixed[$0.key] ?? (contentW - used) }
}

func render(_ vm: VM, to url: URL) -> (pages: Int, ms: Int) {
    let t0 = Date()
    let accent = color(vm.accent), ws = widths(vm.columns), pad: CGFloat = 5
    let cellFont = font(8.5), headFont = font(8, "SemiBold")
    func rowCells(_ r: [String: String]) -> [NSAttributedString] {
        vm.columns.map { c in attr(r[c.key] ?? "", c.key == "idx" ? font(8.5) : cellFont, c.key == "idx" ? muted : ink, align: c.align == "right" ? .right : .left) }
    }
    func rowHeight(_ cells: [NSAttributedString]) -> CGFloat { zip(cells, ws).map { height($0, width: $1 - 2 * pad) }.max()! + 2 * pad }
    let headerCells = vm.columns.map { attr($0.label, headFont, color("#FFFFFF"), align: $0.align == "right" ? .right : .left) }
    let headerH = rowHeight(headerCells)
    let rows = vm.rows.map(rowCells), rowHs = rows.map(rowHeight)
    let docHeaderH: CGFloat = 186, summaryH: CGFloat = 250
    // Pass 1: paginate rows.
    var pages: [[Int]] = [[]]; var y = top + docHeaderH + headerH
    for (i, h) in rowHs.enumerated() {
        if y + h > H - bottom { pages.append([]); y = top + headerH }
        pages[pages.count - 1].append(i); y += h
    }
    let summaryOnNewPage = y + summaryH > H - bottom
    let pageCount = pages.count + (summaryOnNewPage ? 1 : 0)
    // Pass 2: draw.
    var box = CGRect(x: 0, y: 0, width: W, height: H)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    func footer(_ n: Int) { _ = draw(attr("Page \(n) of \(pageCount)", font(7.5), muted, align: .right), in: ctx, x: M, y: H - bottom + 18, width: contentW, pageH: H) }
    func tableHeader(at y: CGFloat) -> CGFloat {
        ctx.setFillColor(accent); ctx.fill(CGRect(x: M, y: H - y - headerH, width: contentW, height: headerH))
        var x = M; for (c, w) in zip(headerCells, ws) { _ = draw(c, in: ctx, x: x + pad, y: y + pad, width: w - 2 * pad, pageH: H); x += w }
        return y + headerH
    }
    for (p, idxs) in pages.enumerated() {
        ctx.beginPDFPage(nil)
        var y = top
        if p == 0 {
            ctx.setFillColor(accent); ctx.fill(CGRect(x: M, y: H - y - 5, width: contentW, height: 5)); y += 14
            var ly = y
            ly += draw(attr(vm.seller.name, font(13, "Bold")), in: ctx, x: M, y: ly, width: 260, pageH: H) + 2
            for l in vm.seller.lines { ly += draw(attr(l, font(9), muted), in: ctx, x: M, y: ly, width: 260, pageH: H) }
            for kv in vm.seller.ids { ly += draw(attr("\(kv.label)  \(kv.value)", font(9), muted), in: ctx, x: M, y: ly, width: 260, pageH: H) }
            var ry = y
            ry += draw(attr(vm.title, font(18, "Bold"), accent, align: .right), in: ctx, x: M, y: ry, width: contentW, pageH: H) + 4
            for kv in vm.meta { ry += draw(attr("\(kv.label)   \(kv.value)", font(9), ink, align: .right), in: ctx, x: M, y: ry, width: contentW, pageH: H) }
            y = max(ly, ry) + 12
            ctx.setFillColor(soft); ctx.fill(CGRect(x: M, y: H - y - 76, width: contentW, height: 76))
            var by = y + 8
            by += draw(attr("BILL TO", font(7.5, "SemiBold"), muted), in: ctx, x: M + 10, y: by, width: 300, pageH: H)
            by += draw(attr(vm.billTo.name, font(10, "SemiBold")), in: ctx, x: M + 10, y: by, width: 400, pageH: H)
            for l in vm.billTo.lines { by += draw(attr(l, font(9)), in: ctx, x: M + 10, y: by, width: 400, pageH: H) }
            for kv in vm.billTo.ids { by += draw(attr("\(kv.label)  \(kv.value)", font(9), muted), in: ctx, x: M + 10, y: by, width: 400, pageH: H) }
            y = top + docHeaderH
        }
        y = tableHeader(at: y)
        for i in idxs {
            var x = M
            for (c, w) in zip(rows[i], ws) { _ = draw(c, in: ctx, x: x + pad, y: y + pad, width: w - 2 * pad, pageH: H); x += w }
            y += rowHs[i]
            ctx.setStrokeColor(line); ctx.setLineWidth(0.75); ctx.move(to: CGPoint(x: M, y: H - y)); ctx.addLine(to: CGPoint(x: M + contentW, y: H - y)); ctx.strokePath()
        }
        if p == pages.count - 1 && !summaryOnNewPage { drawSummary(y + 10) }
        footer(p + 1); ctx.endPDFPage()
    }
    if summaryOnNewPage { ctx.beginPDFPage(nil); drawSummary(top); footer(pageCount); ctx.endPDFPage() }
    ctx.closePDF()
    func drawSummary(_ y0: CGFloat) {
        var y = y0, ty = y0
        if let w = vm.amountInWords {
            y += draw(attr("AMOUNT IN WORDS", font(7.5, "SemiBold"), muted), in: ctx, x: M, y: y, width: 280, pageH: H)
            y += draw(attr(w, font(9, "SemiBold")), in: ctx, x: M, y: y, width: 280, pageH: H)
        }
        if let h = vm.home { y += 6 + draw(attr(h, font(8.5), muted), in: ctx, x: M, y: y + 6, width: 280, pageH: H) }
        for t in vm.totals {
            let f = t.emphasis == true ? font(11, "Bold") : font(9)
            if t.emphasis == true { ctx.setStrokeColor(ink); ctx.setLineWidth(1.5); ctx.move(to: CGPoint(x: M + 320, y: H - ty - 2)); ctx.addLine(to: CGPoint(x: M + contentW, y: H - ty - 2)); ctx.strokePath(); ty += 4 }
            _ = draw(attr(t.label, f, t.emphasis == true ? ink : muted), in: ctx, x: M + 320, y: ty, width: 120, pageH: H)
            ty += draw(attr(t.value, f, ink, align: .right), in: ctx, x: M + 320, y: ty, width: contentW - 320, pageH: H) + 2
        }
        y = max(y, ty) + 24
        y += draw(attr(vm.signature.for, font(9), ink, align: .right), in: ctx, x: M, y: y, width: contentW, pageH: H) + 30
        y += draw(attr(vm.signature.label, font(9), muted, align: .right), in: ctx, x: M, y: y, width: contentW, pageH: H) + 12
        for n in [vm.notes, vm.terms].compactMap({ $0 }) { y += draw(attr(n, font(9)), in: ctx, x: M, y: y, width: contentW, pageH: H) + 6 }
        for n in vm.bottomNotes { y += draw(attr(n, font(9, "SemiBold"), ink, align: .center), in: ctx, x: M, y: y + 6, width: contentW, pageH: H) + 6 }
    }
    return (pageCount, Int(Date().timeIntervalSince(t0) * 1000))
}

let vmDir = root.appendingPathComponent("viewmodels")
for f in try! FileManager.default.contentsOfDirectory(at: vmDir, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    let vm = try! JSONDecoder().decode(VM.self, from: Data(contentsOf: f))
    let out = root.appendingPathComponent("out/\(f.deletingPathExtension().lastPathComponent).native.pdf")
    let r = render(vm, to: out)
    let kb = ((try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0) / 1024
    print("\(f.deletingPathExtension().lastPathComponent)\tpages \(r.pages)\t\(r.ms) ms\t\(kb) KB\tfonts: \(useNoto ? "Noto static" : "Inter variable")")
}
