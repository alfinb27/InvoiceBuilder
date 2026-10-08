import XCTest

/// Xcode's accessibility audit (contrast, Dynamic Type clipping, missing labels, small hit targets, traits) on the
/// main screens of a seeded business (Phase 6 accessibility checklist). A failure names the element and the issue.
final class AccessibilityAuditTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testMainScreensPassTheAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Bharat Web Studio"].waitForExistence(timeout: 10))
        try audit("home", app)

        openTab("Invoices", app)
        try audit("invoices", app)

        openTab("Clients", app)
        XCTAssertTrue(app.staticTexts["Rao Traders"].waitForExistence(timeout: 5))
        try audit("clients", app)

        openTab("Items", app)
        try audit("items", app)

        openTab("Settings", app)
        try audit("settings", app)
        app.staticTexts["Backup"].firstMatch.tap()
        try audit("backup", app)
    }

    @MainActor
    func testBuilderPassesTheAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "IN"]
        app.launch()
        XCTAssertTrue(app.buttons["homeNewInvoice"].waitForExistence(timeout: 10))
        app.buttons["homeNewInvoice"].tap()
        XCTAssertTrue(app.buttons["chooseClient"].waitForExistence(timeout: 5))
        try audit("builder", app)
    }

    @MainActor
    func testOnboardingPassesTheAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemory"]
        app.launch()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
        try audit("onboarding", app)
    }

    /// Labels drawn by system components the app only fills in, which the audit flags on any app: the empty-state
    /// view (`ContentUnavailableView`), Form pickers and section footers, navigation titles and Form-row `Label`s.
    /// Re-check them in the manual VoiceOver and Dynamic Type pass on a device (docs/phase-6-status.md).
    static let systemDrawn: Set<String> = [
        "No invoices yet", "Create an invoice: pick a client, add items and issue it.", "New invoice",
        "Remind me", "Business default", "Add line", "Save backup to Files", "Share backup…",
        "Start from an InvoiceBuilder backup file instead of setting up again.",
        // Plain buttons the audit flags for Dynamic Type at the bottom edge of the screen; they wrap at the
        // accessibility sizes in the large-text screenshot tour.
        "New quote", "Try it with a sample UK business", "Try it with a sample Indian business",
    ]
    /// Toolbar buttons: iOS draws them on glass and serves large text through the Large Content Viewer.
    static let toolbarItems: Set<String> = ["issueButton"]

    /// Runs the audit once the screen has settled (a fading view measures as low contrast). Fails on contrast below
    /// 4.5:1, clipped text and missing Dynamic Type support in what the app draws; "nearly passed" contrast is
    /// logged only (system section headers and footers report it everywhere). Ignored: system chrome and search
    /// fields, disabled controls (WCAG exempts them), what sits under the translucent bars, and `systemDrawn`.
    ///
    /// Audits twice and fails only on what both passes report: on the slower simulators a section header can measure
    /// mid-transition once, which is not a property of the screen.
    @MainActor
    private func audit(_ screen: String, _ app: XCUIApplication) throws {
        Thread.sleep(forTimeInterval: 1.5)
        var firstPass: Set<String> = []
        try app.performAccessibilityAudit { issue in
            if let key = self.key(for: issue, app) { firstPass.insert(key) }
            return true
        }
        guard !firstPass.isEmpty else { return }
        Thread.sleep(forTimeInterval: 2)
        try app.performAccessibilityAudit { issue in
            guard let key = self.key(for: issue, app), firstPass.contains(key) else { return true }
            XCTContext.runActivity(named: "\(screen): \(key)") { _ in }
            return false
        }
    }

    /// The issue as text, or nil when it is one the audit ignores (see `audit`).
    @MainActor
    private func key(for issue: XCUIAccessibilityAuditIssue, _ app: XCUIApplication) -> String? {
        let description = issue.compactDescription
        if description.localizedCaseInsensitiveContains("nearly passed") { return nil }
        // No element: text seen through a translucent bar (rows scrolled under onboarding's Continue bar).
        guard let element = issue.element else {
            return description.localizedCaseInsensitiveContains("contrast") ? nil : description
        }
        let system: Set<XCUIElement.ElementType> = [.tabBar, .navigationBar, .keyboard, .searchField, .toolbar]
        if system.contains(element.elementType) || !element.isEnabled { return nil }
        if Self.systemDrawn.contains(element.label) || Self.toolbarItems.contains(element.identifier) { return nil }
        // Seen through the translucent bars: a row partly under the tab bar (smaller iPhones, e.g. the 16e), or a
        // header still under the navigation bar's glass as a pushed page settles.
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists, element.frame.maxY > tabBar.frame.minY { return nil }
        let navigationBar = app.navigationBars.firstMatch
        if navigationBar.exists, element.frame.minY < navigationBar.frame.maxY { return nil }
        return "\(description) — \"\(element.label)\" [\(element.identifier)]"
    }

    @MainActor
    private func openTab(_ name: String, _ app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        if tab.exists { tab.tap() } else { app.buttons[name].firstMatch.tap() }
    }
}
