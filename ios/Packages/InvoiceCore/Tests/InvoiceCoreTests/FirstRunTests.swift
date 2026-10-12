import Foundation
import Testing
@testable import InvoiceCore

@Suite("Rate chips (documents.md §3.2)")
struct RateChipsTests {
    let chips = try! RateChips.bundled()

    @Test func indiaShowsTheFourCommonRatesAndTheRestUnderOtherRates() {
        let choices = chips.choices(config: TestConfigs.india, customRates: nil, on: TestConfigs.today)
        #expect(choices.chips.map(\.id) == ["gst_0", "gst_5", "gst_18", "gst_40"])
        #expect(choices.others.map(\.id) == ["gst_0_1", "gst_0_25", "gst_1_5", "gst_3", "gst_28", "exempt", "nil"])
        #expect(choices.hint?.hasPrefix("Most services are 18%") == true)
    }

    @Test func aChipRateNotYetInForceIsLeftOut() {
        // GST 40% starts on 2025-09-22; GST 12% ends on 2025-09-21.
        let choices = chips.choices(config: TestConfigs.india, customRates: nil, on: LocalDate(iso: "2025-09-21")!)
        #expect(choices.chips.map(\.id) == ["gst_0", "gst_5", "gst_18"])
        #expect(choices.others.contains { $0.id == "gst_12" })
    }

    @Test func theUKShowsStandardReducedAndZero() {
        let choices = chips.choices(config: TestConfigs.uk, customRates: nil, on: TestConfigs.today)
        #expect(choices.chips.map(\.id) == ["standard", "reduced", "zero"])
        #expect(choices.others.map(\.id) == ["exempt", "outsideScope"])
    }

    @Test func elsewhereTheBusinessesOwnRatesAreTheChips() {
        let rates = (1...5).map {
            CustomRateDraft(name: "Tax \($0)", percent: "\($0)").makeRate(id: "r\($0)", today: TestConfigs.today)
        }
        let choices = chips.choices(config: TestConfigs.generic, customRates: rates, on: TestConfigs.today)
        #expect(choices.chips.map(\.id) == ["r1", "r2", "r3", "r4"])
        #expect(choices.others.map(\.id) == ["r5"])
        #expect(choices.hint == nil)
    }
}

@Suite("One-off lines (documents.md §3.2)")
struct OneOffLineTests {
    let rules = DocumentSamples.rules()
    let gst18 = TestConfigs.india.rate("gst_18", customRates: nil)

    private func price(_ typed: Int64, includesTax: Bool, documentInclusive: Bool, chargesTax: Bool = true) -> Int64 {
        var document = rules.newDocument(docType: .invoice, id: "d1", today: TestConfigs.today, now: 1)
        document.pricesIncludeTax = documentInclusive
        return OneOffLine.unitPrice(typedMinor: typed, includesTax: includesTax, rate: gst18, document: document,
                                    chargesTax: chargesTax, currencies: rules.currencies, mode: .halfAwayFromZero)
    }

    @Test func aPriceOnTheDocumentsBasisIsKeptAsTyped() {
        #expect(price(250_000, includesTax: false, documentInclusive: false) == 250_000)
        #expect(price(250_000, includesTax: true, documentInclusive: true) == 250_000)
        #expect(price(250_000, includesTax: true, documentInclusive: false, chargesTax: false) == 250_000)
    }

    @Test func aPriceOnTheOtherBasisIsConvertedWithOneRounding() {
        // ₹2,500 including 18% → 2500 × 100 / 118 = 2118.644… → ₹2,118.64
        #expect(price(250_000, includesTax: true, documentInclusive: false) == 211_864)
        // ₹2,118.64 before tax → 2118.64 × 118 / 100 = 2499.9952 → ₹2,500.00
        #expect(price(211_864, includesTax: false, documentInclusive: true) == 250_000)
    }

    @Test func theSwitchSetsTheDocumentsBasisOnlyWithoutOtherLines() {
        var document = rules.newDocument(docType: .invoice, id: "d1", today: TestConfigs.today, now: 1)
        #expect(OneOffLine.setsDocumentBasis(document, editing: nil))
        document.lines = [DocumentSamples.line("l1", "Design", price: 100)]
        #expect(OneOffLine.setsDocumentBasis(document, editing: "l1"))
        #expect(!OneOffLine.setsDocumentBasis(document, editing: nil))
        document.lines.append(DocumentSamples.line("l2", "Logo", price: 100))
        #expect(!OneOffLine.setsDocumentBasis(document, editing: "l1"))
    }

    @Test func savingToMyItemsKeepsTheTypedPriceAndItsBasis() {
        let line = LineItem(id: "l1", description: "Logo refresh", productCode: "998391", quantity: "2",
                            unitPriceMinor: 211_864, rateId: "gst_18")
        let item = OneOffLine.catalogItem(for: line, typedMinor: 250_000, includesTax: true, chargesTax: true,
                                          businessID: "b-in", currency: .inr, id: "i1", now: 7)
        #expect(item.name == "Logo refresh" && item.kind == .service && item.unit == ItemKind.service.defaultUnit)
        #expect(item.unitPriceMinor == 250_000 && item.priceIncludesTax && item.rateId == "gst_18")
        #expect(item.productCode == "998391" && item.currency == .inr && item.createdAt == 7)
        let untaxed = OneOffLine.catalogItem(for: line, typedMinor: 250_000, includesTax: true, chargesTax: false,
                                             businessID: "b-in", currency: .inr, id: "i2", now: 7)
        #expect(!untaxed.priceIncludesTax)
    }
}

@Suite("First-run checklist (setup.md §3.2)")
struct FirstRunChecklistTests {
    private func summary(_ type: DocumentType, _ lifecycle: DocumentLifecycle) -> DocumentSummary {
        DocumentSummary(id: UUID().uuidString, docType: type, number: nil, lifecycle: lifecycle,
                        issueDate: TestConfigs.today, dueDate: nil, validUntil: nil, sentAt: nil, quoteOutcome: nil,
                        clientId: nil, buyerName: nil, currency: .inr, totalMinor: 0, lineCount: 1, updatedAt: 0)
    }

    @Test func aNewBusinessHasOneOfFourDone() {
        let checklist = FirstRunChecklist(clientCount: 0, itemCount: 0, documents: [])
        #expect(checklist.doneCount == 1 && checklist.isShown)
        #expect(checklist.isDone(.setUpBusiness) && !checklist.isDone(.addClient))
    }

    @Test func draftsAndQuotesDoNotCountAsSendingTheFirstInvoice() {
        let checklist = FirstRunChecklist(clientCount: 2, itemCount: 1,
                                          documents: [summary(.invoice, .draft), summary(.quote, .issued)])
        #expect(checklist.doneCount == 3 && checklist.isShown)
    }

    @Test func anIssuedOrVoidInvoiceEndsTheChecklist() {
        #expect(!FirstRunChecklist(clientCount: 0, itemCount: 0, documents: [summary(.invoice, .issued)]).isShown)
        let voided = FirstRunChecklist(clientCount: 0, itemCount: 0, documents: [summary(.invoice, .void)])
        #expect(!voided.isShown && voided.isDone(.sendInvoice))
    }
}
