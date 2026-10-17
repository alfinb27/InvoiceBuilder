import Foundation
import InvoiceCore
import Observation
import UIKit

/// The app's top-level state: loading, then onboarding (no business yet) or the main shell.
@MainActor @Observable
public final class AppModel {
    public enum Phase {
        case loading
        /// First launch with sync on: waiting (up to 10 s, skippable) for a business from iCloud (`spec/sync.md` §2).
        case checkingICloud
        case onboarding(OnboardingViewModel)
        case ready(Session)
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    /// Automatic Google Drive backup for this device (`spec/backup.md` §7); nil without Drive in this build.
    public private(set) var autoBackup: AutoBackupRunner?
    /// Live sync through Google Drive (`spec/drive-sync.md`); nil without Drive in this build.
    public private(set) var driveSync: DriveSyncEngine?
    /// The push that follows a local write by 5 s (`spec/drive-sync.md` §4).
    private var pendingPush: Task<Void, Never>?
    private let dependencies: AppDependencies?
    private let seed: SampleData.Country?
    private var skipICloudCheck = false
    /// A backup opened while starting (`spec/backup.md` §6): opened once onboarding or the main shell shows.
    private var openedWhileStarting: URL?
    /// How long the first launch waits for iCloud.
    var iCloudWait: Duration = .seconds(10)

    public init(dependencies: AppDependencies, seed: SampleData.Country? = nil) {
        self.dependencies = dependencies
        self.seed = seed
    }

    /// A model that shows why the app could not open its database.
    public init(failure: any Error) {
        dependencies = nil
        seed = nil
        phase = .failed(String(describing: failure))
    }

    /// The model for this launch: the on-disk database, or an in-memory one for UI tests (`-inMemory`, `-seed IN`).
    public static func launch(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        do {
            let (dependencies, seed) = try AppDependencies.forLaunch(arguments: arguments)
            if seed == nil, !arguments.contains("-inMemory") { Diagnostics.shared.start() }
            let model = AppModel(dependencies: dependencies, seed: seed)
            if dependencies.cloudBackup != nil { AutoBackupScheduler.register(model) }
            return model
        } catch {
            return AppModel(failure: error)
        }
    }

