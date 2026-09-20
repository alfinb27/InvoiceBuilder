import Foundation
import Testing
@testable import InvoiceCore

/// Sample businesses and clients for document tests.
enum DocumentSamples {
    static let india = Business(
        id: "b-in", name: "Bharat Web Studio", legalName: "Bharat Web Studio LLP",
        address: Address(line1: "12 MG Road", city: "Bengaluru", regionCode: "29", postalCode: "560001",
                         countryCode: "IN"),
        countryCode: "IN", taxConfig: "IN", taxRegistration: "regular", taxId: "29AAGCB7383J1Z4",
        homeCurrency: .inr, upiVpa: "bharatweb@examplebank", paymentTermsDays: 15, defaultNotes: "Thank you!",
        logoAssetId: "logo-1"
    )
    static let uk = Business(
        id: "b-gb", name: "Leeds Joinery", address: Address(line1: "10 High Street", city: "Leeds",
                                                              postalCode: "LS1 1AA", countryCode: "GB"),
        countryCode: "GB", taxConfig: "GB", taxRegistration: "vatRegistered", taxId: "GB980780684",
        homeCurrency: .gbp, paymentTermsDays: 30
    )
    static let raoTraders = Client(
        id: "c-rao", businessId: "b-in", name: "Rao Traders",
        billingAddress: Address(line1: "5 Residency Road", city: "Bengaluru", regionCode: "29", postalCode: "560025",
                                countryCode: "IN"),
        countryCode: "IN", regionCode: "29", taxId: "29AABCR1234C1ZU", isBusiness: true
    )
    static let acme = Client(id: "c-acme", businessId: "b-in", name: "Acme Inc.", countryCode: "US", isBusiness: true,
                             defaultCurrency: "USD")

    static func rules(_ business: Business = india) -> DocumentRules {
        try! DocumentRules(configs: TestConfigs.store, business: business,
                           currencies: TestConfigs.reference.currencies)
    }

    static func line(_ id: String, _ description: String, quantity: String = "1", price: Int64,
                     rate: String = "gst_18", code: String? = "998314") -> LineItem {
        LineItem(id: id, description: description, productCode: code, quantity: quantity, unitPriceMinor: price,
                 rateId: rate)
    }
}

@Suite("Document rules (documents.md)")
struct DocumentRulesTests {
    let rules = DocumentSamples.rules()
    let today = TestConfigs.today

    @Test func clientChangesMoveCurrencySupplyTypeAndPlaceOfSupply() {
        var document = rules.newDocument(docType: .invoice, id: "d1", today: today, now: 5)
        document.placeOfSupply = "27"
        document.exchangeRate = "1"
        rules.setClient(DocumentSamples.acme, on: &document)
        #expect(document.clientId == "c-acme")
        #expect(document.currency == "USD" && document.exchangeRate == nil && document.roundOff == false)
        #expect(document.supplyType == "exportWithTax") // no LUT reference
        #expect(document.placeOfSupply == nil)

        document.exchangeRate = "83.25"
        rules.setCurrency("EUR", on: &document)
        #expect(document.exchangeRate == nil && document.roundOff == false)
        rules.setCurrency(.inr, on: &document)
        #expect(document.roundOff == nil)

        rules.setClient(nil, on: &document)
        #expect(document.clientId == nil && document.currency == .inr && document.supplyType == "domestic")
    }

    @Test func issueDateMovesTheDueDateAndTypeChangeSwapsDates() {
        var document = rules.newDocument(docType: .invoice, id: "d1", today: today, now: 0)
        #expect(document.dueDate == LocalDate(iso: "2026-10-04"))
        rules.setIssueDate(LocalDate(iso: "2026-09-29")!, on: &document)
        #expect(document.dueDate == LocalDate(iso: "2026-10-14"))
        rules.setDocType(.quote, on: &document)
        #expect(document.dueDate == nil && document.validUntil == LocalDate(iso: "2026-10-29"))
        rules.setIssueDate(LocalDate(iso: "2026-09-19")!, on: &document)
        #expect(document.validUntil == LocalDate(iso: "2026-10-19"))
        rules.setDocType(.invoice, on: &document)
        #expect(document.validUntil == nil && document.dueDate == LocalDate(iso: "2026-10-04"))
    }

