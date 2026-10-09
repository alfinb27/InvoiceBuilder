/// An invoice or quote (`domain.schema.json#/$defs/Document`, `spec/documents.md`). Drafts are edited in place and
/// autosaved; issuing freezes the snapshots, allocates the number and stores the engine result.
public struct Document: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var deletedAt: Int64?

    public var businessId: String
    public var docType: DocumentType
    /// Nil until issued.
    public var number: String?
    public var seriesId: String?
    public var periodKey: String?
    /// The sequence allocated at issue (`spec/documents.md` §6).
    public var sequence: Int?
    public var lifecycle: DocumentLifecycle
    public var issueDate: LocalDate
    /// Tax point; selects the rates in force.
    public var supplyDate: LocalDate?
    public var dueDate: LocalDate?
    /// Overrides `business.reminderDaysAfterDue` for this invoice (`spec/reminders.md` §1); nil defers to it.
    public var reminderDaysAfterDueOverride: Int?
    /// Quotes only.
    public var validUntil: LocalDate?
    public var sentAt: Int64?
    public var voidedAt: Int64?
    public var voidReason: String?
    public var quoteOutcome: QuoteOutcome?
    /// The quote this invoice was converted from.
    public var convertedFromId: String?
    public var currency: CurrencyCode
    /// Units of home currency per 1 unit of `currency` (decimal string).
    public var exchangeRate: String?
    public var supplyType: String
    /// Overrides the derived place of supply (region code).
    public var placeOfSupply: String?
    public var reverseCharge: Bool
    public var pricesIncludeTax: Bool
    /// Nil = the config's default.
    public var roundOff: Bool?
    public var clientId: String?
    public var sellerSnapshot: SellerSnapshot?
    public var buyerSnapshot: BuyerSnapshot?
    public var discount: Discount?
    public var shippingMinor: Int64
    public var notes: String?
    public var terms: String?
    public var templateId: TemplateID
    /// `<family>@<configVersion>` of the tax config applied.
    public var taxConfigRef: String
    /// 0 for drafts; 1 once issued.
    public var revision: Int
    public var lines: [LineItem]
    public var totals: DocumentTotals
    /// The full engine result, stored at issue.
    public var computed: ComputedDocument?

    public init(id: String, createdAt: Int64 = 0, updatedAt: Int64 = 0, deletedAt: Int64? = nil, businessId: String,
                docType: DocumentType, number: String? = nil, seriesId: String? = nil, periodKey: String? = nil,
                sequence: Int? = nil, lifecycle: DocumentLifecycle = .draft, issueDate: LocalDate,
                supplyDate: LocalDate? = nil, dueDate: LocalDate? = nil, reminderDaysAfterDueOverride: Int? = nil,
                validUntil: LocalDate? = nil, sentAt: Int64? = nil, voidedAt: Int64? = nil, voidReason: String? = nil,
                quoteOutcome: QuoteOutcome? = nil, convertedFromId: String? = nil, currency: CurrencyCode,
                exchangeRate: String? = nil, supplyType: String, placeOfSupply: String? = nil,
                reverseCharge: Bool = false, pricesIncludeTax: Bool = false, roundOff: Bool? = nil,
                clientId: String? = nil, sellerSnapshot: SellerSnapshot? = nil, buyerSnapshot: BuyerSnapshot? = nil,
                discount: Discount? = nil, shippingMinor: Int64 = 0, notes: String? = nil, terms: String? = nil,
                templateId: TemplateID = .modern, taxConfigRef: String, revision: Int = 0, lines: [LineItem] = [],
                totals: DocumentTotals = .zero, computed: ComputedDocument? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.businessId = businessId
        self.docType = docType
        self.number = number
        self.seriesId = seriesId
        self.periodKey = periodKey
        self.sequence = sequence
        self.lifecycle = lifecycle
        self.issueDate = issueDate
        self.supplyDate = supplyDate
        self.dueDate = dueDate
        self.reminderDaysAfterDueOverride = reminderDaysAfterDueOverride
        self.validUntil = validUntil
        self.sentAt = sentAt
        self.voidedAt = voidedAt
        self.voidReason = voidReason
        self.quoteOutcome = quoteOutcome
        self.convertedFromId = convertedFromId
        self.currency = currency
        self.exchangeRate = exchangeRate
        self.supplyType = supplyType
        self.placeOfSupply = placeOfSupply
        self.reverseCharge = reverseCharge
        self.pricesIncludeTax = pricesIncludeTax
        self.roundOff = roundOff
        self.clientId = clientId
        self.sellerSnapshot = sellerSnapshot
        self.buyerSnapshot = buyerSnapshot
        self.discount = discount
        self.shippingMinor = shippingMinor
        self.notes = notes
        self.terms = terms
        self.templateId = templateId
        self.taxConfigRef = taxConfigRef
        self.revision = revision
        self.lines = lines
        self.totals = totals
        self.computed = computed
    }

    public var isDraft: Bool { lifecycle == .draft }

    /// The date that selects the rates and config version in force (`ENGINE.md` Step 0).
    public var effectiveDate: LocalDate { supplyDate ?? issueDate }

    /// Derived display status (`ENGINE.md` §6). `paid` is the sum of the invoice's live payments (`documents.md`
    /// §10); callers without that sum handy pass 0.
    public func status(today: LocalDate, paid: Int64 = 0) -> DocumentStatus {
        DocumentStatus.derive(statusInput(today: today, paid: paid))
    }

    public func statusInput(today: LocalDate, paid: Int64 = 0) -> DocumentStatus.Input {
        DocumentStatus.Input(docType: docType, lifecycle: lifecycle, total: totals.totalMinor, paid: paid,
                             dueDate: dueDate, validUntil: validUntil, sentAt: sentAt, outcome: quoteOutcome,
                             today: today)
    }
}

