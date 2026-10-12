import Foundation
import InvoiceCore
import Synchronization

/// What the entitlement service needs from the store; `StoreKitClient` implements it with StoreKit 2.
public protocol StoreClient: Sendable {
    /// The localised price, or nil when the store cannot be reached or the product is missing.
    func displayPrice(productID: String) async -> String?
    /// Whether a verified, unrevoked transaction for the product is among the current entitlements.
    func owns(productID: String) async -> Bool
    func purchase(productID: String) async -> PurchaseOutcome
    /// Verified transaction changes for the product, for the app's lifetime (refunds, Ask to Buy approvals,
    /// purchases made on another device).
    func updates(productID: String) -> AsyncStream<OwnershipChange>
    /// "Restore purchases": `AppStore.sync()`.
    func sync() async throws
}

public enum PurchaseOutcome: Hashable, Sendable {
    case purchased, pending, cancelled, failed
}

public enum OwnershipChange: Hashable, Sendable {
    case owned, revoked
}

/// The free-tier counter mirrored outside the database (iOS: the Keychain), best effort.
public protocol CounterMirror: Sendable {
    func read() -> Int
    /// Raises the stored value to `count`; never lowers it.
    func raise(to count: Int)
}

/// `spec/billing.md`: the state machine driven by the store, with the effective count from every source.
public final class StoreEntitlementService: EntitlementService, Sendable {
    public let productID: String
    private let store: any StoreClient
    private let counts: any FreeTierRepository
    private let mirror: any CounterMirror
    private let state = Mutex(Shared())

    private struct Shared {
        var status = EntitlementStatus(state: .unknown, count: 0)
        var continuations: [UUID: AsyncStream<EntitlementStatus>.Continuation] = [:]
        var listener: Task<Void, Never>?
    }

    public init(productID: String, store: any StoreClient, counts: any FreeTierRepository,
                mirror: any CounterMirror) {
        self.productID = productID
        self.store = store
        self.counts = counts
        self.mirror = mirror
    }

    deinit {
        state.withLock { $0.listener?.cancel() }
    }

    /// `<bundle id>.unlimited_invoices` (`billing.md`, Product).
    public static func productID(bundleID: String) -> String {
        "\(bundleID).unlimited_invoices"
    }

    public func observeStatus() -> AsyncStream<EntitlementStatus> {
        AsyncStream { continuation in
            let id = UUID()
            let current = state.withLock { shared in
                shared.continuations[id] = continuation
                return shared.status
            }
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                _ = self?.state.withLock { $0.continuations.removeValue(forKey: id) }
            }
        }
    }

    public var status: EntitlementStatus { state.withLock { $0.status } }

    public func start() async {
        let count = await effectiveCount()
        update(count: count, price: nil)
        startListening()
        let owned = await store.owns(productID: productID)
        apply(owned ? .resolvedOwned : .resolvedNotOwned, count: count)
        if let price = await store.displayPrice(productID: productID) { update(count: count, price: price) }
    }

    public func refreshCount() async {
        let count = await effectiveCount()
        mirror.raise(to: count)
        apply(.counted, count: count)
    }

    public func purchase() async {
        let count = await effectiveCount()
        apply(.purchaseStarted, count: count)
        guard status.state == .purchasing else { return }
        switch await store.purchase(productID: productID) {
        case .purchased: apply(.purchased, count: count)
        case .pending: apply(.purchasePending, count: count)
        case .cancelled: apply(.purchaseCancelled, count: count)
        case .failed: apply(.purchaseFailed, count: count)
        }
    }

    public func restore() async {
        let count = await effectiveCount()
        try? await store.sync()
        let owned = await store.owns(productID: productID)
        apply(owned ? .resolvedOwned : .resolvedNotOwned, count: count)
    }

    // MARK: Internals

    private func effectiveCount() async -> Int {
        let stored = (try? await counts.fetchCounts()) ?? FreeTierCounts(local: 0, deviceMirror: 0, issuedInDatabase: 0)
        return FreeTier.effectiveCount(local: stored.local, deviceMirror: stored.deviceMirror,
                                       keychainMirror: mirror.read(), issuedInDatabase: stored.issuedInDatabase)
    }

    private func startListening() {
        let updates = store.updates(productID: productID)
        let task = Task { [weak self] in
            for await change in updates {
                guard let self else { return }
                let count = await self.effectiveCount()
                self.apply(change == .owned ? .purchased : .revoked, count: count)
            }
        }
        state.withLock { shared in
            shared.listener?.cancel()
            shared.listener = task
        }
    }

    private func apply(_ event: EntitlementEvent, count: Int) {
        let (status, continuations) = state.withLock { shared in
            shared.status.state = EntitlementMachine.next(shared.status.state, event, count: count)
            shared.status.count = count
            return (shared.status, Array(shared.continuations.values))
        }
        for continuation in continuations { continuation.yield(status) }
    }

    private func update(count: Int, price: String?) {
        let (status, continuations) = state.withLock { shared in
            shared.status.count = count
            if let price { shared.status.displayPrice = price }
            return (shared.status, Array(shared.continuations.values))
        }
        for continuation in continuations { continuation.yield(status) }
    }
}

/// No store (simulator UI tests, previews): nothing is owned, nothing can be bought, no price.
public struct UnavailableStoreClient: StoreClient {
    public init() {}
    public func displayPrice(productID: String) async -> String? { nil }
    public func owns(productID: String) async -> Bool { false }
    public func purchase(productID: String) async -> PurchaseOutcome { .failed }
    public func updates(productID: String) -> AsyncStream<OwnershipChange> { AsyncStream { _ in } }
    public func sync() async throws {}
}

/// A mirror that lives as long as the process (tests, in-memory launches).
public final class MemoryCounterMirror: CounterMirror {
    private let value = Mutex(0)
    public init() {}
    public func read() -> Int { value.withLock { $0 } }
    public func raise(to count: Int) { value.withLock { $0 = max($0, count) } }
}