    @Test func catalogueLinesAndOneOffRates() {
        var document = rules.newDocument(docType: .invoice, id: "d1", today: today, now: 0)
        #expect(rules.oneOffRateID(for: document).isEmpty) // a GST-charging seller picks the first rate
        let item = CatalogItem(id: "i1", businessId: "b-in", name: "Website", unit: "OTH", unitPriceMinor: 11800,
                               currency: .inr, rateId: "gst_18", productCode: "998314", priceIncludesTax: true)
        let (line, needsPrice) = rules.line(from: item, for: document, id: "l1")
        #expect(!needsPrice)
        #expect(line.unitPriceMinor == 10000 && line.description == "Website" && line.catalogItemId == "i1")
        #expect(line.quantity == "1" && line.unit == "OTH" && line.rateId == "gst_18")
        document.lines = [line]
        #expect(rules.oneOffRateID(for: document) == "gst_18")

        rules.setClient(DocumentSamples.acme, on: &document) // USD without an exchange rate
        #expect(rules.line(from: item, for: document, id: "l2").needsPrice)

        var composition = DocumentSamples.india
        composition.taxRegistration = "composition"
        let compositionRules = DocumentSamples.rules(composition)
        let empty = compositionRules.newDocument(docType: .invoice, id: "d2", today: today, now: 0)
        #expect(compositionRules.oneOffRateID(for: empty) == "gst_0")
    }

    @Test func rateChoicesKeepALineRateNoLongerInForce() {
        let document = rules.newDocument(docType: .invoice, id: "d1", today: today, now: 0)
        let ids = rules.rateChoices(for: document, selected: "gst_12").map(\.id)
        #expect(!ids.dropLast().contains("gst_12") && ids.last == "gst_12")
        #expect(rules.rateChoices(for: document, selected: nil).contains { $0.id == "gst_40" })
    }

