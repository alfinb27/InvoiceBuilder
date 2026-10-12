import Foundation
import InvoiceCore
import InvoiceData
import Testing
@testable import InvoiceUI

/// Settings → Backup → Google Drive and the restore list (`spec/backup.md` §7), against the in-memory Drive.
@MainActor
@Suite("Google Drive backup")
struct DriveBackupTests {
    /// A seeded business whose dependencies back up to `drive`.
    static func session(_ country: SampleData.Country, drive: DemoCloudBackup) async throws -> Session {
        let dependencies = try AppDependencies.make(
            database: AppDatabase.inMemory(), time: .fixed(now: 1_789_800_000_000, today: TestEnvironment.today),
            ids: .random, cloudBackup: drive) // each "phone" its own device id
        let device = try await dependencies.deviceState.loadOrCreate(deviceName: "Test")
        let business = try await SampleData.seed(country, dependencies: dependencies, deviceID: device.id)
        let session = try Session(dependencies: dependencies, business: business, deviceID: device.id,
                                  pdfDirectory: TestEnvironment.pdfDirectory())
        session.autoBackup = dependencies.autoBackupRunner(deviceID: device.id, appVersion: "test")
        return session
    }

    static func model(_ session: Session) throws -> DriveBackupModel {
        DriveBackupModel(runner: try #require(session.autoBackup), store: session.dependencies.cloudBackupState,
                         time: session.dependencies.time)
    }

    @Test func connectingBacksUpAtOnceAndShowsTheAccount() async throws {
        let session = try await Self.session(.india, drive: DemoCloudBackup())
        let model = try Self.model(session)
        #expect(model.statusText == DriveBackupText.notConnected)

        await model.connect()
        #expect(model.isConnected)
        #expect(model.state.cloud.accountEmail == "you@example.com")
        #expect(model.statusText.hasPrefix("Last backup to Google Drive: today at "))
        #expect(model.state.errorMessage == nil)
        // §7.5: a Drive backup counts for the 30-day nudge too.
        for try await status in session.dependencies.backup.observeStatus() {
            #expect(status.lastBackupAt == 1_789_800_000_000)
            break
        }
    }

    @Test func aBackupFromAnotherPhoneRestoresHere() async throws {
        let drive = DemoCloudBackup()
        // The UK business backs up from one phone…
        let uk = try await Self.session(.uk, drive: drive)
        await try Self.model(uk).connect()

        // …and a new phone, still on the Welcome screen, restores it.
        let dependencies = try AppDependencies.make(
            database: AppDatabase.inMemory(), time: .fixed(now: 1_789_800_000_000, today: TestEnvironment.today),
            ids: .random, cloudBackup: drive)
        let device = try await dependencies.deviceState.loadOrCreate(deviceName: "New phone")
        let runner = try #require(dependencies.autoBackupRunner(deviceID: device.id, appVersion: "test"))
        let model = DriveBackupModel(runner: runner, store: dependencies.cloudBackupState, time: dependencies.time)
        var reloads = 0
        let backup = BackupViewModel(dependencies: dependencies, deviceID: device.id) { reloads += 1 }

        await model.showBackups() // signs in first
        #expect(model.state.showsBackups)
        let entries = try #require(model.state.backups)
        #expect(entries.count == 1)
        #expect(DriveBackupText.detail(entries[0]).hasPrefix("Thames Design Ltd"))

        let bytes = try #require(await model.download(entries[0]))
        backup.load(bytes)
        let pending = try #require(backup.state.pendingRestore)
        #expect(pending.preview.file.data.businesses.map(\.name) == ["Thames Design Ltd"])
        await backup.confirmRestore()
        #expect(reloads == 1)
        #expect(try await dependencies.businesses.fetchBusinesses().map(\.name) == ["Thames Design Ltd"])
        #expect(model.isConnected) // automatic backups stay on for this phone (§7.6)
    }

    @Test func stoppingKeepsTheFilesInDrive() async throws {
        let drive = DemoCloudBackup()
        let session = try await Self.session(.india, drive: drive)
        let model = try Self.model(session)
        await model.connect()
        await model.disconnect()
        #expect(!model.isConnected)
        await model.showBackups() // connecting again finds the same folder
        #expect(model.state.backups?.count == 1)
    }

    @Test func failuresReadInPlainWords() {
        #expect(DriveBackupText.failed(.quotaExceeded) == "Couldn't back up to Google Drive: your Google Drive is full.")
        #expect(DriveBackupText.failed(.signedOut).contains("signed out"))
        #expect(DriveBackupText.failed(.networkUnavailable).contains("no internet connection"))
    }

    @Test func theRestoreListSaysWhenWhereAndWhat() {
        let now: Int64 = 1_789_800_000_000
        let entry = CloudBackupEntry(id: "f", name: "n", deviceID: "d", deviceName: "Pixel 8", platform: "android",
                                     createdAt: now - 86_400_000, businesses: "Rao Traders", invoiceCount: 12,
                                     clientCount: 1)
        #expect(DriveBackupText.title(entry, now: now).hasPrefix("Yesterday at "))
        #expect(DriveBackupText.title(entry, now: now).hasSuffix(" · Pixel 8 (Android)"))
        #expect(DriveBackupText.detail(entry) == "Rao Traders · 12 invoices · 1 client")
    }
}
