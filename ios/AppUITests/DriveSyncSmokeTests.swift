import XCTest

/// Live sync through Google Drive (`spec/drive-sync.md`) with the in-memory Drive (`-fakeDrive`): Settings → Sync,
/// and the Welcome screen's "Sync with Google Drive".
final class DriveSyncSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTurnOnGoogleDriveSyncThenSyncNow() {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN", "-fakeDrive"]
        app.launch()

        openTab("Settings", app)
        let sync = app.staticTexts["Sync"].firstMatch
        XCTAssertTrue(sync.waitForExistence(timeout: 10))
        sync.tap()

        let toggle = app.switches["sync.drive"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.tap()
        let confirm = app.buttons["sync.drive.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(text("Up to date", in: app).waitForExistence(timeout: 10))
        let now = app.buttons["sync.drive.now"]
        XCTAssertTrue(now.exists)
        now.tap()
        XCTAssertTrue(text("Up to date", in: app).waitForExistence(timeout: 10))

        toggle.switches.firstMatch.tap()
        XCTAssertFalse(now.waitForExistence(timeout: 2))
    }

    @MainActor
    func testWelcomeOffersSyncWithGoogleDrive() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemory", "-fakeDrive"]
        app.launch()

        XCTAssertTrue(app.buttons["onboarding.usedBefore"].waitForExistence(timeout: 10))
        app.buttons["onboarding.usedBefore"].tap()
        let drive = app.buttons["onboarding.syncDrive"].firstMatch
        XCTAssertTrue(drive.waitForExistence(timeout: 5))
        drive.tap()
        // An empty Drive: nothing arrives, so the Welcome screen stays.
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func openTab(_ name: String, _ app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 10) { tab.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    @MainActor
    private func text(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
