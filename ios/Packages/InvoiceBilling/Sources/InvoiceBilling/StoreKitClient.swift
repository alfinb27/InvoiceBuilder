import Foundation
import Security
import StoreKit

/// StoreKit 2 (`spec/billing.md`, Platform rules — iOS): verified transactions only, revocations honoured, every
/// verified transaction finished after the state is updated.
public struct StoreKitClient: StoreClient {
    public init() {}

    public func displayPrice(productID: String) async -> String? {
        try? await Product.products(for: [productID]).first?.displayPrice
    }

    public func owns(productID: String) async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == productID,
               transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    public func purchase(productID: String) async -> PurchaseOutcome {
        guard let product = try? await Product.products(for: [productID]).first else { return .failed }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                return transaction.revocationDate == nil ? .purchased : .failed
            case .success(.unverified):
                return .failed
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    public func updates(productID: String) -> AsyncStream<OwnershipChange> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    guard case .verified(let transaction) = result, transaction.productID == productID else {
                        continue
                    }
                    continuation.yield(transaction.revocationDate == nil ? .owned : .revoked)
                    await transaction.finish()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func sync() async throws {
        try await AppStore.sync()
    }
}

/// The free-tier counter in the Keychain (`invoicebuilder.freeCounter`, this device only, not synchronised), so a
/// reinstall usually keeps it (best effort, `spec/billing.md`).
public struct KeychainCounterMirror: CounterMirror {
    static let account = "invoicebuilder.freeCounter"
    let service: String

    public init(service: String = "app.invoicebuilder.billing") {
        self.service = service
    }

    public func read() -> Int {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let value = Int(String(decoding: data, as: UTF8.self)) else { return 0 }
        return value
    }

    public func raise(to count: Int) {
        guard count > read() else { return }
        let data = Data(String(count).utf8)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: Self.account, kSecAttrSynchronizable as String: false]
    }
}
