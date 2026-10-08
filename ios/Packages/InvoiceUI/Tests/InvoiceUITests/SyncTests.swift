import Foundation
import InvoiceCore
import InvoiceData
import Testing
@testable import InvoiceUI

/// A sync service whose status the test sets.
final class FakeSyncService: SyncService, @unchecked Sendable {
    // @unchecked: tests drive it from the main actor only.
    private var status: SyncStatus
    private var continuations: [AsyncStream<SyncStatus>.Continuation] = []
    private(set) var enabledCalls: [Bool] = []
    private(set) var erased = false

    init(status: SyncStatus) {
        self.status = status
    }

    func set(_ status: SyncStatus) {
        self.status = status
        for continuation in continuations { continuation.yield(status) }
    }

    func observeStatus() -> AsyncStream<SyncStatus> {
        AsyncStream { continuation in
            continuation.yield(status)
            continuations.append(continuation)
        }
    }

    func setEnabled(_ enabled: Bool) async {
        enabledCalls.append(enabled)
    }

    func eraseLocalDataAndResume() async throws {
        erased = true
    }

    func syncNow() async {}

    func observeRemoteChanges() -> AsyncStream<Void> {
        AsyncStream { _ in }
    }
}

@MainActor
@Suite("Sync and numbering on several devices")
struct SyncTests {
    @Test func aDeviceWithoutASeriesChoosesOneThenIssues() async throws {
        let session = try await TestEnvironment.session(.india)
        // The seeded series belong to another device now (it was set up there and synced here).
        let series = try #require(try await firstValue(
            session.dependencies.numberingSeries.observeSeries(businessID: session.business.id)))
        for var other in series {
            other.ownerDeviceId = "another-device"
            try await session.dependencies.numberingSeries.save(other)
        }

        let model = DocumentViewModel(session: session, route: .new(.invoice, id: "new-invoice"))
        await model.load()
        let clients = try #require(try await firstValue(
            session.dependencies.clients.observeClients(businessID: session.business.id)))
        model.chooseClient(try #require(clients.first))
        let items = try #require(try await firstValue(
            session.dependencies.catalog.observeItems(businessID: session.business.id)))
        model.addItem(try #require(items.first))
        await model.flush()

        await model.requestIssue()
        let choice = try #require(model.state.seriesChoice)
        #expect(choice.ownFirstNumber == "INV/26-27/B0001")
        #expect(choice.others.count == 1 && choice.others[0].nextNumber == "INV/26-27/0001")
        #expect(!model.state.confirmingIssue)

        await model.startOwnSeries()
        #expect(model.state.seriesChoice == nil)
        #expect(model.state.confirmingIssue && model.state.numberPreview == "INV/26-27/B0001")
    }

    @Test func takingOverASeriesContinuesIt() async throws {
        let session = try await TestEnvironment.session(.india)
        let series = try #require(try await firstValue(
            session.dependencies.numberingSeries.observeSeries(businessID: session.business.id)))
        for var other in series {
            other.ownerDeviceId = "another-device"
            try await session.dependencies.numberingSeries.save(other)
        }
        let model = DocumentViewModel(session: session, route: .new(.invoice, id: "new-invoice"))
        await model.load()
        let items = try #require(try await firstValue(
            session.dependencies.catalog.observeItems(businessID: session.business.id)))
        model.addItem(try #require(items.first))
        await model.flush()
        await model.requestIssue()
        let option = try #require(model.state.seriesChoice?.others.first)
        await model.takeOver(seriesID: option.series.id)
        #expect(model.state.confirmingIssue && model.state.numberPreview == "INV/26-27/0001")
    }

    @Test func firstLaunchWaitsForICloudThenOnboards() async throws {
        let sync = FakeSyncService(status: .syncing)
        var dependencies = try TestEnvironment.dependencies()
        dependencies.sync = sync
        let model = AppModel(dependencies: dependencies)
        model.iCloudWait = .milliseconds(300)
        await model.start()
        guard case .onboarding = model.phase else {
            Issue.record("expected onboarding after the wait, got \(model.phase)")
            return
        }
        #expect(sync.enabledCalls == [true])
    }

    @Test func aBusinessArrivingFromICloudOpensInsteadOfOnboarding() async throws {
        let sync = FakeSyncService(status: .syncing)
        var dependencies = try TestEnvironment.dependencies()
        dependencies.sync = sync
        let model = AppModel(dependencies: dependencies)
        model.iCloudWait = .seconds(5)
        let device = try await dependencies.deviceState.loadOrCreate(deviceName: "Test")
        // Another device's business lands while this one waits.
        Task {
            try await Task.sleep(for: .milliseconds(200))
            _ = try await SampleData.seed(.uk, dependencies: dependencies, deviceID: "another-device")
        }
        await model.start()
        guard case .ready(let session) = model.phase else {
            Issue.record("expected the main shell, got \(model.phase)")
            return
        }
        #expect(session.business.name == "Thames Design Ltd")
        #expect(session.deviceID == device.id)
    }

    @Test func withoutSyncThereIsNoWait() async throws {
        let model = AppModel(dependencies: try TestEnvironment.dependencies())
        model.iCloudWait = .seconds(30)
        let started = ContinuousClock.now
        await model.start()
        #expect(ContinuousClock.now - started < .seconds(5))
        guard case .onboarding = model.phase else {
            Issue.record("expected onboarding")
            return
        }
    }

    @Test func syncPageStatus() async throws {
        let sync = FakeSyncService(status: .paused(.accountChanged))
        var dependencies = try TestEnvironment.dependencies()
        dependencies.sync = sync
        let model = SyncViewModel(dependencies: dependencies)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        while model.status == .unavailable { await Task.yield() }
        #expect(model.statusText == "Paused: a different iCloud account is signed in")
        #expect(model.isAvailable && model.isOn)

        await model.eraseAndResume()
        #expect(sync.erased)

        await model.setOn(false)
        #expect(sync.enabledCalls == [false])
    }
}
