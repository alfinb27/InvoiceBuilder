import Foundation

/// Home's "Get ready to send your first invoice" checklist (`spec/setup.md` §3.2). Shown until the business has
/// issued an invoice; issued invoices are never deleted, so it never comes back.
public struct FirstRunChecklist: Equatable, Sendable {
    public enum Item: String, CaseIterable, Sendable {
        case setUpBusiness, addClient, saveItem, sendInvoice
    }

    public var hasClient: Bool
    public var hasItem: Bool
    public var hasIssuedInvoice: Bool

    public init(hasClient: Bool = false, hasItem: Bool = false, hasIssuedInvoice: Bool = false) {
        self.hasClient = hasClient
        self.hasItem = hasItem
        self.hasIssuedInvoice = hasIssuedInvoice
    }

    /// From the business's live clients, items and documents.
    public init(clientCount: Int, itemCount: Int, documents: [DocumentSummary]) {
        self.init(hasClient: clientCount > 0, hasItem: itemCount > 0,
                  hasIssuedInvoice: documents.contains { $0.docType == .invoice && $0.lifecycle != .draft })
    }

    public func isDone(_ item: Item) -> Bool {
        switch item {
        case .setUpBusiness: true
        case .addClient: hasClient
        case .saveItem: hasItem
        case .sendInvoice: hasIssuedInvoice
        }
    }

    public var doneCount: Int { Item.allCases.filter(isDone).count }
    public var isShown: Bool { !hasIssuedInvoice }
}
