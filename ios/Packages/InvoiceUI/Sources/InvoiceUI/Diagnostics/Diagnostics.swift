import Foundation
import MetricKit

/// First-party diagnostics (ADR-0011): MetricKit's daily metric and diagnostic (crash, hang, disk-write) payloads,
/// kept as JSON files on this device — newest 20 — until the user chooses to share them from Settings → About.
/// Nothing leaves the device on its own.
public final class Diagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    // @unchecked: `folder` is immutable; file writes go through FileManager, which is thread-safe.
    public static let shared = Diagnostics(folder: Diagnostics.defaultFolder)
    static let kept = 20

    let folder: URL

    init(folder: URL) {
        self.folder = folder
    }

    static var defaultFolder: URL {
        (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                                      create: true).appending(path: "InvoiceBuilder/Diagnostics"))
            ?? FileManager.default.temporaryDirectory.appending(path: "Diagnostics")
    }

    /// Subscribes to MetricKit (the live app only; tests never call it).
    public func start() {
        MXMetricManager.shared.add(self)
    }

    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { save(payload.jsonRepresentation(), kind: "metrics") }
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads { save(payload.jsonRepresentation(), kind: "diagnostics") }
    }

    func save(_ data: Data, kind: String, at date: Date = Date()) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(kind)-\(Int64(date.timeIntervalSince1970 * 1000)).json"
        try? data.write(to: folder.appending(path: name), options: [.atomic, .completeFileProtection])
        for stale in reports().dropFirst(Self.kept) { try? FileManager.default.removeItem(at: stale) }
    }

    /// Newest first.
    public func reports() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .sorted { stamp($0) > stamp($1) }
    }

    private func stamp(_ url: URL) -> Int64 {
        Int64(url.deletingPathExtension().lastPathComponent.split(separator: "-").last ?? "") ?? 0
    }
}
