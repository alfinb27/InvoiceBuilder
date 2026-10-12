import Foundation
import Synchronization

/// What a device knows about its own id outside the database (`spec/setup.md` §2, ADR-0019).
public enum DeviceMarker: Hashable, Sendable {
    case found(String)
    /// Nothing stored: a first launch, or a database copied from another device by an OS backup.
    case missing
    /// It could not be read right now (a locked device, an I/O error): never a reason to change the id.
    case unreadable
}

/// Where the marker lives: somewhere an OS backup never carries to another device (iOS: a Keychain item, this device
/// only). Android: `DeviceMarkerStore` over `noBackupFilesDir`.
public protocol DeviceMarkerStore: Sendable {
    func read() -> DeviceMarker
    /// False when it could not be stored: the caller then keeps the id it has, rather than replacing it on every
    /// launch because the marker never sticks.
    @discardableResult func write(_ id: String) -> Bool
}

/// Whether this database's `device_state` row belongs to this device (`spec/setup.md` §2).
public enum DeviceIdentity {
    public enum Action: Hashable, Sendable {
        /// No row yet: create it, then write the marker.
        case create
        /// The row is this device's (or the marker can't be read right now).
        case keep
        /// The database was copied from another device: the row takes a new id, then the marker is written.
        case replace
    }

    public static func check(rowID: String?, marker: DeviceMarker) -> Action {
        guard let rowID else { return .create }
        switch marker {
        case .found(let id): return id == rowID ? .keep : .replace
        case .missing: return .replace
        case .unreadable: return .keep
        }
    }
}

/// A marker that lives as long as the process (tests, previews, in-memory databases).
public final class InMemoryDeviceMarkerStore: DeviceMarkerStore {
    private let value: Mutex<DeviceMarker>
    /// Tests: false makes every write fail, as a Keychain that refuses the item would.
    public let writesSucceed: Bool

    public init(_ marker: DeviceMarker = .missing, writesSucceed: Bool = true) {
        value = Mutex(marker)
        self.writesSucceed = writesSucceed
    }

    public func read() -> DeviceMarker { value.withLock { $0 } }

    @discardableResult
    public func write(_ id: String) -> Bool {
        guard writesSucceed else { return false }
        value.withLock { $0 = .found(id) }
        return true
    }
    /// Tests: what the next read returns (`.missing` = a database restored onto another device).
    public func set(_ marker: DeviceMarker) { value.withLock { $0 = marker } }
}
