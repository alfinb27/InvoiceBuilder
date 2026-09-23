import Foundation
import InvoiceCore
import UserNotifications

/// Turns `ReminderScheduler.plan`'s output into local notifications and keeps them in step with the database
/// (`spec/reminders.md` §3, ADR-0013). This is the only feature in the app that schedules local notifications, so
/// reconciling replaces every pending one rather than diffing.
@MainActor
struct ReminderReconciler {
    /// iOS allows at most 64 pending local notifications per app; this app reserves the nearest 50 for reminders.
    static let cap = 50
    static let notificationCategory = "invoiceReminder"
    /// The reminder fires at 9am local time; the spec does not say more than "N days after the due date."
    static let hour = 9

    let dependencies: AppDependencies
    let scheduler: any NotificationScheduling

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        scheduler = dependencies.notifications
    }

    /// Asks once; a denial just means reminders never fire locally (nothing else in the app depends on it).
    func requestAuthorizationIfNeeded() async {
        guard await scheduler.authorizationStatus() == .notDetermined else { return }
        await scheduler.requestAuthorization()
    }

    /// Re-plans this business's reminders and replaces every pending one. Safe to call repeatedly (app launch,
    /// after a payment is recorded or removed, after a void, after issuing an invoice, after the business default
    /// changes) — `spec/reminders.md` §3.
    func reconcile(businessID: String) async {
        let status = await scheduler.authorizationStatus()
        guard status == .authorized || status == .provisional else {
            scheduler.removeAllPending()
            return
        }
        guard let business = try? await dependencies.businesses.fetchBusiness(id: businessID),
              let candidates = try? await dependencies.documents.fetchReminderCandidates(businessID: businessID)
        else { return }
        let scheduled = ReminderScheduler.plan(businessDefaultDays: business.reminderDaysAfterDue, cap: Self.cap,
                                               candidates: candidates)

        scheduler.removeAllPending()
        for reminder in scheduled {
            guard let document = try? await dependencies.documents.fetchDocument(id: reminder.documentId) else {
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = "Payment reminder"
            content.body = Self.body(for: document, formatter: dependencies.reference.currencies)
            content.sound = .default
            content.categoryIdentifier = Self.notificationCategory
            content.userInfo = ["documentID": reminder.documentId]
            var when = DateComponents()
            when.year = reminder.remindOn.year
            when.month = reminder.remindOn.month
            when.day = reminder.remindOn.day
            when.hour = Self.hour
            let request = UNNotificationRequest(identifier: "reminder-\(reminder.documentId)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            await scheduler.add(request)
        }
    }

    /// "INV/26-27/0001: ₹11,800 from Rao Traders is overdue" (or "due" before the due date has passed).
    private static func body(for document: Document, formatter currencies: CurrencyCatalog) -> String {
        let spec = SpecFormatter(currencies: currencies)
        let amount = spec.money(max(document.totals.totalMinor, 0), currency: document.currency,
                                homeCurrency: document.currency)
        let who = document.buyerSnapshot?.name.map { " from \($0)" } ?? ""
        let number = document.number ?? ""
        return "\(number): \(amount)\(who) is due."
    }
}
