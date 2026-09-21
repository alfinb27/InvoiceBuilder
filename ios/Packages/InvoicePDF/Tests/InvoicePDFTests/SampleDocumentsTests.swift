import Foundation
import InvoiceCore
import Testing
@testable import InvoicePDF

/// Writes one PDF per `pdf` fixture, for the CA and the accountant to check against the mandatory-field rules
/// (`make pdf-samples`). Off in a normal test run: it produces files rather than asserting anything.
@Suite("Sample documents")
struct SampleDocumentsTests {
    struct Case: Decodable {
        let id: String
        let explain: String
        let input: Input

        struct Input: Decodable {
            let template: TemplateID
            let document: Document
        }
    }

    struct File: Decodable {
        let cases: [Case]
    }

    /// The repo root, from this file's path: …/ios/Packages/InvoicePDF/Tests/InvoicePDFTests/<file>.
    static var repository: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url = url.deletingLastPathComponent() }
        return url
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PDF_SAMPLES_OUT"] != nil))
    func writeSamples() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PDF_SAMPLES_OUT"]!)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let configs = try TaxConfigStore.bundled()
        let labels = try PDFLabels.bundled()
        let reference = try ReferenceData.bundled()
        let templates = try PDFTemplateStore.bundled()
        let data = try Data(contentsOf: Self.repository.appending(path: "spec/fixtures/pdf/documents.json"))
        let file = try JSONDecoder().decode(File.self, from: data)

        var index = ["# Sample documents\n"]
        for testCase in file.cases {
            let document = testCase.input.document
            let config = try #require(configs.config(ref: document.taxConfigRef))
            let seller = try #require(document.sellerSnapshot)
            let computed = try TaxEngine.compute(EngineInput(
                document: document, seller: seller.engineSeller,
                buyer: document.buyerSnapshot?.engineBuyer ?? EngineBuyer(), config: config,
                currencies: reference.currencies
            ))
            let model = PDFModelBuilder.build(document: document, computed: computed, config: config, labels: labels,
                                              reference: reference)
            let template = try #require(templates.template(testCase.input.template))
            let request = PDFRenderRequest(model: model, template: template, paperSize: config.paperSize,
                                           accentHex: "#1F6FEB")
            let pdf = PDFRenderer.render(request)
            try pdf.write(to: out.appending(path: "\(testCase.id).pdf"))
            index.append("- **\(testCase.id)** (\(testCase.input.template.rawValue)): \(testCase.explain)")
        }
        try index.joined(separator: "\n").write(to: out.appending(path: "README.md"), atomically: true,
                                                encoding: .utf8)
    }
}
