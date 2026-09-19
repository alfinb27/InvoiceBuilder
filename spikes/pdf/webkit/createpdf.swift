// Isolation test: WebKit createPDF (non-print path) for the Devanagari view model.
import AppKit
import WebKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
@MainActor final class R: NSObject, WKNavigationDelegate {
    let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
    var done: CheckedContinuation<Void, Never>?
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { done?.resume(); done = nil }
}
let app = NSApplication.shared
Task { @MainActor in
    let r = R(); r.wv.navigationDelegate = r
    await withCheckedContinuation { c in r.done = c; r.wv.loadFileURL(root.appendingPathComponent("template/template.html"), allowingReadAccessTo: root) }
    let vm = try! JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("viewmodels/vm-04-in-devanagari.json")))
    _ = try! await r.wv.callAsyncJavaScript("return await window.renderInvoice(vm)", arguments: ["vm": vm], contentWorld: .page)
    let data = try! await r.wv.pdf(configuration: WKPDFConfiguration())
    try! data.write(to: root.appendingPathComponent("out/vm-04-in-devanagari.webkit-createpdf.pdf"))
    let img = try! await r.wv.takeSnapshot(configuration: nil)
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("out/vm-04-webkit-snapshot.png"))
    exit(0)
}
app.run()
