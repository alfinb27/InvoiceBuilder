import InvoiceCore

/// "Send reminder"'s message template (`spec/reminders.md` §4), shared verbatim via the OS share sheet.
@MainActor
enum ReminderMessage {
    static func text(document: InvoiceCore.Document, paidMinor: Int64, session: Session) -> String {
        let outstanding = max(document.totals.totalMinor - paidMinor, 0)
        let greeting: String
        if let buyer = document.buyerSnapshot, let name = buyer.contactName ?? buyer.name {
            greeting = "Hi \(name),"
        } else {
            greeting = "Hi there,"
        }
        let dueDate = document.dueDate?.displayText ?? "the due date"
        var text = "\(greeting) this is a reminder that invoice \(document.number ?? "") for "
            + "\(session.money(outstanding, currency: document.currency)) from \(session.business.name) "
            + "was due on \(dueDate)."
        if let line = upiLine(document: document, outstanding: outstanding, session: session) {
            text += line
        }
        return text + " Thank you!"
    }

    /// `ENGINE.md` §9: only for INR documents with a UPI ID and an outstanding amount > 0.
    private static func upiLine(document: InvoiceCore.Document, outstanding: Int64, session: Session) -> String? {
        guard document.currency == .inr, outstanding > 0, let vpa = session.business.upiVpa?.trimmedOrNil else {
            return nil
        }
        let link = UPIPaymentLink.url(vpa: vpa, payeeName: session.business.name, amountMinor: outstanding,
                                      invoiceNumber: document.number ?? "")
        return " Pay via UPI: \(link)"
    }
}
