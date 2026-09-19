// macOS WebKit harness for the PDF spike: same template + render.js as Chromium, paginated with NSPrintOperation
// (WebKit's print layout; the iOS path uses UIPrintPageRenderer + viewPrintFormatter over the same engine).
// Build & run:  swiftc -O main.swift -o webkit-render && ./webkit-render
import AppKit
import WebKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath + "/..")
let template = root.appendingPathComponent("template/template.html")
let vmDir = root.appendingPathComponent("viewmodels")
let outDir = root.appendingPathComponent("out")

@MainActor
final class Renderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let window: NSWindow
    var loaded: CheckedContinuation<Void, Never>?

    override init() {
        let a4 = NSRect(x: 0, y: 0, width: 595, height: 842)
        webView = WKWebView(frame: a4, configuration: WKWebViewConfiguration())
        window = NSWindow(contentRect: a4, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.contentView = webView
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded?.resume(); loaded = nil }

    func render(vmURL: URL) async throws -> (renderMs: Int, pdfMs: Int, url: URL) {
        let vm = try JSONSerialization.jsonObject(with: Data(contentsOf: vmURL))
        let t0 = Date()
        await withCheckedContinuation { c in loaded = c; webView.loadFileURL(template, allowingReadAccessTo: root) }
        _ = try await webView.callAsyncJavaScript("return await window.renderInvoice(vm)", arguments: ["vm": vm], contentWorld: .page)
        let t1 = Date()
        let out = outDir.appendingPathComponent(vmURL.deletingPathExtension().lastPathComponent + ".webkit.pdf")
        try? FileManager.default.removeItem(at: out)
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595.28, height: 841.89)
        info.topMargin = 40; info.bottomMargin = 45; info.leftMargin = 34; info.rightMargin = 34
        info.horizontalPagination = .fit; info.verticalPagination = .automatic
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = out
        let op = webView.printOperation(with: info)
        op.showsPrintPanel = false; op.showsProgressPanel = false
        op.view?.frame = webView.bounds
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        // runModal returns immediately; wait for the file to appear.
        var last = -1, stable = 0
        for _ in 0..<400 {
            let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? -1
            if size > 0 && size == last { stable += 1; if stable >= 3 { break } } else { stable = 0 }
            last = size
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        return (Int(t1.timeIntervalSince(t0) * 1000), Int(Date().timeIntervalSince(t1) * 1000), out)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    let r = Renderer()
    let files = try FileManager.default.contentsOfDirectory(at: vmDir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    var rows: [[String: Any]] = []
    for f in files {
        do {
            let res = try await r.render(vmURL: f)
            let pages = CGPDFDocument(res.url as CFURL)?.numberOfPages ?? -1
            let kb = ((try? FileManager.default.attributesOfItem(atPath: res.url.path)[.size] as? Int) ?? 0) / 1024
            print("\(f.deletingPathExtension().lastPathComponent)\trender \(res.renderMs) ms\tpdf \(res.pdfMs) ms\tpages \(pages)\t\(kb) KB")
            rows.append(["doc": f.deletingPathExtension().lastPathComponent, "renderMs": res.renderMs, "pdfMs": res.pdfMs, "pages": pages, "kb": kb])
        } catch { print("\(f.lastPathComponent)\tERROR \(error)") }
    }
    let json = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: outDir.appendingPathComponent("webkit-results.json"))
    exit(0)
}
app.run()
