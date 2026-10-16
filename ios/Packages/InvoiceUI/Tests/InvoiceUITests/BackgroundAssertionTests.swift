import Testing
import UIKit
@testable import InvoiceUI

/// The leaving-the-app backup's background task (issue #33): it must end exactly once, also when iOS expires it,
/// or iOS terminates the app.
@MainActor
@Suite("Background assertion")
struct BackgroundAssertionTests {
    @MainActor
    final class FakeApplication {
        var expiry: (@MainActor @Sendable () -> Void)?
        var ended: [UIBackgroundTaskIdentifier] = []

        func assertion() -> BackgroundAssertion {
            BackgroundAssertion(name: "drive-backup", begin: { _, expiry in
                self.expiry = expiry
                return UIBackgroundTaskIdentifier(rawValue: 7)
            }, end: { self.ended.append($0) })
        }
    }

    @Test func finishedWorkEndsTheTaskOnce() {
        let application = FakeApplication()
        let assertion = application.assertion()
        assertion.end()
        assertion.end()
        #expect(application.ended == [UIBackgroundTaskIdentifier(rawValue: 7)])
    }

    @Test func whenTimeRunsOutTheWorkIsCancelledAndTheTaskEnds() {
        let application = FakeApplication()
        let assertion = application.assertion()
        var cancelled = false
        assertion.onExpiry = { cancelled = true }
        application.expiry?()
        #expect(cancelled && application.ended.count == 1)
        assertion.end() // the cancelled work finishing later changes nothing
        #expect(application.ended.count == 1)
    }
}
