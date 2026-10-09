import XCTest

/// End-to-end smoke flows (ADR-0012, ADR-0020): build an invoice from a client, a saved item and something new,
/// then review and send it. Runs on a seeded in-memory database (`-seed IN`).
final class DocumentSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBuildAndSendAnInvoice() {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN"]
        app.launch()

        XCTAssertTrue(app.buttons["homeNewInvoice"].waitForExistence(timeout: 10))
        app.buttons["homeNewInvoice"].tap()

        // 1 Who is it for?
        app.chooseClient("Rao Traders")

        // 2 What are you charging for? A saved item, then something new.
        app.openAddItem().tap()
        XCTAssertTrue(app.staticTexts["Added"].waitForExistence(timeout: 5))
        app.buttons["Something new"].tap()
        let description = app.textFields["lineDescription"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        // Return moves to the price (the sheet's own field order), so the price is reached without tapping it:
        // on CI's simulators a tap there can land under the keyboard.
        description.typeText("Hosting setup\n")
        let price = app.textFields["linePrice"]
        if !waitForFocus(price) { XCTFail("Return didn't move to the price. \(fields(in: app))") }
        app.typeText("1000")
        // The rate carries over from the saved item (GST 18%); the line's total is the engine's.
        let lineTotal = app.descendants(matching: .any).matching(identifier: "lineTotal").firstMatch
        XCTAssertTrue(lineTotal.waitForExistence(timeout: 5))
        XCTAssertTrue(lineTotal.label.contains("₹1,180.00"), lineTotal.label)
        app.buttons["lineDone"].tap()

        // Totals: (5000 + 1000) × 1.18 = ₹7,080.00, from the engine
        let total = app.staticTexts.matching(identifier: "totalAmount").firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("₹7,080.00"), total.label)

        // Review & send: the number it will get, then send it.
        app.buttons["reviewAndSend"].tap()
        let lock = app.descendants(matching: .any).matching(identifier: "review.lockTip").firstMatch
        XCTAssertTrue(lock.waitForExistence(timeout: 10))
        XCTAssertTrue(lock.label.contains("INV/26-27/0001"), lock.label)
        app.buttons["review.keepDraft"].tap()
        app.reviewAndSend()
        XCTAssertTrue(app.staticTexts["INV/26-27/0001"].firstMatch.waitForExistence(timeout: 10))
        let issuedTotal = app.staticTexts.matching(identifier: "issuedTotal").firstMatch
        XCTAssertTrue(issuedTotal.label.contains("₹7,080.00"), issuedTotal.label)
    }

    /// The PDF preview of a draft and of the sent invoice, the template switcher and the share button
    /// (`spec/pdf/RENDERING.md`, `spec/documents.md` §8).
    @MainActor
    func testPreviewAnInvoiceAndSwitchTemplate() {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN"]
        app.launch()

        XCTAssertTrue(app.buttons["homeNewInvoice"].waitForExistence(timeout: 10))
        app.buttons["homeNewInvoice"].tap()
        app.chooseClient("Rao Traders")
        app.openAddItem().tap()
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

        // Send it, then preview the numbered document.
        XCTAssertTrue(app.buttons["reviewAndSend"].waitForExistence(timeout: 5))
        app.reviewAndSend()
        XCTAssertTrue(app.staticTexts["INV/26-27/0001"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()
        XCTAssertTrue(app.buttons["sharePDF"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testSendShowsWhatIsMissing() {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN"]
        app.launch()

        XCTAssertTrue(app.buttons["homeNewInvoice"].waitForExistence(timeout: 10))
        app.buttons["homeNewInvoice"].tap()
        XCTAssertTrue(app.buttons["reviewAndSend"].waitForExistence(timeout: 5))
        app.buttons["reviewAndSend"].tap()
        let problem = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Add at least one item"))
            .firstMatch
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.send"].exists)
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
}