/// A document line (`domain.schema.json#/$defs/LineItem`). The computed columns are filled at issue.
public struct LineItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var position: Int
    public var catalogItemId: String?
    public var description: String
    public var productCode: String?
    /// A `reference/units.json` id.
    public var unit: String?
    /// Decimal string.
    public var quantity: String
    public var unitPriceMinor: Int64
    public var discount: Discount?
    /// Empty until a rate is chosen (a one-off line with no previous line).
    public var rateId: String
    public var rateSnapshot: RateSnapshot?
    public var amountMinor: Int64?
    public var taxableMinor: Int64?
    public var taxMinor: Int64?
    public var totalMinor: Int64?

    public init(id: String, position: Int = 0, catalogItemId: String? = nil, description: String = "",
                productCode: String? = nil, unit: String? = nil, quantity: String = "1", unitPriceMinor: Int64 = 0,
                discount: Discount? = nil, rateId: String = "", rateSnapshot: RateSnapshot? = nil,
                amountMinor: Int64? = nil, taxableMinor: Int64? = nil, taxMinor: Int64? = nil,
                totalMinor: Int64? = nil) {
        self.id = id
        self.position = position
        self.catalogItemId = catalogItemId
        self.description = description
        self.productCode = productCode
        self.unit = unit
        self.quantity = quantity
        self.unitPriceMinor = unitPriceMinor
        self.discount = discount
        self.rateId = rateId
        self.rateSnapshot = rateSnapshot
        self.amountMinor = amountMinor
        self.taxableMinor = taxableMinor
        self.taxMinor = taxMinor
        self.totalMinor = totalMinor
    }

    /// The same line without the results stored at issue (drafts, duplicates).
    public var clearingComputed: LineItem {
        var line = self
        line.rateSnapshot = nil
        line.amountMinor = nil
        line.taxableMinor = nil
        line.taxMinor = nil
        line.totalMinor = nil
        return line
    }
}

/// The rate as applied at issue: `{ percent, category, label }`.
public struct RateSnapshot: Codable, Hashable, Sendable {
    public var percent: String
    public var category: TaxCategory
    public var label: String

    public init(percent: String, category: TaxCategory, label: String) {
        self.percent = percent
        self.category = category
        self.label = label
    }
}

/// The stored totals columns (`subtotal_minor` … `total_minor`).
public struct DocumentTotals: Codable, Hashable, Sendable {
    public var subtotalMinor: Int64
    public var discountMinor: Int64
    public var shippingMinor: Int64
    public var taxableMinor: Int64
    public var taxMinor: Int64
    public var taxNotChargedMinor: Int64
    public var roundOffMinor: Int64
    public var totalMinor: Int64

