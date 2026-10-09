import Foundation
import InvoiceCore
import Testing
@testable import InvoiceUI

/// The guided builder of ADR-0020: the "Add an item" sheet (`spec/documents.md` §3.2), payment-term chips (§3.3),
/// Review & send (§6.1) and Home's first-run checklist (`spec/setup.md` §3.2).
@MainActor
@Suite("Guided builder")
struct GuidedBuilderTests {
    func newInvoice(_ session: Session) async -> DocumentViewModel {
        let model = DocumentViewModel(session: session, route: .new(.invoice, id: "doc-1"), autosaveDelay: .zero)
        await model.load()
        return model
    }

    func item(_ session: Session, named name: String) async throws -> CatalogItem {
        let items = try await firstValue(session.dependencies.catalog.observeItems(businessID: session.business.id))
        return try #require(items?.first { $0.name == name })
    }

    /// Something new: description, quantity, price and rate.
    func addSomethingNew(_ model: DocumentViewModel, _ description: String, quantity: String = "1", price: String,
                         includesTax: Bool = false, saveToItems: Bool = false) -> Bool {
        model.addLine()
        model.state.lineEditor?.draft.description = description
        model.state.lineEditor?.draft.quantityText = quantity
        model.state.lineEditor?.draft.priceText = price
        model.state.lineEditor?.draft.rateId = "gst_18"
        model.state.lineEditor?.includesTax = includesTax
        model.state.lineEditor?.saveToItems = saveToItems
        return model.commitLineEditor()
    }

