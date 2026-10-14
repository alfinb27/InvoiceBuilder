import Foundation
import InvoiceCore
import InvoiceData
import Testing
@testable import InvoiceUI

/// Settings → Sync → Google Drive and Welcome → "Sync with Google Drive" (`spec/drive-sync.md`), against the
/// in-memory Drive.
@MainActor
@Suite("Google Drive sync")
struct DriveSyncModelTests {
    static func model(_ dependencies: AppDependencies, deviceID: String, autoBackup: AutoBackupRunner? = nil,
                      onMerged: @escaping @MainActor (Int) async -> Void = { _ in }) throws -> DriveSyncModel {
        DriveSyncModel(engine: try #require(dependencies.driveSyncEngine(deviceID: deviceID)),
                       store: dependencies.driveSyncStore, iCloud: dependencies.sync, autoBackup: autoBackup,
                       time: dependencies.time, onMerged: onMerged)
    }

    @Test func connectingSyncsAndTurnsDriveBackupOn() async throws {
        let drive = DemoCloudBackup()
        let session = try await DriveBackupTests.session(.india, drive: drive)
        let model = try Self.model(session.dependencies, deviceID: session.deviceID, autoBackup: session.autoBackup)
        #expect(model.statusText == DriveSyncText.off)

        await model.connect()
        #expect(model.isOn)
        #expect(model.state.errorMessage == nil)
        #expect(model.statusText.hasPrefix("Up to date · synced today at "))
        #expect(try await session.dependencies.cloudBackupState.cloudBackupState().isConnected)
        let files = try await drive.syncEntries(folderID: drive.syncFolder(knownID: nil))
        #expect(files.contains { $0.kind == .changes && $0.deviceID == session.deviceID && $0.seq == 1 })

        await model.disconnect()
        #expect(!model.isOn)
    }

    @Test func aNewPhoneJoiningGetsTheBusiness() async throws {
        let drive = DemoCloudBackup()
        let india = try await DriveBackupTests.session(.india, drive: drive)
        await try Self.model(india.dependencies, deviceID: india.deviceID).connect()

        let dependencies = try AppDependencies.make(
            database: AppDatabase.inMemory(), time: .fixed(now: 1_789_800_000_000, today: TestEnvironment.today),
            ids: .random, cloudBackup: drive)
        let device = try await dependencies.deviceState.loadOrCreate(deviceName: "New phone")
        var merged = 0
        let model = try Self.model(dependencies, deviceID: device.id) { merged += $0 }
        await model.connect()
        #expect(merged > 0)
        let businesses = try await dependencies.businesses.fetchBusinesses()
        #expect(businesses.map(\.name) == [india.business.name])
    }
}
