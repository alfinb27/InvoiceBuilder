import Foundation
import InvoiceCore
import Testing
@testable import InvoiceUI

@MainActor
@Suite("Document builder")
struct DocumentViewModelTests {
    /// A new invoice in the seeded Indian business, loaded and ready to edit (autosave without delay).
    func newInvoice(_ session: Session, docType: DocumentType = .invoice) async -> DocumentViewModel {
        let model = DocumentViewModel(session: session, route: .new(docType, id: "doc-1"), autosaveDelay: .zero)
        await model.load()
        return model
    }

    func client(_ session: Session, named name: String) async throws -> Client {
        let clients = try await firstValue(session.dependencies.clients.observeClients(businessID: session.business.id))
        return try #require(clients?.first { $0.name == name })
    }

    func item(_ session: Session, named name: String) async throws -> CatalogItem {
        let items = try await firstValue(session.dependencies.catalog.observeItems(businessID: session.business.id))
        return try #require(items?.first { $0.name == name })
    }

    @Test func aNewDraftIsWrittenOnItsFirstChangeOnly() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        #expect(model.state.document.dueDate == LocalDate(iso: "2026-10-04")) // 15 payment days
        await model.flush()
        #expect(try await session.dependencies.documents.fetchDocument(id: "doc-1") == nil)

