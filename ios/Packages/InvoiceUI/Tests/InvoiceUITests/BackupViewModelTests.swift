import Foundation
import InvoiceCore
import InvoiceData
import Testing
@testable import InvoiceUI

@MainActor
@Suite("Backup")
struct BackupViewModelTests {
    @Test func exportWritesAFileAndOnlyACompletedSaveCounts() async throws {
        let session = try await TestEnvironment.session(.india)
        let model = BackupViewModel(dependencies: session.dependencies, deviceID: session.deviceID) {}

        let export = try #require(await model.prepareExport())
        #expect(export.fileName == "InvoiceBackup-2026-09-19.invoicebackup")
        let bytes = try Data(contentsOf: export.url)
        let preview = try BackupCodec.validate(bytes, appSchemaVersion: session.dependencies.backup.schemaVersion).get()
        #expect(preview.live.businesses == 1 && preview.live.clients > 0)

        await model.exportFinished(completed: false)
        var status = try await firstStatus(session.dependencies)
        #expect(status.lastBackupAt == nil)

        await model.exportFinished(completed: true)
        status = try await firstStatus(session.dependencies)
        #expect(status.lastBackupAt == 1_789_800_000_000)
    }

    @Test func aFileThatIsNotABackupShowsAnErrorAndChangesNothing() async throws {
        let session = try await TestEnvironment.session(.india)
        var restored = false
        let model = BackupViewModel(dependencies: session.dependencies, deviceID: session.deviceID) { restored = true }

        model.load(Data("hello".utf8))
        #expect(model.state.errorMessage == "This file isn't an InvoiceBuilder backup.")
        #expect(model.state.pendingRestore == nil)
        #expect(!restored)
    }

    @Test func restoringAsksFirstThenReplacesAndReloads() async throws {
        // A UK backup restored over an Indian business.
        let uk = try await TestEnvironment.session(.uk)
        let file = try await uk.dependencies.backup.makeBackup(app: .init(platform: "ios", version: "test"))

        let session = try await TestEnvironment.session(.india)
        var reloads = 0
        let model = BackupViewModel(dependencies: session.dependencies, deviceID: session.deviceID) { reloads += 1 }
        model.load(try BackupCodec.encode(file))
        let pending = try #require(model.state.pendingRestore)
        #expect(pending.preview.live.businesses == 1)
        #expect(reloads == 0)

        await model.confirmRestore()
        #expect(model.state.didRestore && model.state.pendingRestore == nil && model.state.errorMessage == nil)
        #expect(reloads == 1)
        let businesses = try await session.dependencies.businesses.fetchBusinesses()
        #expect(businesses.map(\.name) == ["Thames Design Ltd"])
    }

    @Test func restoringFromOnboardingOpensTheRestoredBusiness() async throws {
        let uk = try await TestEnvironment.session(.uk)
        let bytes = try BackupCodec.encode(try await uk.dependencies.backup.makeBackup(
            app: .init(platform: "ios", version: "test")))

        let app = AppModel(dependencies: try TestEnvironment.dependencies())
        await app.start()
        guard case .onboarding(let onboarding) = app.phase else {
            Issue.record("expected onboarding, got \(app.phase)")
            return
        }
        onboarding.backup.load(bytes)
        await onboarding.backup.confirmRestore()
        guard case .ready(let session) = app.phase else {
            Issue.record("expected the main shell, got \(app.phase)")
            return
        }
        #expect(session.business.name == "Thames Design Ltd")
    }

    @Test func lastBackupText() {
        #expect(BackupText.lastBackup(days: nil) == "Never backed up")
        #expect(BackupText.lastBackup(days: 0) == "Last backup: today")
        #expect(BackupText.lastBackup(days: 1) == "Last backup: yesterday")
        #expect(BackupText.lastBackup(days: 12) == "Last backup: 12 days ago")
    }

    @Test func openingAFileRoutesToTheBackupPage() async throws {
        let app = AppModel(dependencies: try TestEnvironment.dependencies(), seed: .uk)
        await app.start()
        guard case .ready(let session) = app.phase else {
            Issue.record("expected the main shell")
            return
        }
        let url = URL(fileURLWithPath: "/tmp/InvoiceBackup-2026-09-19.invoicebackup")
        await app.open(url)
        #expect(session.router.selectedTab == .settings)
        #expect(session.router.settings.selection == .backup)
        #expect(session.router.settings.incomingBackup == url)
    }

    private func firstStatus(_ dependencies: AppDependencies) async throws -> BackupStatus {
        var iterator = dependencies.backup.observeStatus().makeAsyncIterator()
        return try #require(try await iterator.next())
    }
}
