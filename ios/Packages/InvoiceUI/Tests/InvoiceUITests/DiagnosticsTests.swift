import Foundation
import Testing
@testable import InvoiceUI

/// MetricKit reports kept on the device until the user shares them (ADR-0011).
@Suite("Diagnostics")
struct DiagnosticsTests {
    func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "diagnostics-\(UUID().uuidString.lowercased())")
    }

    /// Issue #34: a batch delivered at once used to keep only its last report.
    @Test func aBatchSavedAtOneInstantKeepsEveryReport() throws {
        let diagnostics = Diagnostics(folder: folder())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 1...3 { diagnostics.save(Data("crash \(index)".utf8), kind: "diagnostics", at: now) }
        let reports = diagnostics.reports()
        #expect(reports.count == 3)
        #expect(try String(contentsOf: reports[0], encoding: .utf8) == "crash 3") // newest first
    }

    @Test func onlyTheNewestTwentyAreKept() {
        let diagnostics = Diagnostics(folder: folder())
        for index in 0..<25 {
            diagnostics.save(Data("\(index)".utf8), kind: "metrics", at: Date(timeIntervalSince1970: Double(index)))
        }
        #expect(diagnostics.reports().count == Diagnostics.kept)
    }
}
