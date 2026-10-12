import Foundation

/// What Settings shows about iCloud sync (`spec/sync.md` §2).
public enum SyncStatus: Hashable, Sendable {
    /// Turned off on this device.
    case off
    case upToDate
    case syncing
    case paused(SyncPauseReason)
    /// This build or device cannot sync (no iCloud container, or not an Apple device).
    case unavailable
}

public enum SyncPauseReason: String, Hashable, Sendable {
    case signedOut
    /// The iCloud account changed; local data stays until the user decides (§2).
    case accountChanged
    case quotaExceeded
    case networkUnavailable
}

/// iCloud sync behind one interface (ADR-0015): `InvoiceSync` implements it with SQLiteData; everything else, and
/// every test, uses `UnavailableSyncService` or a fake.
public protocol SyncService: Sendable {
    func observeStatus() -> AsyncStream<SyncStatus>
    /// Turns sync on or off for this device; local data is always kept.
    func setEnabled(_ enabled: Bool) async
    /// §2 account change: erase this device's synced data and start again with the current account. The caller
    /// writes a safety snapshot first.
    func eraseLocalDataAndResume() async throws
    /// Fetches and sends now; returns when the round trip is done (or failed).
    func syncNow() async
    /// Called after each completed sync with changes from another device (§5).
    func observeRemoteChanges() -> AsyncStream<Void>
}

/// A build without iCloud: status `unavailable`, every call a no-op.
public struct UnavailableSyncService: SyncService {
    public init() {}

    public func observeStatus() -> AsyncStream<SyncStatus> {
        AsyncStream { continuation in
            continuation.yield(.unavailable)
            continuation.finish()
        }
    }

    public func setEnabled(_ enabled: Bool) async {}
    public func eraseLocalDataAndResume() async throws {}
    public func syncNow() async {}

    public func observeRemoteChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
