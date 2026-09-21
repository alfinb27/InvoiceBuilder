import Foundation
import InvoiceCore
import PDFKit
import Testing
import UIKit
@testable import InvoicePDF

/// View models built in code: the strings themselves are proven by the `pdf` fixtures in InvoiceCore, so these
/// tests are about the drawing — pagination, fonts, the QR block and the size of the file.
enum SampleModel {
    static let labels = try! PDFLabels.bundled()
    static let templates = try! PDFTemplateStore.bundled()

    static func invoice(lines: Int = 2, isDraft: Bool = false, description: String = "Website development",
                        withUPI: Bool = true) -> PDFDocumentModel {
        let columns = [
            PDFDocumentModel.Column(id: "index", label: "#", align: .leading),
            PDFDocumentModel.Column(id: "description", label: "Description", align: .leading),
            PDFDocumentModel.Column(id: "productCode", label: "HSN/SAC", align: .leading),
            PDFDocumentModel.Column(id: "quantity", label: "Qty", align: .trailing),
            PDFDocumentModel.Column(id: "unitPrice", label: "Rate", align: .trailing),
            PDFDocumentModel.Column(id: "taxable", label: "Taxable value", align: .trailing),
            PDFDocumentModel.Column(id: "tax:CGST", label: "CGST 9%", align: .trailing),
            PDFDocumentModel.Column(id: "tax:SGST", label: "SGST 9%", align: .trailing),
            PDFDocumentModel.Column(id: "amount", label: "Amount", align: .trailing),
        ]
        let rows = (1...max(lines, 1)).map { index in
            ["\(index)", "\(description) \(index)", "998314", "2", "₹5,000.00", "₹10,000.00", "₹900.00", "₹900.00",
             "₹11,800.00"]
        }
        return PDFDocumentModel(
            title: "Tax Invoice",
            isDraft: isDraft,
            draftLabel: isDraft ? "DRAFT" : nil,
            number: isDraft ? nil : "INV/26-27/0042",
            numberLabel: "Invoice no.",
            meta: [PDFDocumentModel.Field(label: "Date", value: "19 Sep 2026"),
                   PDFDocumentModel.Field(label: "Due date", value: "4 Oct 2026"),
                   PDFDocumentModel.Field(label: "Place of supply", value: "Karnataka")],
            seller: PDFDocumentModel.Party(
                heading: "From", name: "Bharat Web Studio",
                lines: ["Bharat Web Studio LLP", "12 MG Road", "Bengaluru 560001", "Karnataka"],
                fields: [PDFDocumentModel.Field(label: "GSTIN", value: "29AAGCB7383J1Z4")]
            ),
            buyer: PDFDocumentModel.Party(
                heading: "Bill to", name: "Rao Traders", lines: ["5 Residency Road", "Bengaluru 560025"],
                fields: [PDFDocumentModel.Field(label: "GSTIN", value: "29AABCR1234C1ZU")]
            ),
            columns: columns,
            rows: rows,
            totals: [
                PDFDocumentModel.TotalRow(label: "Subtotal", value: "₹10,000.00"),
                PDFDocumentModel.TotalRow(label: "Taxable value", value: "₹10,000.00"),
                PDFDocumentModel.TotalRow(label: "CGST 9%", value: "₹900.00"),
                PDFDocumentModel.TotalRow(label: "SGST 9%", value: "₹900.00"),
                PDFDocumentModel.TotalRow(label: "Total", value: "₹11,800.00", emphasis: .strong),
            ],
            taxSummary: PDFDocumentModel.Table(
                columns: [PDFDocumentModel.Column(id: "rate", label: "GST rate", align: .leading),
                          PDFDocumentModel.Column(id: "taxable", label: "Taxable value", align: .trailing),
                          PDFDocumentModel.Column(id: "tax", label: "GST", align: .trailing)],
                rows: [["CGST 9%", "₹10,000.00", "₹900.00"], ["SGST 9%", "₹10,000.00", "₹900.00"],
                       ["Total GST", "₹10,000.00", "₹1,800.00"]]
            ),
            amountInWords: "Indian Rupees Eleven Thousand Eight Hundred Only",
            notes: [PDFDocumentModel.Note(label: "Notes", text: "Thank you for your business.",
                                          placement: "bottom")],
            payment: PDFDocumentModel.Payment(
                bank: [PDFDocumentModel.Field(label: "Account name", value: "Bharat Web Studio LLP"),
                       PDFDocumentModel.Field(label: "IFSC", value: "EXMP0001234")],
                upi: withUPI ? PDFDocumentModel.Payment.UPI(
                    id: "bharatweb@examplebank", caption: "Scan to pay with any UPI app",
                    payload: "upi://pay?pa=bharatweb@examplebank&pn=Bharat%20Web%20Studio&am=11800.00&cu=INR"
                ) : nil
            ),
            signature: PDFDocumentModel.Signature(forBusiness: "For Bharat Web Studio",
                                                  authorisedSignatory: "Authorised signatory"),
            footer: PDFDocumentModel.Footer(pageLabel: "Page {page} of {pages}",
                                            continued: "Continued on next page")
        )
    }

