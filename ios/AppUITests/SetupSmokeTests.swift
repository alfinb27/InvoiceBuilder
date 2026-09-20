import XCTest

/// End-to-end smoke flows for Phase 1 (ADR-0012): onboarding, then adding a client and an item. The app runs on an
/// in-memory database (`-inMemory`, `-seed IN`), so nothing touches the simulator's real data.
final class SetupSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testIndianBusinessOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemory"]
        app.launch()

        // 1 Country
        app.buttons["India"].firstMatch.tap()
        app.buttons["Continue"].tap()
        // 2 Registration: "Registered (regular)" is the default
        XCTAssertTrue(app.staticTexts["Registered (regular)"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        // 3 Business: the state comes from the GSTIN, the PAN is filled in from it
        type("Bharat Test Studio", into: app.textFields["Business name"], in: app)
        type("29AAGCB7383J1Z4", into: app.textFields["GSTIN"], in: app)
        XCTAssertTrue(app.staticTexts["Valid · Karnataka"].waitForExistence(timeout: 5))
        type("12 MG Road", into: app.textFields["Address line 1"], in: app)
        app.buttons["Continue"].tap()
        // 4 Bank and UPI (optional), 5 Logo and signature (optional)
        app.buttons["Continue"].tap()
        app.buttons["Finish"].tap()

        XCTAssertTrue(app.staticTexts["Bharat Test Studio"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["GSTIN 29AAGCB7383J1Z4"].exists)
    }

    @MainActor
    func testOnboardingShowsProblemsBeforeContinuing() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemory"]
        app.launch()

        app.buttons["Continue"].tap()
        XCTAssertTrue(text("Enter the country", in: app).waitForExistence(timeout: 5))
        app.buttons["United Kingdom"].firstMatch.tap()
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        type("GB123456789", into: app.textFields["VAT registration number"], in: app)
        app.buttons["Continue"].tap()
        XCTAssertTrue(text("Enter the business name", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(text("This VAT registration number has a typo", in: app).exists)
    }

    @MainActor
    func testAddClientAndItemToSeededBusiness() {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN"]
        app.launch()

        openTab("Clients", app)
        XCTAssertTrue(app.staticTexts["Rao Traders"].waitForExistence(timeout: 10))
        app.buttons["Add client"].tap()
        type("Kaveri Textiles", into: app.textFields["Name"], in: app)
        // Tap the switch itself: tapping the middle of a Form toggle row hits its label.
        app.switches["Business client (B2B)"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        type("33AAACC1206D1ZN", into: app.textFields["GSTIN (optional)"], in: app)
        XCTAssertTrue(app.staticTexts["Valid · Tamil Nadu"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Kaveri Textiles"].waitForExistence(timeout: 5))

        openTab("Items", app)
        XCTAssertTrue(app.staticTexts["Website development"].waitForExistence(timeout: 10))
        app.buttons["Add item"].tap()
        type("Logo design", into: app.textFields["Name"], in: app)
        type("7500", into: app.textFields["Price per unit in INR"], in: app)
        app.buttons["Rate"].tap()
        app.buttons["GST 18%"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Logo design"].waitForExistence(timeout: 5))
    }

    /// A tab bar button on iPhone; the top tab bar (or sidebar) on iPad.
    @MainActor
    private func openTab(_ name: String, _ app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        if tab.exists { tab.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    /// Scrolls the form until `field` is on screen, then types into it.
    @MainActor
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication,
                      file: StaticString = #filePath, line: UInt = #line) {
        var attempts = 0
        while !(field.exists && field.isHittable) && attempts < 8 {
            app.swipeUp(velocity: .slow)
            attempts += 1
        }
        XCTAssertTrue(field.exists, "field not found", file: file, line: line)
        field.tap()
        field.typeText(text + "\n") // return ends editing, so the keyboard never covers the next field
    }

    /// Static text whose label contains `text` (problem messages are read as "Problem: …").
    @MainActor
    private func text(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
