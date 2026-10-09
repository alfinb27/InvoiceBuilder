import XCTest

/// End-to-end smoke flows for Phase 2 (ADR-0012): build an invoice from a client, a catalogue item and a one-off
/// line, then issue it. Runs on a seeded in-memory database (`-seed IN`).
final class DocumentSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBuildAndIssueAnInvoice() {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN"]
        app.launch()

        XCTAssertTrue(app.buttons["homeNewInvoice"].waitForExistence(timeout: 10))
        app.buttons["homeNewInvoice"].tap()

        // Client
        XCTAssertTrue(app.buttons["chooseClient"].waitForExistence(timeout: 5))
        app.buttons["chooseClient"].tap()
        let rao = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rao Traders")).firstMatch
        XCTAssertTrue(rao.waitForExistence(timeout: 5))
        rao.tap()

        // A catalogue item
        app.openCatalogue().tap()
        app.buttons["catalogDone"].tap()

        // A one-off line
        scrollTo(app.buttons["addLine"], in: app)
        app.buttons["addLine"].tap()
        let description = app.textFields["Description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        // Return moves Description → Quantity → Price (the editor's own field order), so the price is reached
        // without tapping it: on CI's iOS 18.5 simulator a tap there can land under the keyboard or outside the sheet.
        description.typeText("Hosting setup\n")
        // By identifier or label: SwiftUI puts a modifier's identifier on the field on some iOS versions only.
        let quantity = app.textFields.matching(NSPredicate(format: "identifier == %@ OR label == %@", "lineQuantity",
                                                           "Quantity")).firstMatch
        if !waitForFocus(quantity) { XCTFail("Return didn't move to the quantity. \(fields(in: app))") }
        app.typeText("\n")
        let price = app.textFields.matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", "linePrice",
                                                        "Price")).firstMatch
        if !waitForFocus(price) { XCTFail("Return didn't move to the price. \(fields(in: app))") }
        app.typeText("1000")
        XCTAssertTrue(((price.value as? String) ?? "").contains("1000"), "price typed: \(price.value ?? "nil")")
        app.buttons["lineDone"].tap()

        // Totals: (5000 + 1000) × 1.18 = ₹7,080.00, from the engine
        let total = app.staticTexts.matching(identifier: "totalAmount").firstMatch
        scrollTo(total, in: app)
        XCTAssertTrue(total.label.contains("₹7,080.00"), total.label)

        // Issue
        app.buttons["issueButton"].tap()
        let confirm = app.buttons["Issue invoice"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["INV/26-27/0001"].firstMatch.waitForExistence(timeout: 10))
        let issuedTotal = app.staticTexts.matching(identifier: "issuedTotal").firstMatch
        XCTAssertTrue(issuedTotal.label.contains("₹7,080.00"), issuedTotal.label)
    }

    /// Phase 3: the PDF preview of an issued invoice, the template switcher and the share button
    /// (`spec/pdf/RENDERING.md`, `spec/documents.md` §8).
    @MainActor
    func testPreviewAnInvoiceAndSwitchTemplate() {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN"]
        app.launch()

        XCTAssertTrue(app.buttons["homeNewInvoice"].waitForExistence(timeout: 10))
        app.buttons["homeNewInvoice"].tap()
        XCTAssertTrue(app.buttons["chooseClient"].waitForExistence(timeout: 5))
        app.buttons["chooseClient"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rao Traders")).firstMatch.tap()
        app.openCatalogue().tap()
        app.buttons["catalogDone"].tap()

        // The draft previews, watermarked.
        let preview = app.buttons["previewButton"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()
        XCTAssertTrue(app.buttons["template-classic"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["sharePDF"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["template-classic"].tap()
        XCTAssertTrue(app.buttons["template-minimal"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()

        // Issue it, then preview the numbered document.
        XCTAssertTrue(app.buttons["issueButton"].waitForExistence(timeout: 5))
        app.buttons["issueButton"].tap()
        let confirm = app.buttons["Issue invoice"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["INV/26-27/0001"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()
        XCTAssertTrue(app.buttons["sharePDF"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testIssueShowsWhatIsMissing() {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN"]
        app.launch()

        XCTAssertTrue(app.buttons["homeNewInvoice"].waitForExistence(timeout: 10))
        app.buttons["homeNewInvoice"].tap()
        XCTAssertTrue(app.buttons["issueButton"].waitForExistence(timeout: 5))
        app.buttons["issueButton"].tap()
        let problem = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Add at least one line"))
            .firstMatch
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
    }

    /// Waits up to five seconds for `element` to take keyboard focus (CI's simulators are slower).
    @MainActor
    private func waitForFocus(_ element: XCUIElement) -> Bool {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let expectation = XCTNSPredicateExpectation(predicate: focused, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
    }

    /// Every text field on screen and which one has the keyboard: tells "the field wasn't found" apart from
    /// "Return didn't move the focus" when this fails on CI.
    @MainActor
    private func fields(in app: XCUIApplication) -> String {
        let rows = app.textFields.allElementsBoundByIndex.map { field in
            let focused = (field.value(forKey: "hasKeyboardFocus") as? Bool) == true
            return "[\(field.identifier)|\(field.label)\(focused ? "|FOCUSED" : "")]"
        }
        return "Text fields: " + rows.joined(separator: " ")
    }

    /// Swipes up until `element` is on screen.
    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !(element.exists && element.isHittable) && attempts < 10 {
            app.swipeUp(velocity: .slow)
            attempts += 1
        }
        XCTAssertTrue(element.exists, "\(element) not found")
    }
}
