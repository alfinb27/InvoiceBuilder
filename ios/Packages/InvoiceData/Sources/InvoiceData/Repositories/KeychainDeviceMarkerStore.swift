import Foundation
import InvoiceCore
import Security

/// The device marker in the Keychain (`spec/setup.md` §2, ADR-0019): `…AfterFirstUnlockThisDeviceOnly` and not
/// synchronised, so an iCloud or encrypted backup restores it only onto this same device, never a new one. Android:
/// a file in `noBackupFilesDir`.
public struct KeychainDeviceMarkerStore: DeviceMarkerStore {
    static let account = "invoicebuilder.deviceID"
    let service: String

    public init(service: String = "app.invoicebuilder.device") {
        self.service = service
    }

    public func read() -> DeviceMarker {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess:
            guard let data = item as? Data else { return .unreadable }
            return .found(String(decoding: data, as: UTF8.self))
        case errSecItemNotFound:
            return .missing
        default:
            return .unreadable // e.g. errSecInteractionNotAllowed before the first unlock: never change the id for it
        }
    }

    @discardableResult
    public func write(_ id: String) -> Bool {
        let data = Data(id.utf8)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: Self.account, kSecAttrSynchronizable as String: false]
    }
}