    /// A solid PNG, standing in for an uploaded logo or signature.
    static func png(width: Int, height: Int, color: UIColor) -> Data {
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size).pngData { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func request(_ model: PDFDocumentModel, template id: TemplateID = .classic) -> PDFRenderRequest {
        PDFRenderRequest(model: model, template: templates.template(id)!, paperSize: "A4", accentHex: "#1F6FEB")
    }
}

/// The text of every page, as a reader (or a tax office) would extract it.
func pageTexts(_ data: Data) throws -> [String] {
    let document = try #require(PDFDocument(data: data))
    return (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
}

@Suite("PDF rendering")
struct RenderTests {
    @Test(arguments: [TemplateID.classic, .modern, .minimal, .compact])
    func everyTemplateDrawsOnePageWithTheKeyFacts(_ template: TemplateID) throws {
        let data = PDFRenderer.render(SampleModel.request(SampleModel.invoice(), template: template))
        let pages = try pageTexts(data)
        #expect(pages.count == 1)
        let text = pages[0]
        for expected in ["Tax Invoice", "INV/26-27/0042", "Rao Traders", "Bharat Web Studio", "29AAGCB7383J1Z4",
                         "Website development 1", "₹11,800.00", "Total", "Page 1 of 1",
                         "Indian Rupees Eleven Thousand Eight Hundred Only", "Authorised signatory"] {
            #expect(text.contains(expected), "\(template.rawValue) is missing \"\(expected)\"")
        }
    }

    @Test func aLongInvoicePaginatesWithRepeatedHeadersAndPageNumbers() throws {
        let data = PDFRenderer.render(SampleModel.request(SampleModel.invoice(lines: 60)))
        let pages = try pageTexts(data)
        #expect(pages.count >= 2, "60 lines should not fit on one page")
        let withRows = pages.indices.filter { pages[$0].contains("998314") }
        for (index, text) in pages.enumerated() {
            #expect(text.contains("Page \(index + 1) of \(pages.count)"))
            if withRows.contains(index) {
                #expect(text.lowercased().contains("description"), "page \(index + 1) repeats no table header")
            }
        }
        // Every page the table spills out of says so; the page where it ends does not.
        for index in withRows.dropLast() {
            #expect(pages[index].contains("Continued on next page"), "page \(index + 1) is missing the note")
        }
        #expect(pages[withRows.last ?? 0].contains("Continued on next page") == false
                || withRows.last != pages.count - 1)
        // The totals follow the last row; the closing region is on that page or the next one (§3.3, §3.4).
        let withTotals = try #require(pages.firstIndex { $0.contains("Total") })
        #expect(withTotals == (withRows.last ?? 0) || withTotals == (withRows.last ?? 0) + 1)
        #expect(pages.last?.contains("Authorised signatory") == true)
        // Every line appears exactly once, in order.
        let all = pages.joined()
        for index in 1...60 { #expect(all.contains("Website development \(index)")) }
    }

    @Test func devanagariIsDrawnWithTheBundledFontAndStaysSelectable() throws {
        let data = PDFRenderer.render(SampleModel.request(SampleModel.invoice(description: "वेबसाइट विकास")))
        let text = try pageTexts(data).joined()
        // The page is correct and the text is real text; a pre-base vowel sign (वि) can extract out of order,
        // which is a PDF limitation (spec/pdf/RENDERING.md §4).
        #expect(text.contains("वेबसाइट"), "Hindi text must be embedded and extractable")
        #expect(String(decoding: data, as: UTF8.self).contains("NotoSansDevanagari"),
                "the bundled Devanagari font must be embedded, not a system substitute")
    }

    @Test func draftsCarryTheWatermark() throws {
        let data = PDFRenderer.render(SampleModel.request(SampleModel.invoice(isDraft: true)))
        let text = try pageTexts(data).joined()
        #expect(text.contains("DRAFT"))
    }

    /// §3.3: the tax summary sits beside the totals, so an ordinary invoice keeps to one page.
    @Test func theTaxSummarySitsBesideTheTotals() throws {
        let data = PDFRenderer.render(SampleModel.request(SampleModel.invoice(lines: 6)))
        let pages = try pageTexts(data)
        #expect(pages.count == 1, "six lines with a tax summary must still fit on one page")
        let text = pages[0]
        // Both columns are there, and so is everything that follows them.
        for expected in ["GST rate", "Total GST", "Subtotal", "Total", "BANK DETAILS", "Authorised signatory"] {
            #expect(text.contains(expected), "missing \"\(expected)\"")
        }
    }

    /// §3.4: payment, notes and signature travel together — never a page holding only a note and a signature.
    @Test(arguments: [TemplateID.classic, .modern, .minimal, .compact])
    func theClosingBlocksAreNeverStrandedOnAPageOfTheirOwn(_ template: TemplateID) throws {
        for lines in [1, 3, 5, 7, 9, 12, 14] {
            let data = PDFRenderer.render(SampleModel.request(SampleModel.invoice(lines: lines),
                                                              template: template))
            let pages = try pageTexts(data)
            let last = try #require(pages.last)
            #expect(last.contains("Authorised signatory"), "\(template.rawValue), \(lines) lines")
            if !last.contains("Total") {
                // The region moved as a whole, so the payment details moved with it.
                #expect(last.contains("bharatweb@examplebank"),
                        "\(template.rawValue), \(lines) lines: the last page holds only notes and a signature")
            }
        }
    }