    public init(subtotalMinor: Int64, discountMinor: Int64, shippingMinor: Int64, taxableMinor: Int64,
                taxMinor: Int64, taxNotChargedMinor: Int64, roundOffMinor: Int64, totalMinor: Int64) {
        self.subtotalMinor = subtotalMinor
        self.discountMinor = discountMinor
        self.shippingMinor = shippingMinor
        self.taxableMinor = taxableMinor
        self.taxMinor = taxMinor
        self.taxNotChargedMinor = taxNotChargedMinor
        self.roundOffMinor = roundOffMinor
        self.totalMinor = totalMinor
    }

    public init(_ totals: ComputedTotals) {
        self.init(subtotalMinor: totals.subtotal, discountMinor: totals.discount, shippingMinor: totals.shipping,
                  taxableMinor: totals.taxable, taxMinor: totals.tax, taxNotChargedMinor: totals.taxNotCharged,
                  roundOffMinor: totals.roundOff, totalMinor: totals.total)
    }

    public static let zero = DocumentTotals(subtotalMinor: 0, discountMinor: 0, shippingMinor: 0, taxableMinor: 0,
                                            taxMinor: 0, taxNotChargedMinor: 0, roundOffMinor: 0, totalMinor: 0)
}

/// The seller as the engine sees it plus what documents print (`spec/documents.md` §4). One flat JSON object.
public struct SellerSnapshot: Codable, Hashable, Sendable {
    public var registration: String
    public var taxId: String?
    public var region: String?
    public var country: String
    public var homeCurrency: CurrencyCode
    public var lutReference: String?
    /// The business address on one line.
    public var address: String?
    public var turnoverMinor: Int64?
    public var customRates: [TaxRate]?

    public var name: String
    public var legalName: String?
    public var postalAddress: Address?
    public var email: String?
    public var phone: String?
    public var website: String?
    public var extraIds: ExtraIDs?
    public var bank: BankDetails?
    public var upiVpa: String?
    public var logoAssetId: String?
    public var signatureAssetId: String?

    public init(registration: String, taxId: String? = nil, region: String? = nil, country: String,
                homeCurrency: CurrencyCode, lutReference: String? = nil, address: String? = nil,
                turnoverMinor: Int64? = nil, customRates: [TaxRate]? = nil, name: String, legalName: String? = nil,
                postalAddress: Address? = nil, email: String? = nil, phone: String? = nil, website: String? = nil,
                extraIds: ExtraIDs? = nil, bank: BankDetails? = nil, upiVpa: String? = nil,
                logoAssetId: String? = nil, signatureAssetId: String? = nil) {
        self.registration = registration
        self.taxId = taxId
        self.region = region
        self.country = country
        self.homeCurrency = homeCurrency
        self.lutReference = lutReference
        self.address = address
        self.turnoverMinor = turnoverMinor
        self.customRates = customRates
        self.name = name
        self.legalName = legalName
        self.postalAddress = postalAddress
        self.email = email
        self.phone = phone
        self.website = website
        self.extraIds = extraIds
        self.bank = bank
        self.upiVpa = upiVpa
        self.logoAssetId = logoAssetId
        self.signatureAssetId = signatureAssetId
    }

    public var engineSeller: EngineSeller {
        EngineSeller(registration: registration, taxId: taxId, region: region, country: country,
                     homeCurrency: homeCurrency, lutReference: lutReference, address: address,
                     turnoverMinor: turnoverMinor, customRates: customRates)
    }
}

/// The client as the engine sees it plus what documents print (`spec/documents.md` §4). One flat JSON object.
public struct BuyerSnapshot: Codable, Hashable, Sendable {
    public var name: String?
    /// The billing address on one line.
    public var address: String?
    public var country: String?
    public var region: String?
    public var taxId: String?
    public var isBusiness: Bool

    public var contactName: String?
    public var email: String?
    public var phone: String?
    public var billingAddress: Address?
    public var shippingAddress: Address?

    public init(name: String? = nil, address: String? = nil, country: String? = nil, region: String? = nil,
                taxId: String? = nil, isBusiness: Bool = false, contactName: String? = nil, email: String? = nil,
                phone: String? = nil, billingAddress: Address? = nil, shippingAddress: Address? = nil) {
        self.name = name
        self.address = address
        self.country = country
        self.region = region
        self.taxId = taxId
        self.isBusiness = isBusiness
        self.contactName = contactName
        self.email = email
        self.phone = phone
        self.billingAddress = billingAddress
        self.shippingAddress = shippingAddress
    }

