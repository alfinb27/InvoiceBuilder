import Foundation
import InvoiceCore
import Testing
import UserNotifications
@testable import InvoiceUI

/// Records what `ReminderReconciler` would have scheduled, without touching the real OS notification center
/// (`NotificationScheduling`'s whole reason for existing — see its doc comment). `@unchecked Sendable`: every test
/// here drives it serially from the main actor, never concurrently.
final class FakeNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    var status: UNAuthorizationStatus = .authorized
    private(set) var added: [UNNotificationRequest] = []
    private(set) var removeAllCount = 0
    private(set) var requestedAuthorization = false

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async { requestedAuthorization = true }
    func removeAllPending() {
        removeAllCount += 1
        added = []
    }
    func add(_ request: UNNotificationRequest) async { added.append(request) }
}

@MainActor
@Suite("Reminders")
struct ReminderReconcilerTests {
    /// Issues an invoice for Rao Traders due `daysFromToday` from now (negative = already overdue).
    func issuedInvoice(_ session: Session, id: String, daysFromToday: Int) async throws -> Document {
        let model = DocumentViewModel(session: session, route: .new(.invoice, id: id), autosaveDelay: .zero)
        await model.load()
        let clients = try await firstValue(session.dependencies.clients.observeClients(businessID: session.business.id))
        model.chooseClient(try #require(clients?.first { $0.name == "Rao Traders" }))
        let items = try await firstValue(session.dependencies.catalog.observeItems(businessID: session.business.id))
        model.addItem(try #require(items?.first { $0.name == "Website development" }))
        model.setDueDate(session.today.adding(days: daysFromToday))
        await model.requestIssue()
        await model.confirmIssue()
        return model.state.document
    }

    @Test func reconcileSchedulesOverdueInvoicesAndSkipsPaidOnes() async throws {
        let scheduler = FakeNotificationScheduler()
        let session = try await TestEnvironment.session(notifications: scheduler)
        var withDefault = session.business
        withDefault.reminderDaysAfterDue = 3
        try await session.dependencies.businesses.save(withDefault)

        // Due 2 days ago + 3 days: the reminder is tomorrow.
        let overdue = try await issuedInvoice(session, id: "doc-overdue", daysFromToday: -2)
        let paid = try await issuedInvoice(session, id: "doc-paid", daysFromToday: -2)
        try await session.dependencies.paymentService.recordPayment(
            documentID: paid.id, amountMinor: paid.totals.totalMinor, date: session.today, method: .cash,
            reference: nil, note: nil)

        await session.reconcileReminders()
        #expect(scheduler.requestedAuthorization == false) // already authorized
        #expect(scheduler.added.map(\.identifier) == ["reminder-\(overdue.id)"])
    }

    @Test func reconcileAsksForAuthorizationOnlyWhenNotDetermined() async throws {
        let scheduler = FakeNotificationScheduler()
        scheduler.status = .notDetermined
        let session = try await TestEnvironment.session(notifications: scheduler)
        await session.reconcileReminders()
        #expect(scheduler.requestedAuthorization)
    }

    @Test func reconcileClearsPendingWithoutSchedulingWhenNotAuthorized() async throws {
        let scheduler = FakeNotificationScheduler()
        scheduler.status = .denied
        let session = try await TestEnvironment.session(notifications: scheduler)
        var withDefault = session.business
        withDefault.reminderDaysAfterDue = 3
        try await session.dependencies.businesses.save(withDefault)
        _ = try await issuedInvoice(session, id: "doc-overdue", daysFromToday: -2)

        await session.reconcileReminders()
        #expect(scheduler.added.isEmpty && scheduler.removeAllCount >= 1)
    }

    @Test func reconcileReplacesRatherThanAccumulates() async throws {
        // Issuing already reconciles once (`DocumentViewModel.confirmIssue`); this checks that reconciling again
        // still leaves exactly one pending reminder for the one eligible invoice, not two.
        let scheduler = FakeNotificationScheduler()
        let session = try await TestEnvironment.session(notifications: scheduler)
        var withDefault = session.business
        withDefault.reminderDaysAfterDue = 3
        try await session.dependencies.businesses.save(withDefault)
        _ = try await issuedInvoice(session, id: "doc-1", daysFromToday: -2)

        await session.reconcileReminders()
        #expect(scheduler.added.count == 1)
        await session.reconcileReminders()
        #expect(scheduler.added.count == 1) // replaced, not accumulated
    }

    @Test func reminderDatesAlreadyPassedAreNotScheduled() async throws {
        // Due 10 days ago + 3 days = a week ago: a calendar trigger that never fires, so it must not be added (and
        // must not take one of the 50 places, `spec/reminders.md` §3).
        let scheduler = FakeNotificationScheduler()
        let session = try await TestEnvironment.session(notifications: scheduler)
        var withDefault = session.business
        withDefault.reminderDaysAfterDue = 3
        try await session.dependencies.businesses.save(withDefault)
        _ = try await issuedInvoice(session, id: "doc-old", daysFromToday: -10)
        let upcoming = try await issuedInvoice(session, id: "doc-upcoming", daysFromToday: -2)

        await session.reconcileReminders()
        #expect(scheduler.added.map(\.identifier) == ["reminder-\(upcoming.id)"])
    }

    @Test func notificationShowsTheOutstandingAmount() async throws {
        let scheduler = FakeNotificationScheduler()
        let session = try await TestEnvironment.session(notifications: scheduler)
        var withDefault = session.business
        withDefault.reminderDaysAfterDue = 3
        try await session.dependencies.businesses.save(withDefault)
        let invoice = try await issuedInvoice(session, id: "doc-part-paid", daysFromToday: -2)
        try await session.dependencies.paymentService.recordPayment(
            documentID: invoice.id, amountMinor: 100_000, date: session.today, method: .cash, reference: nil, note: nil)

        await session.reconcileReminders()
        let body = try #require(scheduler.added.first?.content.body)
        let outstanding = session.money(invoice.totals.totalMinor - 100_000, currency: invoice.currency)
        #expect(body.contains(outstanding), "\(body)")
        #expect(!body.contains(session.money(invoice.totals.totalMinor, currency: invoice.currency)))
    }

    @Test func sendReminderNamesTheSellerAsIssued() async throws {
        // `spec/reminders.md` §4: the message (and its UPI link) use the issued document's seller snapshot, so a
        // business renamed after issuing doesn't change what an old invoice's reminder says.
        let session = try await TestEnvironment.session(notifications: FakeNotificationScheduler())
        var invoice = try await issuedInvoice(session, id: "doc-renamed", daysFromToday: -2)
        invoice.sellerSnapshot?.name = "Name When Issued"
        #expect(session.business.name != "Name When Issued")

        let text = ReminderMessage.text(document: invoice, paidMinor: 0, session: session)
        #expect(text.contains("from Name When Issued was due"), "\(text)")
        #expect(!text.contains(session.business.name))
    }
}