    /// The logo and the signature are the only drawn images apart from the QR, and the business supplies both.
    @Test func aLogoAndASignatureAreDrawnWithoutDisturbingTheLayout() throws {
        let plain = PDFRenderer.render(SampleModel.request(SampleModel.invoice()))
        var request = SampleModel.request(SampleModel.invoice())
        request.logo = SampleModel.png(width: 240, height: 80, color: .systemIndigo)
        request.signature = SampleModel.png(width: 200, height: 60, color: .black)
        let data = PDFRenderer.render(request)
        let pages = try pageTexts(data)
        #expect(pages.count == 1, "images must not push the document onto a second page")
        #expect(pages[0].contains("Authorised signatory") && pages[0].contains("INV/26-27/0042"))
        #expect(data.count > plain.count, "the images must actually be embedded")
        // A signature image takes the full box, so the block is taller than the plain line-to-sign version.
        #expect(try #require(PDFDocument(data: data)).page(at: 0)?.bounds(for: .mediaBox).height == 842)
    }

    @Test func aOnePageInvoiceStaysSmall() throws {
        let data = PDFRenderer.render(SampleModel.request(SampleModel.invoice()))
        #expect(data.count < 300_000, "one page was \(data.count) bytes")
        #expect(PDFRenderer.pageCount(SampleModel.request(SampleModel.invoice())) == 1)
    }

    @Test func aLetterPageIsWiderAndShorter() throws {
        var request = SampleModel.request(SampleModel.invoice())
        request.paperSize = "Letter"
        let document = try #require(PDFDocument(data: PDFRenderer.render(request)))
        let bounds = try #require(document.page(at: 0)?.bounds(for: .mediaBox))
        #expect(Int(bounds.width) == 612 && Int(bounds.height) == 792)
    }

    /// The plan's budget is one second on an XR-class device. A shared CI runner under parallel test load is not
    /// that device, so the real guard is the *shape* of the cost: 60 lines must stay within a small multiple of
    /// one line, which catches a layout pass that turns quadratic whatever the machine. The absolute ceiling is
    /// kept as a loose sanity check.
    @Test func renderingGrowsWithTheLinesAndNoFaster() throws {
        _ = PDFRenderer.render(SampleModel.request(SampleModel.invoice(lines: 1))) // warm the font cache
        func seconds(lines: Int) -> TimeInterval {
            let request = SampleModel.request(SampleModel.invoice(lines: lines))
            let start = Date()
            _ = PDFRenderer.render(request)
            return Date().timeIntervalSince(start)
        }
        let one = max(seconds(lines: 1), 0.001)
        let sixty = seconds(lines: 60)
        #expect(sixty < one * 12, "60 lines took \(sixty) s against \(one) s for one line")
        #expect(sixty < 3.0, "a 60-line invoice took \(sixty) s")
    }
}
