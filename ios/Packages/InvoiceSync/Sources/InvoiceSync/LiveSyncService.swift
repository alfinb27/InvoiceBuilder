import CloudKit
import Foundation
import GRDB
import InvoiceCore
import InvoiceData
import SQLiteData
import Synchronization

/// iCloud sync for the app's database (`spec/sync.md`): SQLiteData's `SyncEngine` over the synced tables, with
/// account changes pausing sync instead of erasing data (§2).
public final class LiveSyncService: SyncService, @unchecked Sendable {
    // @unchecked: every mutable property is only touched on `state`'s lock.
    private let engine: SyncEngine
    private let deviceState: any DeviceStateRepository
    private let delegate: AccountDelegate
    private let state = Mutex(State())

    private struct State {
        var status: SyncStatus = .syncing
        var statusContinuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]
        var remoteContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]
        var poller: Task<Void, Never>?
        var wasFetching = false
    }

    /// Opens `database` for sync. The database must have been opened with `LiveSyncService.prepare(_:)` in its
    /// configuration, so SQLiteData's metadata database is attached to every connection.
    public init(database: AppDatabase, containerIdentifier: String, deviceState: any DeviceStateRepository,
                enabled: Bool) throws {
        let delegate = AccountDelegate()
        self.delegate = delegate
        self.deviceState = deviceState
        engine = try SyncEngine(
            for: database.writer,
            tables: SyncedBusiness.self, SyncedAsset.self, SyncedClient.self, SyncedCatalogItem.self,
            SyncedNumberingSeries.self, SyncedDocument.self, SyncedLineItem.self, SyncedTaxLine.self,
            SyncedPayment.self,
            containerIdentifier: containerIdentifier,
            startImmediately: enabled,
            delegate: delegate
        )
        delegate.onAccountChange = { [weak self] reason in self?.pause(reason) }
        if enabled { startPolling() } else { publish(.off) }
    }

    /// The connection setup sync needs: SQLiteData's metadata database on every connection.
    public static func prepare(_ configuration: inout Configuration, containerIdentifier: String) {
        configuration.prepareDatabase { db in
            try db.attachMetadatabase(containerIdentifier: containerIdentifier)
        }
    }

    // MARK: SyncService

    public func observeStatus() -> AsyncStream<SyncStatus> {
        AsyncStream { continuation in
            let id = UUID()
            let current = state.withLock { state in
                state.statusContinuations[id] = continuation
                return state.status
            }
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                _ = self?.state.withLock { $0.statusContinuations.removeValue(forKey: id) }
            }
        }
    }

    public func observeRemoteChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            state.withLock { $0.remoteContinuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                _ = self?.state.withLock { $0.remoteContinuations.removeValue(forKey: id) }
            }
        }
    }

    public func setEnabled(_ enabled: Bool) async {
        try? await deviceState.setSyncEnabled(enabled)
        if enabled {
            do {
                try await engine.start()
                startPolling()
                await syncNow()
            } catch {
                publish(.paused(.signedOut))
            }
        } else {
            engine.stop()
            stopPolling()
            publish(.off)
        }
    }

    public func eraseLocalDataAndResume() async throws {
        try await engine.deleteLocalData()
        try await engine.start()
        startPolling()
        await syncNow()
    }

    public func syncNow() async {
        guard engine.isRunning else { return }
        do {
            try await engine.syncChanges()
            publish(.upToDate)
        } catch let error as CKError {
            switch error.code {
            case .quotaExceeded: publish(.paused(.quotaExceeded))
            case .networkUnavailable, .networkFailure: publish(.paused(.networkUnavailable))
            case .notAuthenticated: publish(.paused(.signedOut))
            default: publish(.upToDate)
            }
        } catch {
            publish(.paused(.networkUnavailable))
        }
    }

    // MARK: Status

    private func pause(_ reason: SyncPauseReason) {
        engine.stop()
        stopPolling()
        publish(.paused(reason))
    }

    private func publish(_ status: SyncStatus) {
        let continuations = state.withLock { state in
            state.status = status
            return Array(state.statusContinuations.values)
        }
        for continuation in continuations { continuation.yield(status) }
    }

    /// The engine's activity, sampled once a second while it runs: `syncing` while it sends or fetches, then
    /// `upToDate`; a finished fetch tells `observeRemoteChanges` listeners (reminders, the duplicate check).
    private func startPolling() {
        let task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.sample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        state.withLock { state in
            state.poller?.cancel()
            state.poller = task
        }
    }

    private func stopPolling() {
        state.withLock { state in
            state.poller?.cancel()
            state.poller = nil
        }
    }

    private func sample() {
        let fetching = engine.isFetchingChanges
        let busy = engine.isSynchronizing
        let (finishedFetch, current, remotes) = state.withLock { state in
            let finished = state.wasFetching && !fetching
            state.wasFetching = fetching
            return (finished, state.status, Array(state.remoteContinuations.values))
        }
        if busy, current != .syncing {
            publish(.syncing)
        } else if !busy, current == .syncing {
            publish(.upToDate)
        }
        if finishedFetch { for continuation in remotes { continuation.yield(()) } }
    }
}

/// Keeps local data on sign-out or an account switch (SQLiteData's default would erase it) and reports the pause.
private final class AccountDelegate: SyncEngineDelegate, @unchecked Sendable {
    // @unchecked: `onAccountChange` is set once, before the engine can call back.
    var onAccountChange: (@Sendable (SyncPauseReason) -> Void)?

    func syncEngine(_ syncEngine: SyncEngine,
                    accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType) async {
        switch changeType {
        case .signOut: onAccountChange?(.signedOut)
        case .switchAccounts: onAccountChange?(.accountChanged)
        case .signIn: break
        @unknown default: onAccountChange?(.accountChanged)
        }
    }
}
