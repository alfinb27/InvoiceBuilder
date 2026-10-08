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
        scrollTo(app.buttons["addFromItems"], in: app)
        app.buttons["addFromItems"].tap()
        let website = app.buttons["catalogItem-Website development"]
        XCTAssertTrue(website.waitForExistence(timeout: 5))
        website.tap()
        app.buttons["catalogDone"].tap()

        // A one-off line
        scrollTo(app.buttons["addLine"], in: app)
        app.buttons["addLine"].tap()
        let description = app.textFields["Description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        // No Return here: on the iOS 18.5 SDK CI links against, Return can dismiss the line editor's popover.
        description.typeText("Hosting setup")
        // With the keyboard up, the price row can sit below the fold on a smaller simulator (CI's), where the Form
        // has not created it yet. Scroll it into view.
        let price = app.textFields.matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@",
                                                        "linePrice", "Price")).firstMatch
        var attempts = 0
        while !(price.waitForExistence(timeout: 2) && price.isHittable) && attempts < 6 {
            app.swipeUp(velocity: .slow)
            attempts += 1
        }
        if !price.exists { print("PRICE-FIELD-MISSING hierarchy:\n\(app.debugDescription)") }
        XCTAssertTrue(price.exists, "the price field never appeared")
        // On a slow runner the tap can land before the field accepts focus, and `price.typeText` then fails outright
        // ("Neither element nor any descendant has keyboard focus"). Tap until it has focus (by coordinate the second
        // time), then type through the app, which sends keys to whatever is focused. Check, and retry.
        for attempt in 0..<4 where !((price.value as? String) ?? "").contains("1000") {
            if attempt.isMultiple(of: 2) {
                price.tap()
            } else {
                price.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            guard waitForFocus(price) else { continue }
            if let typed = price.value as? String, !typed.isEmpty, !typed.hasPrefix("0.00") {
                app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count))
            }
            app.typeText("1000")
        }
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
        scrollTo(app.buttons["addFromItems"], in: app)
        app.buttons["addFromItems"].tap()
        XCTAssertTrue(app.buttons["catalogItem-Website development"].waitForExistence(timeout: 5))
        app.buttons["catalogItem-Website development"].tap()
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

    /// Waits up to two seconds for `element` to take keyboard focus.
    @MainActor
    private func waitForFocus(_ element: XCUIElement) -> Bool {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let expectation = XCTNSPredicateExpectation(predicate: focused, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 2) == .completed
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