        model.chooseClient(try await client(session, named: "Rao Traders"))
        await model.flush()
        let stored = try #require(try await session.dependencies.documents.fetchDocument(id: "doc-1"))
        #expect(stored.buyerSnapshot?.name == "Rao Traders" && model.state.isPersisted)
    }

    @Test func catalogueItemsAndTotalsComeFromTheEngine() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        model.chooseClient(try await client(session, named: "Umesh Foods")) // Maharashtra: IGST
        model.addItem(try await item(session, named: "Website development"))
        model.addItem(try await item(session, named: "Tea leaves"))
        let computed = try #require(model.computed)
        #expect(computed.taxLines.map(\.component) == ["IGST", "IGST"])
        #expect(computed.totals.total == 615_200) // 5000 × 1.18 + 240 × 1.05 = 5900 + 252
        #expect(model.state.selectedLineID == model.state.document.lines.last?.id)

        model.setDiscountText("10")
        #expect(model.state.document.discount == .percent("10"))
        model.setDiscountText("10.5.1")
        #expect(model.discountIssue == .invalidNumber(.invalid) && model.state.document.discount == .percent("10"))
        model.setDiscountText("")
        model.setShippingText("150")
        #expect(model.state.document.shippingMinor == 15_000)
        #expect(model.computed?.totals.shipping == 15_000)
    }

    @Test func lineEditorValidatesThenApplies() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        model.addLine()
        #expect(model.state.lineEditor?.isNew == true && model.state.lineEditor?.draft.rateId == "")
        #expect(!model.commitLineEditor())
        #expect(model.visibleLineIssue(.description) == .required)
        #expect(model.visibleLineIssue(.price) == .required && model.visibleLineIssue(.rate) == .required)

        model.state.lineEditor?.draft.description = "Logo design"
        model.state.lineEditor?.draft.quantityText = "2"
        model.state.lineEditor?.draft.priceText = "1,250.50"
        model.state.lineEditor?.draft.rateId = "gst_18"
        model.state.lineEditor?.draft.discountText = "5000"
        model.state.lineEditor?.draft.discountIsPercent = false
        #expect(!model.commitLineEditor()) // ₹5,000 off ₹2,501
        #expect(model.visibleLineIssue(.discount) == .exceedsLineAmount)
        model.state.lineEditor?.draft.discountText = "1"
        #expect(model.commitLineEditor())
        let line = try #require(model.state.document.lines.first)
        #expect(line.quantity == "2" && line.unitPriceMinor == 125_050 && line.discount == .amount(100))
        #expect(model.computed?.lines.first?.amount == 250_000)

        // The next one-off line takes the previous line's rate.
        model.addLine()
        #expect(model.state.lineEditor?.draft.rateId == "gst_18")
        model.cancelLineEditor()
        #expect(model.state.document.lines.count == 1)
    }

    @Test func linesCanBeDuplicatedMovedAndDeleted() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        model.addItem(try await item(session, named: "Website development"))
        model.addItem(try await item(session, named: "SEO audit"))
        let first = model.state.document.lines[0].id
        model.duplicateLine(first)
        #expect(model.state.document.lines.map(\.description) == ["Website development", "Website development",
                                                                  "SEO audit"])
        #expect(model.state.document.lines.map(\.position) == [0, 1, 2])
        model.moveLines(from: IndexSet(integer: 2), to: 0)
        #expect(model.state.document.lines.first?.description == "SEO audit")
        model.deleteLines(at: IndexSet(integer: 0))
        #expect(model.state.document.lines.count == 2 && model.state.document.lines.map(\.position) == [0, 1])
        await model.flush()
        let stored = try await session.dependencies.documents.fetchDocument(id: "doc-1")
        #expect(stored?.lines.map(\.id) == model.state.document.lines.map(\.id))
    }

    @Test func issuingShowsProblemsThenNumbersTheInvoice() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        await model.requestIssue()
        #expect(model.state.issueProblems == [.noLines] && !model.state.confirmingIssue)

        model.chooseClient(try await client(session, named: "Rao Traders"))
        model.addItem(try await item(session, named: "Website development"))
        #expect(model.state.issueProblems.isEmpty) // problems update as the draft changes
        await model.requestIssue()
        #expect(model.state.confirmingIssue && model.state.numberPreview == "INV/26-27/0001")

        await model.confirmIssue()
        #expect(model.state.document.lifecycle == .issued && model.state.document.number == "INV/26-27/0001")
        #expect(model.computed?.totals.total == 590_000)
        #expect(!model.isDraft)
        model.addLine() // issued documents are read-only
        #expect(model.state.lineEditor == nil)
    }

    @Test func untouchedDraftsAreDeletedOnClose() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        model.setNotesText("Draft notes")
        await model.flush()
        #expect(try await session.dependencies.documents.fetchDocument(id: "doc-1") != nil)
        await model.close()
        #expect(try await session.dependencies.documents.fetchDocument(id: "doc-1") == nil)
    }

    @Test func quotesConvertToInvoices() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session, docType: .quote)
        #expect(model.state.document.validUntil == LocalDate(iso: "2026-10-19"))
        model.chooseClient(try await client(session, named: "Rao Traders"))
        model.addItem(try await item(session, named: "SEO audit"))
        await model.requestIssue()
        #expect(model.state.numberPreview == "QT/26-27/0001")
        await model.confirmIssue()
        #expect(model.canConvert)

        await model.convertToInvoice()
        let route = try #require(session.router.documents.selection)
        #expect(session.router.documents.docType == .invoice)
        let invoice = try #require(try await session.dependencies.documents.fetchDocument(id: route.id))
        #expect(invoice.convertedFromId == "doc-1" && invoice.isDraft && invoice.lines.count == 1)
        #expect(!model.canConvert)
    }

    @Test func currencyChangesResetTheExchangeRateAndRoundOff() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        model.chooseClient(try await client(session, named: "Acme Inc.")) // a US client: export with IGST
        #expect(model.state.document.supplyType == "exportWithTax")
        model.setCurrency("USD")
        #expect(model.state.document.roundOff == false && model.isForeignCurrency)
        model.setExchangeRateText("83.25")
        #expect(model.state.document.exchangeRate == "83.25")
        model.addItem(try await item(session, named: "Website development"))
        #expect(model.state.document.lines.first?.unitPriceMinor == 6006) // ₹5,000 / 83.25 = $60.06
        model.setCurrency("EUR")
        #expect(model.state.document.exchangeRate == nil && model.state.exchangeRateText.isEmpty)
        model.setCurrency(.inr)
        #expect(model.state.document.roundOff == nil)
    }

    @Test func amountsThatDoNotFitTheNewCurrencyAreCleared() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        model.addItem(try await item(session, named: "Website development"))
        model.setShippingText("12.50")
        model.setDiscountText("2.50")
        model.setDiscountIsPercent(false)
        #expect(model.state.document.shippingMinor == 1_250 && model.state.document.discount == .amount(250))

        model.setCurrency("JPY") // yen have no minor units, so "12.50" cannot mean ¥12.50
        #expect(model.state.document.shippingMinor == 0 && model.state.document.discount == nil)
        #expect(model.shippingIssue == .invalidNumber(.tooManyDecimals))
        #expect(model.computed?.totals.shipping == 0)
    }

    @Test func nextNumberCannotGoBelowAnIssuedOne() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        model.chooseClient(try await client(session, named: "Rao Traders"))
        model.addItem(try await item(session, named: "Website development"))
        await model.requestIssue()
        await model.confirmIssue()

        let numbering = NumberingSettingsViewModel(session: session)
        let series = try #require(try await firstValue(
            session.dependencies.numberingSeries.observeSeries(businessID: session.business.id))?.first)
        numbering.edit(series)
        for _ in 0..<200 where numbering.state.highestIssued.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        numbering.state.draft?.nextNumberText = "1"
        #expect(numbering.draftIssues[.nextNumber] == .alreadyIssued(highest: 1))
        numbering.state.draft?.nextNumberText = "2"
        #expect(numbering.draftIssues[.nextNumber] == nil)
    }
}

@Suite("Decimal pads")
struct DecimalPadTests {
    @Test func commaDecimalLocalesTypeADecimalPoint() {
        #expect(DecimalPadText.normalized("12,5", locale: Locale(identifier: "de_DE")) == "12.5")
        #expect(DecimalPadText.normalized("1,250.50", locale: Locale(identifier: "en_IN")) == "1,250.50")
        #expect(MoneyInput.parse(DecimalPadText.normalized("12,50", locale: Locale(identifier: "fr_FR")),
                                 exponent: 2) == .success(1_250))
    }
}