    @Test func theFirstLinesSwitchSetsTheDocumentsBasisAndKeepsThePriceAsTyped() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        #expect(addSomethingNew(model, "Logo refresh", quantity: "2", price: "2500", includesTax: true))
        #expect(model.state.document.pricesIncludeTax)
        #expect(model.state.document.lines[0].unitPriceMinor == 250_000)
        #expect(model.computed?.totals.total == 500_000) // 2 × ₹2,500 including 18%
    }

    @Test func aLaterLineOnTheOtherBasisIsConverted() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        #expect(addSomethingNew(model, "Website design", price: "12000"))
        #expect(addSomethingNew(model, "Logo refresh", price: "2500", includesTax: true))
        #expect(!model.state.document.pricesIncludeTax) // the document's basis stays
        #expect(model.state.document.lines[1].unitPriceMinor == 211_864) // 2500 × 100 / 118
    }

    @Test func theLiveLineTotalIsTheEnginesForThatLine() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        model.addLine()
        model.state.lineEditor?.draft.quantityText = "2"
        model.state.lineEditor?.draft.priceText = "2500"
        #expect(model.lineEditorPreview == nil) // no rate yet
        model.state.lineEditor?.draft.rateId = "gst_18"
        #expect(model.lineEditorPreview?.text == "2 × ₹2,500.00 + ₹900.00 GST")
        #expect(model.lineEditorPreview?.total == "₹5,900.00")
        model.state.lineEditor?.includesTax = true
        // Inside the price: CGST and SGST of 9% are rounded each (₹381.36), so ₹762.72 of the ₹5,000.
        #expect(model.lineEditorPreview?.text == "2 × ₹2,500.00 incl. ₹762.72 GST")
        #expect(model.lineEditorPreview?.total == "₹5,000.00")
    }

    @Test func savingToMyItemsWritesTheItemAndLinksTheLine() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        #expect(addSomethingNew(model, "Hosting setup", price: "1000", saveToItems: true))
        await model.waitForItemSaves()
        let saved = try await item(session, named: "Hosting setup")
        #expect(saved.unitPriceMinor == 100_000 && saved.rateId == "gst_18" && !saved.priceIncludesTax)
        #expect(model.state.document.lines[0].catalogItemId == saved.id)
        await model.flush()
        let stored = try await session.dependencies.documents.fetchDocument(id: "doc-1")
        #expect(stored?.lines.first?.catalogItemId == saved.id)
    }

    @Test func somethingNewTakesTheRateOfASavedItemAddedMeanwhile() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        model.addLine() // the sheet opens before any line exists: no rate yet
        #expect(model.state.lineEditor?.draft.rateId == "")
        model.addItem(try await item(session, named: "Tea leaves")) // GST 5%, from "My saved items"
        #expect(model.state.lineEditor?.isNew == true && model.state.lineEditor?.draft.rateId == "gst_5")
    }

    @Test func theSharedPDFIsNamedAfterTheNumber() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        #expect(DocumentText.pdfFileName(model.state.document) == "Invoice draft.pdf")
        var issued = model.state.document
        issued.number = "INV/26-27/0001"
        #expect(DocumentText.pdfFileName(issued) == "Invoice INV-26-27-0001.pdf")
    }

    @Test func aForeignCurrencyLineIsNotOfferedForMyItems() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        model.setCurrency("USD")
        model.addLine()
        #expect(!model.canSaveLineToItems && model.state.lineEditor?.saveToItems == false)
    }

    @Test func howManyStepsByOneAndNeverBelowOne() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        model.addLine()
        model.stepLineQuantity(by: 1)
        #expect(model.state.lineEditor?.draft.quantityText == "2")
        model.stepLineQuantity(by: -1)
        model.stepLineQuantity(by: -1)
        #expect(model.state.lineEditor?.draft.quantityText == "1")
        model.state.lineEditor?.draft.quantityText = "1.5"
        model.stepLineQuantity(by: 1)
        #expect(model.state.lineEditor?.draft.quantityText == "2.5")
    }

    @Test func rateChipsComeFromTheSpec() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        model.addLine()
        #expect(model.lineRateChoices.chips.map(\.id) == ["gst_0", "gst_5", "gst_18", "gst_40"])
        #expect(model.lineRateChoices.others.contains { $0.id == "gst_28" })
    }

    @Test func paymentTermChipsSetTheDueDate() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        #expect(model.termChoices == [0, 7, 15, 30]) // the business's 15 days is one of them
        #expect(model.selectedTermDays == 15)
        model.setTerm(days: 7)
        #expect(model.state.document.dueDate == model.state.document.issueDate.adding(days: 7))
        #expect(model.selectedTermDays == 7)
        model.setDueDate(model.state.document.issueDate.adding(days: 10))
        #expect(model.selectedTermDays == nil)
    }

    @Test func reviewThenSendIssuesAndOpensTheChannel() async throws {
        let session = try await TestEnvironment.session()
        let model = await newInvoice(session)
        model.addItem(try await item(session, named: "Website development"))
        await model.requestIssue()
        #expect(model.state.confirmingIssue && model.state.numberPreview == "INV/26-27/0001")

        model.keepAsDraft()
        await model.sendAfterReview()
        #expect(model.isDraft && model.preview == nil)

        await model.requestIssue()
        model.send(via: .email)
        #expect(!model.state.confirmingIssue && model.state.pendingSend == .email)
        await model.sendAfterReview()
        #expect(model.state.document.number == "INV/26-27/0001" && !model.isDraft)
        #expect(model.preview?.pendingChannel == .email && model.state.pendingSend == nil)
    }

    @Test func homeShowsTheChecklistUntilTheFirstInvoiceIsSent() async throws {
        let session = try await TestEnvironment.session()
        let home = HomeViewModel(session: session)
        let task = Task { await home.observe() }
        defer { task.cancel() }
        await waitUntil { home.state.documentsLoaded && home.state.clientCount > 0 }
        #expect(home.state.checklist.isShown && home.state.checklist.doneCount == 3)

        let model = await newInvoice(session)
        model.addItem(try await item(session, named: "Website development"))
        await model.requestIssue()
        await model.confirmIssue()
        await waitUntil { !home.state.checklist.isShown }
        #expect(home.state.checklist.isDone(.sendInvoice))
    }
}