    public var engineBuyer: EngineBuyer {
        EngineBuyer(name: name, address: address, country: country, region: region, taxId: taxId,
                    isBusiness: isBusiness)
    }
}

/// One row of the documents list: what a list shows without loading lines.
public struct DocumentSummary: Hashable, Sendable, Identifiable {
    public var id: String
    public var docType: DocumentType
    public var number: String?
    public var lifecycle: DocumentLifecycle
    public var issueDate: LocalDate
    public var dueDate: LocalDate?
    public var validUntil: LocalDate?
    public var sentAt: Int64?
    public var quoteOutcome: QuoteOutcome?
    public var clientId: String?
    /// From the buyer snapshot.
    public var buyerName: String?
    public var currency: CurrencyCode
    public var totalMinor: Int64
    /// The sum of the invoice's live payments (`documents.md` §10); 0 for quotes and drafts.
    public var paidMinor: Int64
    public var lineCount: Int
    public var updatedAt: Int64

    public init(id: String, docType: DocumentType, number: String?, lifecycle: DocumentLifecycle,
                issueDate: LocalDate, dueDate: LocalDate?, validUntil: LocalDate?, sentAt: Int64?,
                quoteOutcome: QuoteOutcome?, clientId: String?, buyerName: String?, currency: CurrencyCode,
                totalMinor: Int64, paidMinor: Int64 = 0, lineCount: Int, updatedAt: Int64) {
        self.id = id
        self.docType = docType
        self.number = number
        self.lifecycle = lifecycle
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.validUntil = validUntil
        self.sentAt = sentAt
        self.quoteOutcome = quoteOutcome
        self.clientId = clientId
        self.buyerName = buyerName
        self.currency = currency
        self.totalMinor = totalMinor
        self.paidMinor = paidMinor
        self.lineCount = lineCount
        self.updatedAt = updatedAt
    }

    public func status(today: LocalDate) -> DocumentStatus {
        DocumentStatus.derive(DocumentStatus.Input(docType: docType, lifecycle: lifecycle, total: totalMinor,
                                                   paid: paidMinor, dueDate: dueDate, validUntil: validUntil,
                                                   sentAt: sentAt, outcome: quoteOutcome, today: today))
    }

    /// `max(total − paid, 0)`; nil for quotes (`ENGINE.md` §6).
    public func outstanding() -> Int64? {
        docType == .quote ? nil : max(totalMinor - paidMinor, 0)
    }
}

public extension [DocumentSummary] {
    /// Outstanding balance per currency across this client's live, unpaid issued invoices (`documents.md` §10),
    /// sorted by currency code. Several currencies are kept separate rather than summed, since there is no
    /// spec'd conversion between them (`DashboardTotals`'s doc comment explains why).
    func outstandingByCurrency(today: LocalDate) -> [(currency: CurrencyCode, minor: Int64)] {
        var totals: [CurrencyCode: Int64] = [:]
        for document in self where document.docType == .invoice && document.lifecycle == .issued {
            guard let outstanding = document.outstanding(), document.status(today: today) != .paid else { continue }
            totals[document.currency, default: 0] += outstanding
        }
        return totals.sorted { $0.key.rawValue < $1.key.rawValue }.map { ($0.key, $0.value) }
    }
}

/// Home-currency totals for the Home dashboard (`docs/plan.md` Phase 4). v1 only sums documents in the business's
/// home currency: a payment carries no currency of its own (`documents.md` §10), so a foreign-currency invoice's
/// payments cannot be safely converted without a spec'd conversion rule.
public struct DashboardTotals: Hashable, Sendable {
    public var outstandingMinor: Int64
    public var overdueMinor: Int64
    public var paidThisMonthMinor: Int64

    public init(outstandingMinor: Int64 = 0, overdueMinor: Int64 = 0, paidThisMonthMinor: Int64 = 0) {
        self.outstandingMinor = outstandingMinor
        self.overdueMinor = overdueMinor
        self.paidThisMonthMinor = paidThisMonthMinor
    }
}