    /// Loads this device and the active business (`spec/setup.md` §2).
    public func start() async {
        guard case .loading = phase, let dependencies else { return }
        skipICloudCheck = false
        do {
            var device = try await dependencies.deviceState.loadOrCreate(deviceName: UIDevice.current.name)
            if let seed, try await dependencies.businesses.fetchBusinesses().isEmpty {
                try await SampleData.seed(seed, dependencies: dependencies, deviceID: device.id)
                device = try await dependencies.deviceState.loadOrCreate(deviceName: UIDevice.current.name)
            }
            await dependencies.sync.setEnabled(device.preferences.isSyncEnabled)
            if autoBackup == nil {
                autoBackup = dependencies.autoBackupRunner(deviceID: device.id, appVersion: AppInfo.version)
            }
            if driveSync == nil { driveSync = dependencies.driveSyncEngine(deviceID: device.id) }
            // Never wait for the store at launch: offline, the price lookup waits for a network timeout. Until it
            // answers the state is `unknown`, which still lets anyone under the free limit issue (`spec/billing.md`).
            let entitlements = dependencies.entitlements
            Task { await entitlements.start() }
            var businesses = try await dependencies.businesses.fetchBusinesses()
            if businesses.isEmpty, await syncIsOn(dependencies.sync) {
                businesses = try await waitForICloud(dependencies)
            }
            if let business = BusinessSetup.activeBusiness(preferences: device.preferences, businesses: businesses) {
                phase = .ready(try makeSession(business: business, deviceID: device.id))
            } else {
                let deviceID = device.id
                phase = .onboarding(OnboardingViewModel(
                    dependencies: dependencies, deviceID: deviceID,
                    onRestored: { [weak self] in await self?.reload() },
                    onTryDemo: { [weak self] country in await self?.startDemo(country) },
                    autoBackup: autoBackup, driveSync: driveSync,
                    onFinished: { [weak self] in self?.finishOnboarding(with: $0, deviceID: deviceID) }))
            }
            if let url = openedWhileStarting {
                openedWhileStarting = nil
                await open(url)
            }
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Onboarding's "Try it with a sample business": a seeded business in an in-memory database, so nothing touches
    /// the real one. Its session's `reloadApp` leaves the demo for the real start.
    public func startDemo(_ country: SampleData.Country) async {
        do {
            let demo = try AppDependencies.inMemory()
            let device = try await demo.deviceState.loadOrCreate(deviceName: UIDevice.current.name)
            let business = try await SampleData.seed(country, dependencies: demo, deviceID: device.id)
            try await SampleData.addDemoDocuments(business: business, dependencies: demo, deviceID: device.id)
            let demoEntitlements = demo.entitlements
            Task { await demoEntitlements.start() }
            let session = try Session(dependencies: demo, business: business, deviceID: device.id)
            session.isDemo = true
            session.reloadApp = { [weak self] in await self?.reload() }
            phase = .ready(session)
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Skips the first-launch iCloud check.
    public func skipICloud() {
        skipICloudCheck = true
    }

    private func syncIsOn(_ sync: any SyncService) async -> Bool {
        for await status in sync.observeStatus() {
            return status != .off && status != .unavailable
        }
        return false
    }

    /// Polls for a business arriving from iCloud, four times a second, until one does, `iCloudWait` passes or the user
    /// skips.
    private func waitForICloud(_ dependencies: AppDependencies) async throws -> [Business] {
        phase = .checkingICloud
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: iCloudWait)
        while clock.now < deadline, !skipICloudCheck {
            let businesses = try await dependencies.businesses.fetchBusinesses()
            if !businesses.isEmpty { return businesses }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return try await dependencies.businesses.fetchBusinesses()
    }

    /// A `.invoicebackup` opened from another app (Files, Mail, AirDrop; `spec/backup.md` §6).
    public func open(_ url: URL) async {
        switch phase {
        case .onboarding(let onboarding):
            await onboarding.backup.open(url)
        case .ready(let session):
            session.router.selectedTab = .settings
            session.router.settings.restore(from: url)
        case .loading, .checkingICloud:
            openedWhileStarting = url
        case .failed:
            break
        }
    }

    /// Starts again from the database, as at launch: after a restore replaced the data (`spec/backup.md` §4
    /// step 5), the active business is chosen afresh and every screen is rebuilt.
    public func reload() async {
        phase = .loading
        await start()
    }

    private func finishOnboarding(with business: Business, deviceID: String) {
        do {
            phase = .ready(try makeSession(business: business, deviceID: deviceID))
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    private func makeSession(business: Business, deviceID: String) throws -> Session {
        guard let dependencies else { throw SpecLoadingError(path: "-", reason: "no dependencies") }
        let session = try Session(dependencies: dependencies, business: business, deviceID: deviceID)
        session.reloadApp = { [weak self] in await self?.reload() }
        session.autoBackup = autoBackup
        session.driveSync = driveSync
        return session
    }

    // MARK: Automatic cloud backup (spec/backup.md §7.2)

    var hasCloudBackup: Bool { dependencies?.cloudBackup != nil }

    /// A backup if one is due. Works in a background launch too, before any screen has loaded the device.
    func backUpIfDue() async {
        guard let dependencies, dependencies.cloudBackup != nil else { return }
        if autoBackup == nil, let device = try? await dependencies.deviceState.loadOrCreate(deviceName: UIDevice.current.name) {
            autoBackup = dependencies.autoBackupRunner(deviceID: device.id, appVersion: AppInfo.version)
        }
        _ = try? await autoBackup?.backUpIfDue() // the result is in the state; the next trigger tries again
    }

    // MARK: Live sync through Google Drive (spec/drive-sync.md §4, §6)

    /// One pull and push when Drive sync is on. Works in a background launch too.
    func syncDrive() async {
        guard let dependencies, dependencies.cloudBackup != nil else { return }
        if driveSync == nil, let device = try? await dependencies.deviceState.loadOrCreate(deviceName: UIDevice.current.name) {
            driveSync = dependencies.driveSyncEngine(deviceID: device.id)
        }
        guard let driveSync, let state = try? await dependencies.driveSyncStore.driveSyncState(), state.isConnected,
              state.lastError != .signedOut else { return }
        guard let changed = try? await driveSync.syncNow(), changed > 0 else { return }
        await driveSyncMerged()
    }

    /// `sync.md` §5 after a pull that changed records: reminders for the open business, or the app reloads when
    /// a business arrived during onboarding.
    func driveSyncMerged() async {
        switch phase {
        case .ready(let session): await session.reconcileReminders()
        case .onboarding:
            if let businesses = try? await dependencies?.businesses.fetchBusinesses(), !businesses.isEmpty {
                await reload()
            }
        case .loading, .checkingICloud, .failed: break
        }
    }

    /// While the app is in front: a sync now, then every 60 s and 5 s after each local write. Ends when the task
    /// is cancelled (the app left the foreground).
    func syncDriveWhileActive() async {
        guard let dependencies, dependencies.cloudBackup != nil else { return }
        await syncDrive()
        let store = dependencies.driveSyncStore
        let poll = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                await self.syncDrive()
            }
        }
        let watch = Task { @MainActor in
            var first = true
            do {
                for try await _ in store.observeLatestChange() {
                    if first { first = false; continue }
                    self.pendingPush?.cancel()
                    self.pendingPush = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(5))
                        if !Task.isCancelled { await self.syncDrive() }
                    }
                }
            } catch {}
        }
        await withTaskCancellationHandler {
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
        } onCancel: {
            poll.cancel()
            watch.cancel()
        }
        pendingPush?.cancel()
    }
}
