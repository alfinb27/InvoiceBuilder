import Foundation

/// The free tier and the unlock (`spec/billing.md`).
public enum FreeTier {
    public static let limit = 15

    /// "Effective count" (`billing.md`, Free tier): the highest of every place the count is kept.
    public static func effectiveCount(local: Int, deviceMirror: Int, keychainMirror: Int, issuedInDatabase: Int) -> Int {
        max(local, deviceMirror, keychainMirror, issuedInDatabase)
    }

    public static func remaining(count: Int) -> Int { max(limit - count, 0) }
}

public enum EntitlementState: String, Hashable, Sendable, CaseIterable {
    case unknown, free, limitReached, purchasing, pending, unlocked
}

public enum EntitlementEvent: String, Hashable, Sendable, CaseIterable {
    case resolvedOwned, resolvedNotOwned, counted, purchaseStarted, purchasePending, purchased, purchaseCancelled,
         purchaseFailed, revoked
}

/// `billing.md`, Transitions.
public enum EntitlementMachine {
    public static func next(_ state: EntitlementState, _ event: EntitlementEvent, count: Int) -> EntitlementState {
        let byCount: EntitlementState = count >= FreeTier.limit ? .limitReached : .free
        switch (event, state) {
        case (.resolvedOwned, _), (.purchased, _):
            return .unlocked
        case (.resolvedNotOwned, .unknown), (.resolvedNotOwned, .unlocked),
             (.resolvedNotOwned, .free), (.resolvedNotOwned, .limitReached):
            return byCount
        case (.counted, .free), (.counted, .limitReached):
            return byCount
        case (.purchaseStarted, .free), (.purchaseStarted, .limitReached):
            return .purchasing
        case (.purchasePending, .purchasing):
            return .pending
        case (.purchaseCancelled, .purchasing), (.purchaseCancelled, .pending),
             (.purchaseFailed, .purchasing), (.purchaseFailed, .pending):
            return byCount
        case (.revoked, .unlocked):
            return byCount
        default:
            return state
        }
    }

    /// Issuing an invoice is allowed when unlocked or below the limit, in every state.
    public static func canIssueInvoice(_ state: EntitlementState, count: Int) -> Bool {
        state == .unlocked || count < FreeTier.limit
    }
}

/// What the app shows about the unlock: the state, the effective count and the store's price.
public struct EntitlementStatus: Hashable, Sendable {
    public var state: EntitlementState
    public var count: Int
    /// `Product.displayPrice`, once the store answered; never hard-coded (`billing.md`, Product).
    public var displayPrice: String?

    public init(state: EntitlementState, count: Int, displayPrice: String? = nil) {
        self.state = state
        self.count = count
        self.displayPrice = displayPrice
    }

    public var canIssueInvoice: Bool { EntitlementMachine.canIssueInvoice(state, count: count) }
    public var remaining: Int { FreeTier.remaining(count: count) }
    public var isUnlocked: Bool { state == .unlocked }
}

/// The unlock and the free-tier count behind one interface: `InvoiceBilling` implements it with StoreKit 2.
public protocol EntitlementService: Sendable {
    func observeStatus() -> AsyncStream<EntitlementStatus>
    /// Launch: cached entitlements, the updates listener, the product's price, the effective count.
    func start() async
    /// After an invoice was issued here or synced devices issued some (`billing.md`, Free tier).
    func refreshCount() async
    /// The purchase sheet; returns when it is done (purchased, pending, cancelled or failed).
    func purchase() async
    /// "Restore purchases" (`AppStore.sync()`).
    func restore() async
}

/// The three counts kept in the database (`billing.md`, Free tier); the Keychain mirror is the fourth.
public struct FreeTierCounts: Hashable, Sendable {
    /// `app_state.issued_invoice_count`.
    public var local: Int
    /// `device_state.free_counter_mirror`.
    public var deviceMirror: Int
    /// Every invoice ever issued, voided and tombstoned included (synced devices share it).
    public var issuedInDatabase: Int

    public init(local: Int, deviceMirror: Int, issuedInDatabase: Int) {
        self.local = local
        self.deviceMirror = deviceMirror
        self.issuedInDatabase = issuedInDatabase
    }
}

public protocol FreeTierRepository: Sendable {
    func fetchCounts() async throws -> FreeTierCounts
}
