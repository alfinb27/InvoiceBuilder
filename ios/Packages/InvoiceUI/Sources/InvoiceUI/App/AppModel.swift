import Foundation
import InvoiceCore
import Observation
import UIKit

/// The app's top-level state: loading, then onboarding (no business yet) or the main shell.
@MainActor @Observable
public final class AppModel {
    public enum Phase {
        case loading
        case onboarding(OnboardingViewModel)
        case ready(Session)
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    private let dependencies: AppDependencies?
    private let seed: SampleData.Country?

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
        do {
            var device = try await dependencies.deviceState.loadOrCreate(deviceName: UIDevice.current.name)
            if let seed, try await dependencies.businesses.fetchBusinesses().isEmpty {
                try await SampleData.seed(seed, dependencies: dependencies, deviceID: device.id)
                device = try await dependencies.deviceState.loadOrCreate(deviceName: UIDevice.current.name)
            }
            let businesses = try await dependencies.businesses.fetchBusinesses()
            if let business = BusinessSetup.activeBusiness(preferences: device.preferences, businesses: businesses) {
                phase = .ready(try Session(dependencies: dependencies, business: business, deviceID: device.id))
            } else {
                let deviceID = device.id
                phase = .onboarding(OnboardingViewModel(dependencies: dependencies, deviceID: deviceID) { [weak self] in
                    self?.finishOnboarding(with: $0, deviceID: deviceID)
                })
            }
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    private func finishOnboarding(with business: Business, deviceID: String) {
        guard let dependencies else { return }
        do {
            phase = .ready(try Session(dependencies: dependencies, business: business, deviceID: deviceID))
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}
