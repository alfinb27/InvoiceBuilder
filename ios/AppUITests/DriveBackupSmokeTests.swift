import XCTest

/// Automatic backup to Google Drive (`spec/backup.md` §7) with the in-memory Drive (`-fakeDrive`): connect, back up
/// now, and restore from the list; and the Welcome screen's "Restore from Google Drive".
final class DriveBackupSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBackUpToGoogleDriveThenRestoreFromIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN", "-fakeDrive"]
        app.launch()

        openTab("Settings", app)
        let backup = app.buttons["Backup"].firstMatch
        XCTAssertTrue(backup.waitForExistence(timeout: 10))
        backup.tap()

        let row = app.buttons["backup.drive"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(text("Off", in: app).exists)
        row.tap()
        let connect = app.buttons["backup.drive.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        connect.tap()
        XCTAssertTrue(text("you@example.com", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(text("Last backup to Google Drive: today", in: app).waitForExistence(timeout: 10))
        let backUpNow = app.buttons["backup.drive.backUpNow"]
        backUpNow.tap()
        // Wait for the backup to finish (the page is disabled while it runs), then go back.
        XCTAssertTrue(backUpNow.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: backUpNow)
        waitForExpectations(timeout: 10)
        app.buttons["backup.drive.done"].tap() // back to Backup
        XCTAssertTrue(text("Last backup: today", in: app).waitForExistence(timeout: 5)) // §7.5: it counts as a backup
        XCTAssertTrue(text("On", in: app).exists)

        let restore = app.buttons["backup.drive.restore"]
        if !restore.isHittable { app.swipeUp() }
        restore.tap()
        let first = app.buttons["driveBackup-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["driveBackup-1"].exists == false) // today's file was replaced, not added
        first.tap()
        XCTAssertTrue(app.buttons["backup.confirmRestore"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].firstMatch.tap()

        app.buttons["backup.drive"].tap()
        app.buttons["backup.drive.disconnect"].tap()
        XCTAssertTrue(app.buttons["backup.drive.connect"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWelcomeOffersRestoreFromGoogleDrive() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemory", "-fakeDrive"]
        app.launch()

        XCTAssertTrue(app.buttons["onboarding.usedBefore"].waitForExistence(timeout: 10))
        app.buttons["onboarding.usedBefore"].tap()
        let drive = app.buttons["onboarding.restoreDrive"].firstMatch
        XCTAssertTrue(drive.waitForExistence(timeout: 5))
        drive.tap()
        XCTAssertTrue(text("No backups in Google Drive yet", in: app).waitForExistence(timeout: 10))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 5))
    }

    /// A tab bar button on iPhone; the top tab bar (or sidebar) on iPad.
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
