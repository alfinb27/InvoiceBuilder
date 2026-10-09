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
        snapshot("01-home-first-run", app)

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
        snapshot("20-builder-empty", app)
        app.buttons["chooseClient"].tap()
        snapshot("21-client-picker", app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Umesh Foods")).firstMatch.tap()
        app.openAddItem().tap()
        app.buttons["catalogItem-Tea leaves"].tap()
        snapshot("22-add-item-saved", app)
        app.buttons["Something new"].tap()
        let description = app.textFields["lineDescription"]
        if description.waitForExistence(timeout: 5) {
            description.tap()
            description.typeText("Delivery\n")
            app.typeText("250")
        }
        snapshot("23-add-item-new", app)
        app.buttons["lineDone"].tap()
        snapshot("24-builder", app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tea leaves")).firstMatch.tap()
        XCTAssertTrue(app.buttons["lineDone"].waitForExistence(timeout: 5))
        snapshot("25-edit-item", app)
        app.buttons["lineDone"].tap()
        app.buttons["moreOptions"].tap()
        snapshot("26-more-options", app)
        app.buttons["reviewAndSend"].tap()
        XCTAssertTrue(app.buttons["review.send"].waitForExistence(timeout: 10))
        snapshot("27-review-and-send", app)
        app.buttons["channel-email"].tap()
        snapshot("28-review-email", app)
        app.buttons["channel-whatsApp"].tap()
        app.buttons["review.keepDraft"].tap()
        app.reviewAndSend()
        XCTAssertTrue(app.staticTexts.matching(identifier: "issuedTotal").firstMatch.waitForExistence(timeout: 10))
        snapshot("29-sent-invoice", app)
        // The PDF, and each template it can be drawn with.
        app.buttons["previewButton"].firstMatch.tap()
        XCTAssertTrue(app.buttons["template-classic"].waitForExistence(timeout: 10))
        snapshot("30-preview-modern", app)
        for template in ["classic", "compact", "minimal"] {
            app.buttons["template-\(template)"].tap()
            snapshot("31-preview-\(template)", app)
        }
        app.buttons["Done"].firstMatch.tap()
        openTab("Invoices", app)
        Thread.sleep(forTimeInterval: 1) // the large title fades in after the tab switch
        snapshot("32-invoices-list", app)
        openTab("Home", app)
        snapshot("33-home-dashboard", app)
    }

    /// iPad, landscape: the builder's right pane renders the draft as it is edited (Phase 3). Skipped on iPhone,
    /// where the pane does not exist.
    @MainActor
    func testBuilderLivePreviewPane() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN"]
        app.launch()
        XCTAssertTrue(app.buttons["homeNewInvoice"].waitForExistence(timeout: 10))
        app.buttons["homeNewInvoice"].tap()
        let pane = app.descendants(matching: .any).matching(identifier: "builderPane").firstMatch
        try XCTSkipUnless(pane.waitForExistence(timeout: 5), "no side pane at this width")

        app.chooseClient("Umesh Foods")
        app.openAddItem().tap()
        app.buttons["catalogDone"].tap()

        // The pane shows the document itself, redrawn after each edit.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "builderPreview").firstMatch
            .waitForExistence(timeout: 15))
        snapshot("40-ipad-live-preview", app)
        pane.buttons["Totals"].tap()
        snapshot("41-ipad-totals-pane", app)
        pane.buttons["Preview"].tap()
        app.buttons["previewButton"].firstMatch.tap()
        XCTAssertTrue(app.buttons["template-classic"].waitForExistence(timeout: 15))
        snapshot("42-ipad-preview-sheet", app)
        app.buttons["Done"].firstMatch.tap()
    }

    /// The builder at an accessibility text size (Dynamic Type layout check).
    @MainActor
    func testBuilderAtLargeTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        XCTAssertTrue(app.buttons["homeNewInvoice"].waitForExistence(timeout: 10))
        snapshot("50-home-large-text", app)
        app.buttons["homeNewInvoice"].tap()
        app.chooseClient("Rao Traders")
        app.openAddItem().tap()
        app.buttons["Something new"].tap()
        snapshot("51-add-item-large-text", app)
        app.buttons["Cancel"].firstMatch.tap()
        snapshot("52-builder-large-text", app)
        app.swipeUp(velocity: .slow)
        app.swipeUp(velocity: .slow)
        snapshot("53-builder-large-text-scrolled", app)
    }

    @MainActor
    func testTourOfOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemory"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 10))
        snapshot("10-welcome", app)
        app.buttons["onboarding.start"].tap()
        XCTAssertTrue(app.buttons["country-IN"].waitForExistence(timeout: 5))
        snapshot("11-where-you-work", app)
        app.buttons["country-IN"].tap()
        snapshot("12-where-you-work-india", app)
        app.buttons["country-other"].tap()
        snapshot("13-somewhere-else", app)
        app.buttons["country-IN"].tap()
        app.buttons["onboarding.continue"].tap()
        let gstin = app.textFields["GSTIN"]
        if gstin.waitForExistence(timeout: 5) {
            gstin.tap()
            gstin.typeText("29AAGCB7383J1Z4\n")
        }
        snapshot("14-your-business", app)
        app.buttons["onboarding.continue"].tap()
        snapshot("15-business-problems", app)
    }

    @MainActor
    private func openTab(_ name: String, _ app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        if tab.exists { tab.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    /// The whole screen, not `app.screenshot()`: in landscape the app's own screenshot comes back in the
    /// portrait frame and the right of the window is cropped off.
    @MainActor
    private func snapshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
