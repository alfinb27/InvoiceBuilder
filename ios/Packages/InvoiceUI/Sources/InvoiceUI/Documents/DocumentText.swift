import InvoiceCore
import SwiftUI

/// Words, messages and colours for documents: engine issues and errors, issue problems and statuses.
enum DocumentText {
    static func noun(_ docType: DocumentType) -> String {
        docType == .quote ? "quote" : "invoice"
    }

    /// The name of the shared PDF (`spec/documents.md` §8): "Invoice INV-26-27-0001.pdf", "Quote draft.pdf".
    static func pdfFileName(_ document: InvoiceCore.Document) -> String {
        let noun = noun(document.docType).capitalized
        guard let number = document.number else { return "\(noun) draft.pdf" }
        return "\(noun) \(number.replacingOccurrences(of: "/", with: "-")).pdf"
    }

    /// The navigation title of a document: its number once issued, else "New invoice" / "Quote draft".
    static func title(_ document: InvoiceCore.Document, isPersisted: Bool) -> String {
        if let number = document.number { return number }
        let noun = noun(document.docType)
        return isPersisted ? noun.capitalized + " draft" : "New " + noun
    }

    static func status(_ status: DocumentStatus) -> String {
        switch status {
        case .draft: "Draft"
        case .issued: "Not sent"
        case .sent: "Sent"
        case .partiallyPaid: "Part paid"
        case .paid: "Paid"
        case .overdue: "Past due"
        case .void: "Void"
        case .open: "Open"
        case .accepted: "Accepted"
        case .declined: "Declined"
        case .expired: "Expired"
        case .converted: "Converted"
        }
    }

    static func color(_ status: DocumentStatus) -> Color {
        switch status {
        case .draft, .void, .expired: Theme.textSecondary
        case .paid, .accepted, .converted: Theme.success
        case .overdue, .declined: Theme.danger
        case .partiallyPaid: Theme.warning
        case .issued, .sent, .open: Theme.info
        }
    }

    /// "Item 2", "Items 1 and 3", "Items 1, 2 and 5" (1-based for people; the screens call lines items).
    static func lines(_ indexes: [Int]) -> String {
        let numbers = indexes.map { String($0 + 1) }
        guard numbers.count > 1, let last = numbers.last else { return "Item \(numbers.first ?? "")" }
        return "Items " + numbers.dropLast().joined(separator: ", ") + " and " + last
    }

    /// A compliance check or rate warning from the engine (`ENGINE.md` Step 12).
    static func message(_ issue: EngineIssue, config: TaxConfig, homeCurrency: CurrencyCode) -> String {
        let labels = config.labels
        let lines = issue.lines.map(lines) ?? "Some items"
        switch issue.code {
        case "rate_not_effective":
            return "\(lines): the \(labels.taxName) rate isn't in force on this date. Check the rate or the dates."
        case "seller_tax_id_missing":
            return "Add your \(labels.taxIdName) in Settings → Business profile."
        case "buyer_details_required":
            return config.family == "IN"
                ? "For totals of ₹50,000 or more to unregistered buyers, add the client's name, address and state."
                : "A \(labels.taxName) invoice needs the client's name and address."
        case "buyer_address_missing":
            return "Add the client's name and billing address: registered buyers need them on the invoice."
        case "lut_reference_missing":
            return "Exports without IGST need your LUT reference. Add it in Settings → Business profile."
        case "export_buyer_details_required":
            return "Exports need the client's name, address and country."
        case "product_code_missing":
            return "\(lines): add the \(labels.productCodeName) with enough digits for your turnover."
        case "exchange_rate_missing":
            return "Add the exchange rate: \(labels.taxName) must also be shown in \(homeCurrency.rawValue)."
        default:
            return issue.code.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Why the engine could not compute the document (`ENGINE.md` §3, errors).
    static func message(_ error: TaxEngineError, config: TaxConfig) -> String {
        let line = error.line.map { "Item \($0 + 1): " } ?? ""
        switch error.code {
        case .noComponentRule:
            return "This supply type can't be used with your registration."
        case .unknownRate:
            return line + "choose a \(config.labels.taxName) rate."
        case .unknownRegion:
            return "Choose a valid \((config.labels.placeOfSupply ?? "place of supply").lowercased())."
        case .discountExceedsSubtotal:
            return "The discount is more than the subtotal."
        case .lineDiscountExceedsAmount:
            return line + "the discount is more than the item's amount."
        case .inclusiveCompoundUnsupported:
            return line + "compound taxes can't be used with tax-inclusive prices."
        case .invalidInput:
            return line + "check the quantity, price and amounts."
        }
    }

    /// What blocks sending (`spec/documents.md` §6).
    static func message(_ problem: IssueProblem, config: TaxConfig, homeCurrency: CurrencyCode,
                        docType: DocumentType) -> String {
        switch problem {
        case .noLines:
            "Add at least one item."
        case .lineDescriptionMissing(let indexes):
            "\(lines(indexes)): add a description."
        case .lineRateMissing(let indexes):
            "\(lines(indexes)): choose a \(config.labels.taxName) rate."
        case .engine(let error):
            message(error, config: config)
        case .blockingIssue(let issue):
            message(issue, config: config, homeCurrency: homeCurrency)
        case .noSeries:
            "This device has no number series for \(noun(docType))s. Check Settings → Invoice numbering."
        case .numbering(.numberTooLong):
            "The next number would be too long. Shorten the pattern in Settings → Invoice numbering."
        case .numbering(.numberInvalidChars):
            "The next number has characters that aren't allowed. Check Settings → Invoice numbering."
        }
    }

    static func category(_ category: TaxCategory) -> String {
        switch category {
        case .exempt: "Exempt"
        case .nilRated: "Nil rated"
        case .outsideScope: "Outside the scope"
        case .zero: "Zero rated"
        default: category.rawValue.capitalized
        }
    }
}

enum PaymentMethodText {
    /// The fixed set from `domain.schema.json#/$defs/Payment.method`, in picker order.
    static let all: [PaymentMethod] = [.cash, .bank, .upi, .card, .cheque, .other]

    static func label(_ method: PaymentMethod) -> String {
        switch method {
        case .cash: "Cash"
        case .bank: "Bank transfer"
        case .upi: "UPI"
        case .card: "Card"
        case .cheque: "Cheque"
        case .other: "Other"
        default: method.rawValue.capitalized
        }
    }
}

/// A status chip for lists and headers.
struct StatusTag: View {
    let status: DocumentStatus

    var body: some View {
        Tag(text: DocumentText.status(status), color: DocumentText.color(status))
    }
}

extension LocalDate {
    /// Noon on this day in the device calendar (DatePicker values).
    var date: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    init(date: Date) {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self = LocalDate(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
            ?? LocalDate(daysSinceEpoch: 0)
    }

    /// From an epoch-ms audit timestamp (`voidedAt`, `sentAt`), in the device calendar.
    init(epochMs: Int64) {
        self.init(date: Date(timeIntervalSince1970: Double(epochMs) / 1000))
    }

    /// `19 Sept 2026`, for rows and headers (display only; stored dates stay ISO).
    var displayText: String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