    @Test func snapshotsCarryEngineAndDisplayFields() {
        let config = rules.config(on: today)
        let seller = rules.sellerSnapshot(config: config)
        #expect(seller.region == "29" && seller.address == "12 MG Road, Bengaluru 560001")
        #expect(seller.name == "Bharat Web Studio" && seller.logoAssetId == "logo-1" && seller.bank == nil)
        let buyer = rules.buyerSnapshot(client: DocumentSamples.raoTraders)
        #expect(buyer.engineBuyer == EngineBuyer(name: "Rao Traders", address: "5 Residency Road, Bengaluru 560025",
                                                 country: "IN", region: "29", taxId: "29AABCR1234C1ZU",
                                                 isBusiness: true))

        var document = rules.newDocument(docType: .invoice, id: "d1", today: today,
                                         client: DocumentSamples.raoTraders, now: 0)
        document.buyerSnapshot = buyer
        // The client was deleted: the draft keeps its last buyer snapshot.
        #expect(rules.buyerSnapshot(for: document, client: nil) == buyer)
        document.clientId = nil
        #expect(rules.buyerSnapshot(for: document, client: nil) == nil)
    }

    @Test func preparedDraftStoresTotalsButNoComputedResult() {
        var document = rules.newDocument(docType: .invoice, id: "d1", today: today,
                                         client: DocumentSamples.raoTraders, now: 0)
        document.lines = [DocumentSamples.line("l1", "Website", quantity: "2", price: 500000)]
        document.lines[0].position = 7
        let saved = rules.preparedDraft(document, client: DocumentSamples.raoTraders)
        #expect(saved.totals.totalMinor == 1_180_000 && saved.totals.taxMinor == 180_000)
        #expect(saved.computed == nil && saved.lines[0].position == 0)
        #expect(saved.sellerSnapshot?.taxId == "29AAGCB7383J1Z4" && saved.buyerSnapshot?.name == "Rao Traders")
        #expect(saved.taxConfigRef == "IN@2025-09-22")

        document.lines[0].rateId = "gst_99"
        #expect(rules.preparedDraft(document, client: DocumentSamples.raoTraders).totals == .zero)
    }

    @Test func issueProblems() {
        var document = rules.newDocument(docType: .invoice, id: "d1", today: today, now: 0)
        let seller = rules.sellerSnapshot(config: rules.config(for: document))
        #expect(rules.issueProblems(document, result: rules.compute(document, seller: seller, buyer: nil))
            == [.noLines])

        document.lines = [DocumentSamples.line("l1", " ", price: 100), DocumentSamples.line("l2", "Fee", price: 100, rate: "")]
        let problems = rules.issueProblems(document, result: rules.compute(document, seller: seller, buyer: nil))
        #expect(problems == [.lineDescriptionMissing([0]), .lineRateMissing([1])]) // unknown_rate is not repeated

        var uk = DocumentSamples.rules(DocumentSamples.uk).newDocument(docType: .invoice, id: "d2", today: today, now: 0)
        uk.currency = "EUR" // foreign currency without an exchange rate: an error-severity issue
        uk.lines = [DocumentSamples.line("l1", "Joinery", price: 10000, rate: "standard", code: nil)]
        let ukRules = DocumentSamples.rules(DocumentSamples.uk)
        let ukSeller = ukRules.sellerSnapshot(config: ukRules.config(for: uk))
        let ukProblems = ukRules.issueProblems(uk, result: ukRules.compute(uk, seller: ukSeller, buyer: nil))
        #expect(ukProblems.contains(.blockingIssue(EngineIssue(code: "exchange_rate_missing", severity: .error))))
    }

    @Test func issuedDocumentFreezesResults() throws {
        var document = rules.newDocument(docType: .invoice, id: "d1", today: today,
                                         client: DocumentSamples.raoTraders, now: 0)
        document.lines = [DocumentSamples.line("l1", "Website", quantity: "2", price: 500000)]
        let config = rules.config(for: document)
        let seller = rules.sellerSnapshot(config: config)
        let buyer = rules.buyerSnapshot(client: DocumentSamples.raoTraders)
        let computed = try rules.compute(document, seller: seller, buyer: buyer).get()
        let series = NumberingSeries(id: "s1", businessId: "b-in", docType: .invoice, label: "Invoices",
                                     pattern: "INV/{fy}/{seq:4}", reset: .fiscalYear, ownerDeviceId: "dev",
                                     counters: ["FY2026": 42])
        let allocation = try NumberAllocator.allocate(from: series, issueDate: today, config: config).get()
        let issued = rules.issued(document, seller: seller, buyer: buyer, computed: computed, allocation: allocation)
        #expect(issued.lifecycle == .issued && issued.number == "INV/26-27/0042" && issued.sequence == 42)
        #expect(issued.seriesId == "s1" && issued.periodKey == "FY2026" && issued.revision == 1)
        #expect(issued.computed == computed && issued.totals.totalMinor == 1_180_000)
        #expect(issued.lines[0].rateSnapshot == RateSnapshot(percent: "18", category: .standard, label: "GST 18%"))
        #expect(issued.lines[0].taxMinor == 180_000 && issued.lines[0].totalMinor == 1_180_000)
        #expect(allocation.series.counters == ["FY2026": 43])
    }

    @Test func duplicateAndConvert() {
        var quote = rules.newDocument(docType: .quote, id: "q1", today: LocalDate(iso: "2026-08-01")!,
                                      client: DocumentSamples.raoTraders, now: 0)
        quote.lines = [DocumentSamples.line("l1", "Website", price: 500000)]
        quote.lines[0].amountMinor = 500000
        quote.lifecycle = .issued
        quote.number = "QT-0007"
        quote.discount = .percent("5")
        var ids = 0
        let next = { () -> String in ids += 1; return "n\(ids)" }
        let copy = rules.duplicate(quote, id: "q2", today: today, now: 9, newLineID: next)
        #expect(copy.lifecycle == .draft && copy.number == nil && copy.docType == .quote)
        #expect(copy.issueDate == today && copy.validUntil == LocalDate(iso: "2026-10-19"))
        #expect(copy.lines.map(\.id) == ["n1"] && copy.lines[0].amountMinor == nil && copy.discount == .percent("5"))

        #expect(rules.canConvert(quote))
        let invoice = rules.convertedInvoice(from: quote, id: "i1", today: today, now: 9, newLineID: next)
        #expect(invoice.docType == .invoice && invoice.convertedFromId == "q1")
        #expect(invoice.dueDate == LocalDate(iso: "2026-10-04") && invoice.validUntil == nil)
        quote.quoteOutcome = .converted
        #expect(!rules.canConvert(quote))
    }
}

@Suite("Number allocation (documents.md §6)")
struct NumberAllocatorTests {
    let series = [
        NumberingSeries(id: "b", createdAt: 5, businessId: "x", docType: .invoice, label: "Later", pattern: "B{seq:3}",
                        reset: .never, ownerDeviceId: "me"),
        NumberingSeries(id: "a", createdAt: 1, businessId: "x", docType: .invoice, label: "Other device",
                        pattern: "A{seq:3}", reset: .never, ownerDeviceId: "other"),
        NumberingSeries(id: "c", createdAt: 1, businessId: "x", docType: .invoice, label: "Mine",
                        pattern: "INV-{seq:4}", reset: .never, ownerDeviceId: "me"),
        NumberingSeries(id: "q", createdAt: 0, businessId: "x", docType: .quote, label: "Quotes",
                        pattern: "QT-{seq:4}", reset: .never, ownerDeviceId: "me"),
    ]

    @Test func picksTheEarliestSeriesThisDeviceOwns() {
        #expect(NumberAllocator.series(for: .invoice, deviceID: "me", among: series)?.id == "c")
        #expect(NumberAllocator.series(for: .quote, deviceID: "me", among: series)?.id == "q")
        #expect(NumberAllocator.series(for: .invoice, deviceID: "new-device", among: series) == nil)
    }

