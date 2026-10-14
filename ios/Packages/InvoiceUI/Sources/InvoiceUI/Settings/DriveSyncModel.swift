import Foundation
import InvoiceCore
import Observation

/// Settings → Sync → Google Drive and Welcome → "Sync with Google Drive" (`spec/drive-sync.md` §1, §7, §9).
@MainActor @Observable
final class DriveSyncModel {
    struct State {
        var sync = DriveSyncState()
        var isWorking = false
        var errorMessage: String?
    }

    var state = State()

    private let engine: DriveSyncEngine
    private let store: any DriveSyncStore
    private let iCloud: any SyncService
    private let autoBackup: AutoBackupRunner?
    private let time: TimeSource
    /// After a pull that changed records (`sync.md` §5 runs: reminders, and a reload when a business arrived).
    private let onMerged: @MainActor (Int) async -> Void

    init(engine: DriveSyncEngine, store: any DriveSyncStore, iCloud: any SyncService, autoBackup: AutoBackupRunner?,
         time: TimeSource, onMerged: @escaping @MainActor (Int) async -> Void = { _ in }) {
        self.engine = engine
        self.store = store
        self.iCloud = iCloud
        self.autoBackup = autoBackup
        self.time = time
        self.onMerged = onMerged
    }

    var isOn: Bool { state.sync.isConnected }

    var statusText: String { DriveSyncText.status(state.sync, now: time.now()) }

    var hasError: Bool { isOn && state.sync.lastError != nil }

    func observe() async {
        do {
            for try await sync in store.observeDriveSyncState() { state.sync = sync }
        } catch {}
    }

    /// §1, §7: iCloud sync goes off on this device, Drive sync connects and merges, Drive backup comes on with it.
    func connect() async {
        await work {
            await iCloud.setEnabled(false)
            try await engine.connect()
            if let autoBackup, let backup = try? await autoBackupState(), !backup.isConnected {
                try? await autoBackup.connect()
            }
            await onMerged(1)
        }
    }

    func syncNow() async {
        await work {
            let changed = try await engine.syncNow()
            if changed > 0 { await onMerged(changed) }
        }
    }

    /// §7: the files stay in Drive.
    func disconnect() async {
        await work { try await engine.disconnect() }
    }

    func dismissError() {
        state.errorMessage = nil
    }

    private func autoBackupState() async throws -> CloudBackupState? {
        guard let store = store as? any CloudBackupStateStore else { return nil }
        return try await store.cloudBackupState()
    }

    private func work(_ body: () async throws -> Void) async {
        state.isWorking = true
        defer { state.isWorking = false }
        do {
            try await body()
        } catch CloudBackupError.cancelled {
            // The user closed Google's page: nothing to say.
        } catch {
            state.errorMessage = DriveSyncText.failed((error as? CloudBackupError) ?? .other)
        }
        if let sync = try? await store.driveSyncState() { state.sync = sync }
    }
}

/// What the Google Drive sync rows say (`spec/drive-sync.md` §9).
enum DriveSyncText {
    static let off = "Keep this phone in step with your other phones, iPhone or Android, through your own Google Drive."

    static func failed(_ error: CloudBackupError) -> String {
        switch error {
        case .signedOut: "Paused: you're signed out of Google Drive. Connect again to carry on."
        case .quotaExceeded: "Paused: your Google Drive is full."
        case .networkUnavailable: "Waiting for the network"
        case .cancelled, .other: "Couldn't sync with Google Drive. It will try again. If this keeps happening, update the app."
        }
    }

    static func status(_ state: DriveSyncState, now: Int64) -> String {
        guard state.isConnected else { return off }
        if let error = state.lastError { return failed(error) }
        guard let last = state.lastSyncAt else { return "Syncing…" }
        return "Up to date · synced \(DriveBackupText.when(last, now: now))"
    }
}
