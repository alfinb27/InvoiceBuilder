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
    private let dependencies: AppDependencies?
    private let seed: SampleData.Country?
    private var skipICloudCheck = false
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
            return AppModel(dependencies: dependencies, seed: seed)
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
                    onFinished: { [weak self] in self?.finishOnboarding(with: $0, deviceID: deviceID) }))
            }
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
        case .loading, .checkingICloud, .failed:
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
        return session
    }
}
