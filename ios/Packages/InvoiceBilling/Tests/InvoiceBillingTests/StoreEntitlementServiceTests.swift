import Foundation
import InvoiceCore
import Synchronization
import Testing
@testable import InvoiceBilling

final class FakeStore: StoreClient {
    private let shared = Mutex(Shared())

    private struct Shared {
        var owned = false
        var outcome: PurchaseOutcome = .purchased
        var price: String? = "₹299.00"
        var syncs = 0
        var continuation: AsyncStream<OwnershipChange>.Continuation?
    }

    init(owned: Bool = false, outcome: PurchaseOutcome = .purchased) {
        shared.withLock {
            $0.owned = owned
            $0.outcome = outcome
        }
    }

    var syncs: Int { shared.withLock { $0.syncs } }
    func setOwned(_ owned: Bool) { shared.withLock { $0.owned = owned } }
    func setOutcome(_ outcome: PurchaseOutcome) { shared.withLock { $0.outcome = outcome } }

    /// A transaction update arriving from outside (refund, Ask to Buy approved, another device).
    func send(_ change: OwnershipChange) {
        let continuation = shared.withLock { shared in
            shared.owned = change == .owned
            return shared.continuation
        }
        continuation?.yield(change)
    }

    func displayPrice(productID: String) async -> String? { shared.withLock { $0.price } }
    func owns(productID: String) async -> Bool { shared.withLock { $0.owned } }

    func purchase(productID: String) async -> PurchaseOutcome {
        shared.withLock { shared in
            if shared.outcome == .purchased { shared.owned = true }
            return shared.outcome
        }
    }

    func updates(productID: String) -> AsyncStream<OwnershipChange> {
        AsyncStream { continuation in shared.withLock { $0.continuation = continuation } }
    }

    func sync() async throws { shared.withLock { $0.syncs += 1 } }
}

final class MemoryMirror: CounterMirror {
    private let value: Mutex<Int>
    init(_ value: Int = 0) { self.value = Mutex(value) }
    func read() -> Int { value.withLock { $0 } }
    func raise(to count: Int) { value.withLock { $0 = max($0, count) } }
}

final class FakeCounts: FreeTierRepository {
    private let counts: Mutex<FreeTierCounts>
    init(_ counts: FreeTierCounts) { self.counts = Mutex(counts) }
    func set(_ counts: FreeTierCounts) { self.counts.withLock { $0 = counts } }
    func fetchCounts() async throws -> FreeTierCounts { counts.withLock { $0 } }
}

@Suite("Entitlements")
struct StoreEntitlementServiceTests {
    static func counts(_ local: Int, mirror: Int = 0, database: Int? = nil) -> FakeCounts {
        FakeCounts(FreeTierCounts(local: local, deviceMirror: mirror, issuedInDatabase: database ?? local))
    }

    @Test func productIDFollowsTheBundleID() {
        #expect(StoreEntitlementService.productID(bundleID: "app.invoicebuilder.invoices")
                == "app.invoicebuilder.invoices.unlimited_invoices")
    }

    @Test func launchResolvesFromTheStoreAndShowsThePrice() async {
        let service = StoreEntitlementService(productID: "p", store: FakeStore(owned: false), counts: Self.counts(4),
                                              mirror: MemoryMirror())
        await service.start()
        #expect(service.status == EntitlementStatus(state: .free, count: 4, displayPrice: "₹299.00"))
        #expect(service.status.remaining == 11 && service.status.canIssueInvoice)

        let owned = StoreEntitlementService(productID: "p", store: FakeStore(owned: true), counts: Self.counts(40),
                                            mirror: MemoryMirror())
        await owned.start()
        #expect(owned.status.state == .unlocked && owned.status.canIssueInvoice)
    }

    @Test func theHighestCountWins() async {
        // A reinstall emptied the database counter, but the Keychain remembers 15.
        let service = StoreEntitlementService(productID: "p", store: FakeStore(), counts: Self.counts(0, database: 2),
                                              mirror: MemoryMirror(15))
        await service.start()
        #expect(service.status.state == .limitReached && !service.status.canIssueInvoice)
    }

    @Test func issuingTheFifteenthInvoiceReachesTheLimitAndRaisesTheMirror() async {
        let counts = Self.counts(14)
        let mirror = MemoryMirror()
        let service = StoreEntitlementService(productID: "p", store: FakeStore(), counts: counts, mirror: mirror)
        await service.start()
        #expect(service.status.state == .free)
        counts.set(FreeTierCounts(local: 15, deviceMirror: 15, issuedInDatabase: 15))
        await service.refreshCount()
        #expect(service.status.state == .limitReached && mirror.read() == 15)
    }

    @Test func buyingAtTheLimitUnlocks() async {
        let service = StoreEntitlementService(productID: "p", store: FakeStore(), counts: Self.counts(15),
                                              mirror: MemoryMirror())
        await service.start()
        await service.purchase()
        #expect(service.status.state == .unlocked && service.status.canIssueInvoice)
    }

    @Test func cancellingGoesBackToTheLimit() async {
        let service = StoreEntitlementService(productID: "p", store: FakeStore(outcome: .cancelled),
                                              counts: Self.counts(15), mirror: MemoryMirror())
        await service.start()
        await service.purchase()
        #expect(service.status.state == .limitReached)
    }

    @Test func askToBuyWaitsForApproval() async throws {
        let store = FakeStore(outcome: .pending)
        let service = StoreEntitlementService(productID: "p", store: store, counts: Self.counts(15),
                                              mirror: MemoryMirror())
        await service.start()
        await service.purchase()
        #expect(service.status.state == .pending && !service.status.canIssueInvoice)

        var statuses = service.observeStatus().makeAsyncIterator()
        _ = await statuses.next() // current
        store.send(.owned) // the parent approved
        #expect(await statuses.next()?.state == .unlocked)
    }

    @Test func aRefundRevokes() async throws {
        let store = FakeStore(owned: true)
        let service = StoreEntitlementService(productID: "p", store: store, counts: Self.counts(20),
                                              mirror: MemoryMirror())
        await service.start()
        #expect(service.status.state == .unlocked)
        var statuses = service.observeStatus().makeAsyncIterator()
        _ = await statuses.next()
        store.send(.revoked)
        #expect(await statuses.next()?.state == .limitReached)
    }

    @Test func restoreSyncsAndUnlocksWhatWasBoughtElsewhere() async {
        let store = FakeStore(owned: false)
        let service = StoreEntitlementService(productID: "p", store: store, counts: Self.counts(15),
                                              mirror: MemoryMirror())
        await service.start()
        store.setOwned(true) // bought on another device; `AppStore.sync()` brings it here
        await service.restore()
        #expect(store.syncs == 1 && service.status.state == .unlocked)
    }

    @Test func buyingWhileUnlockedDoesNothing() async {
        let store = FakeStore(owned: true, outcome: .failed)
        let service = StoreEntitlementService(productID: "p", store: store, counts: Self.counts(3),
                                              mirror: MemoryMirror())
        await service.start()
        await service.purchase()
        #expect(service.status.state == .unlocked)
    }
}