    @Test func advancesThePeriodCounter() throws {
        let config = TestConfigs.india
        var first = try NumberAllocator.allocate(from: series[2], issueDate: TestConfigs.today, config: config).get()
        #expect(first.number == "INV-0001" && first.periodKey == "all" && first.sequence == 1)
        first = try NumberAllocator.allocate(from: first.series, issueDate: TestConfigs.today, config: config).get()
        #expect(first.number == "INV-0002" && first.series.counters == ["all": 3])
    }

    @Test func reportsNumbersTheConfigRejects() {
        var long = series[2]
        long.pattern = "INVOICE-NUMBER-{seq:6}"
        #expect(NumberAllocator.allocate(from: long, issueDate: TestConfigs.today, config: TestConfigs.india)
            == .failure(.numberTooLong))
    }
}

@Suite("Line editor and typed document fields (documents.md §3)")
struct LineItemRulesTests {
    let rules = LineItemRules(config: TestConfigs.india, chargesTax: true, exponent: 2)

    @Test func reportsMissingAndMalformedFields() {
        var draft = LineItemDraft()
        draft.quantityText = ""
        #expect(rules.issues(draft) == [.description: .required, .quantity: .required, .price: .required,
                                        .rate: .required])
        draft.description = "Consulting"
        draft.quantityText = "1.5.2"
        draft.priceText = "12.345"
        draft.rateId = "gst_18"
        draft.productCode = "99A"
        #expect(rules.issues(draft) == [.quantity: .invalidNumber(.invalid), .price: .invalidNumber(.tooManyDecimals),
                                        .productCode: .invalid(.hsnSac, .format)])
        // A seller that does not charge tax never has to pick a rate.
        let noTax = LineItemRules(config: TestConfigs.india, chargesTax: false, exponent: 2)
        draft.rateId = ""
        #expect(noTax.issues(draft)[.rate] == nil)
    }

    @Test func discountsStayWithinTheLine() {
        var draft = LineItemDraft()
        draft.description = "Consulting"
        draft.priceText = "100"
        draft.rateId = "gst_18"
        draft.discountText = "120"
        #expect(rules.issues(draft)[.discount] == .outOfRange(0...100))
        draft.discountIsPercent = false
        draft.discountText = "100.01"
        #expect(rules.issues(draft)[.discount] == .exceedsLineAmount)
        draft.discountText = "100"
        #expect(rules.issues(draft).isEmpty)
    }

    @Test func appliesNormalisedValuesAndRoundTrips() {
        var draft = LineItemDraft()
        draft.description = "  Tea leaves "
        draft.quantityText = "01.50"
        draft.priceText = "1,250.5"
        draft.discountText = "10"
        draft.rateId = "gst_5"
        draft.productCode = " 0902 "
        draft.unit = "KGS"
        var line = LineItem(id: "l1")
        rules.apply(draft, to: &line)
        #expect(line.description == "Tea leaves" && line.quantity == "1.5" && line.unitPriceMinor == 125_050)
        #expect(line.discount == .percent("10") && line.rateId == "gst_5" && line.productCode == "0902")
        #expect(line.unit == "KGS")

        let reopened = LineItemDraft(line: line, exponent: 2)
        #expect(reopened.quantityText == "1.5" && reopened.priceText == "1250.50" && reopened.discountText == "10")
        line.discount = .amount(2_500)
        #expect(LineItemDraft(line: line, exponent: 2).discountText == "25.00")
        #expect(!LineItemDraft(line: line, exponent: 2).discountIsPercent)
    }

    @Test func documentFields() {
        #expect(DocumentInput.shipping("", exponent: 2) == .success(0))
        #expect(DocumentInput.shipping("49.5", exponent: 2) == .success(4_950))
        #expect(DocumentInput.shipping("-1", exponent: 2) == .failure(.invalidNumber(.invalid)))
        #expect(DocumentInput.exchangeRate(" ") == .success(nil))
        #expect(DocumentInput.exchangeRate("83.250") == .success("83.25"))
        #expect(DocumentInput.exchangeRate("0") == .failure(.invalidNumber(.invalid)))
        #expect(DocumentInput.discount("0", isPercent: true, exponent: 2) == .success(nil))
        #expect(DocumentInput.discount("250", isPercent: false, exponent: 0) == .success(.amount(250)))
        #expect(DocumentInput.editingText(.percent("7.50"), exponent: 2) == ("7.5", true))
        #expect(DocumentInput.editingText(minor: 0, exponent: 2).isEmpty)
    }
}
