import XCTest

/// Walks the main screens of a seeded business and attaches a screenshot of each (kept in the result bundle).
/// Run on an iPhone and an iPad simulator to review layouts; later the basis for App Store screenshots.
final class ScreenshotTour: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testTourOfSetupScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Bharat Web Studio"].waitForExistence(timeout: 10))
        snapshot("01-home", app)

        openTab("Clients", app)
        XCTAssertTrue(app.staticTexts["Rao Traders"].waitForExistence(timeout: 5))
        snapshot("02-clients", app)
        app.staticTexts["Rao Traders"].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        snapshot("03-client-detail", app)
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        snapshot("04-client-editor", app)
        app.buttons["Cancel"].tap()

        openTab("Items", app)
        XCTAssertTrue(app.staticTexts["Website development"].waitForExistence(timeout: 5))
        snapshot("05-items", app)
        app.buttons["Add item"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        snapshot("06-item-editor", app)
        app.buttons["Cancel"].tap()

        openTab("Settings", app)
        XCTAssertTrue(app.staticTexts["Invoice numbering"].waitForExistence(timeout: 5))
        snapshot("07-settings", app)
        app.staticTexts["Invoice numbering"].tap()
        XCTAssertTrue(app.staticTexts["INV/26-27/0001"].waitForExistence(timeout: 5)
                      || app.staticTexts["Next number"].waitForExistence(timeout: 1))
        snapshot("08-numbering", app)
    }

    @MainActor
    func testTourOfTheBuilder() {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN"]
        app.launch()
        XCTAssertTrue(app.buttons["homeNewInvoice"].waitForExistence(timeout: 10))
        app.buttons["homeNewInvoice"].tap()
        XCTAssertTrue(app.buttons["chooseClient"].waitForExistence(timeout: 5))
        app.buttons["chooseClient"].tap()
        snapshot("20-client-picker", app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Umesh Foods")).firstMatch.tap()
        let addFromItems = app.buttons["addFromItems"]
        if !addFromItems.isHittable { app.swipeUp(velocity: .slow) }
        addFromItems.tap()
        XCTAssertTrue(app.buttons["catalogItem-Website development"].waitForExistence(timeout: 5))
        app.buttons["catalogItem-Website development"].tap()
        app.buttons["catalogItem-Tea leaves"].tap()
        snapshot("21-catalog-picker", app)
        app.buttons["catalogDone"].tap()
        snapshot("22-builder", app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tea leaves")).firstMatch.tap()
        XCTAssertTrue(app.buttons["lineDone"].waitForExistence(timeout: 5))
        snapshot("23-line-editor", app)
        app.buttons["lineDone"].tap()
        app.swipeUp(velocity: .slow)
        snapshot("24-builder-totals", app)
        app.buttons["issueButton"].tap()
        if app.buttons["Issue invoice"].waitForExistence(timeout: 5) { app.buttons["Issue invoice"].tap() }
        XCTAssertTrue(app.staticTexts.matching(identifier: "issuedTotal").firstMatch.waitForExistence(timeout: 10))
        snapshot("25-issued-invoice", app)
        openTab("Invoices", app)
        snapshot("26-invoices-list", app)
    }

    /// The builder at an accessibility text size (Dynamic Type layout check).
    @MainActor
    func testBuilderAtLargeTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        XCTAssertTrue(app.buttons["homeNewInvoice"].waitForExistence(timeout: 10))
        app.buttons["homeNewInvoice"].tap()
        XCTAssertTrue(app.buttons["chooseClient"].waitForExistence(timeout: 5))
        app.buttons["chooseClient"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rao Traders")).firstMatch.tap()
        var attempts = 0
        while !app.buttons["addFromItems"].isHittable && attempts < 8 {
            app.swipeUp(velocity: .slow)
            attempts += 1
        }
        app.buttons["addFromItems"].tap()
        XCTAssertTrue(app.buttons["catalogItem-Website development"].waitForExistence(timeout: 5))
        app.buttons["catalogItem-Website development"].tap()
        app.buttons["catalogDone"].tap()
        snapshot("30-builder-large-text", app)
        app.swipeUp(velocity: .slow)
        app.swipeUp(velocity: .slow)
        snapshot("31-builder-large-text-totals", app)
    }

    @MainActor
    func testTourOfOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemory"]
        app.launch()
        XCTAssertTrue(app.buttons["India"].firstMatch.waitForExistence(timeout: 10))
        snapshot("10-onboarding-country", app)
        app.buttons["India"].firstMatch.tap()
        app.buttons["Continue"].tap()
        snapshot("11-onboarding-registration", app)
        app.buttons["Continue"].tap()
        let gstin = app.textFields["GSTIN"]
        if gstin.waitForExistence(timeout: 5) {
            gstin.tap()
            gstin.typeText("29AAGCB7383J1Z4\n")
        }
        snapshot("12-onboarding-business", app)
    }

    @MainActor
    private func openTab(_ name: String, _ app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        if tab.exists { tab.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    @MainActor
    private func snapshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
