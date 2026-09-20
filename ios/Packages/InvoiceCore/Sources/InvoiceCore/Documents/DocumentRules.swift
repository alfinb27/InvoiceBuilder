import Foundation

/// Why a document cannot be issued yet (`spec/documents.md` §6 step 3–5). Screens turn these into messages.
public enum IssueProblem: Equatable, Sendable {
    case noLines
    /// 0-based line indexes.
    case lineDescriptionMissing([Int])
    case lineRateMissing([Int])
    /// The engine could not compute the document.
    case engine(TaxEngineError)
    /// An engine issue with severity `error`.
    case blockingIssue(EngineIssue)
    /// This device owns no series for the document type.
    case noSeries
    case numbering(NumberingError)
}

/// Document rules for one business (`spec/documents.md`): a new draft's defaults, the edits that move other fields,
/// snapshots, the engine input and what blocks issuing. View models and services ask these rules; neither computes
/// tax or defaults on its own.
public struct DocumentRules: Sendable {
    public let configs: TaxConfigStore
    public let business: Business
    public let currencies: CurrencyCatalog
    private let defaultConfig: TaxConfig

    public init(configs: TaxConfigStore, business: Business, currencies: CurrencyCatalog) throws {
        guard let config = configs.latest(family: business.taxConfig) ?? configs.latest(family: "GENERIC") else {
            throw SpecLoadingError(path: "tax/\(business.taxConfig).json", reason: "no config for this business")
        }
        self.init(configs: configs, business: business, currencies: currencies, defaultConfig: config)
    }

    /// `defaultConfig` is used when the store has no version of the business's family (the session's config).
    public init(configs: TaxConfigStore, business: Business, currencies: CurrencyCatalog, defaultConfig: TaxConfig) {
        self.configs = configs
        self.business = business
        self.currencies = currencies
        self.defaultConfig = defaultConfig
    }

    /// The business's config family in force on `date` (a document's `supplyDate ?? issueDate`).
    public func config(on date: LocalDate) -> TaxConfig {
        configs.latest(family: business.taxConfig, on: date) ?? defaultConfig
    }

    public func config(for document: Document) -> TaxConfig { config(on: document.effectiveDate) }

    public func chargesTax(_ config: TaxConfig) -> Bool {
        config.registration(business.taxRegistration)?.chargesTax ?? false
    }

    /// The line editor's rules for a line of `document`.
    public func lineRules(for document: Document) -> LineItemRules {
        let config = config(for: document)
        return LineItemRules(config: config, chargesTax: chargesTax(config),
                             exponent: currencies.exponent(of: document.currency))
    }

    // MARK: §2 New drafts

    public func newDocument(docType: DocumentType, id: String, today: LocalDate, client: Client? = nil,
                            now: Int64) -> Document {
        let config = config(on: today)
        var document = Document(
            id: id, createdAt: now, updatedAt: now, businessId: business.id, docType: docType, issueDate: today,
            currency: business.homeCurrency, supplyType: config.supplyTypes.first?.id ?? "domestic",
            notes: business.defaultNotes, terms: business.defaultTerms, templateId: business.templateId,
            taxConfigRef: config.ref
        )
        applyTypeDates(&document)
        setClient(client, on: &document)
        return document
    }

    /// Invoice: due after the payment terms, no valid-until date; quote: valid for 30 days, no due date.
    public func applyTypeDates(_ document: inout Document) {
        if document.docType == .quote {
            document.dueDate = nil
            document.validUntil = document.issueDate.adding(days: Self.quoteValidityDays)
        } else {
            document.validUntil = nil
            document.dueDate = document.issueDate.adding(days: business.paymentTermsDays)
        }
    }

    public static let quoteValidityDays = 30

    /// §2.1: the first `supplyTypeDefaults` entry that matches, else the first supply type.
    public func defaultSupplyType(client: Client?, config: TaxConfig) -> String {
        let foreign = client.map { $0.countryCode != business.countryCode } ?? false
        let isBusiness = client?.isBusiness ?? false
        let hasLUT = business.extraIds?.lutReference?.trimmedOrNil != nil
        let match = config.supplyTypeDefaults.first { entry in
            (entry.when.buyerForeign.map { $0 == foreign } ?? true)
                && (entry.when.buyerIsBusiness.map { $0 == isBusiness } ?? true)
                && (entry.when.sellerHasLutReference.map { $0 == hasLUT } ?? true)
        }
        return match?.supplyType ?? config.supplyTypes.first?.id ?? "domestic"
    }

    // MARK: §2.2 Edits that move other fields

    /// Choosing, changing or clearing the client resets the currency, supply type, round-off and place of supply.
    public func setClient(_ client: Client?, on document: inout Document) {
        document.clientId = client?.id
        setCurrency(client?.defaultCurrency ?? business.homeCurrency, on: &document)
        document.supplyType = defaultSupplyType(client: client, config: config(for: document))
        document.placeOfSupply = nil
    }

    /// A foreign currency starts without round-off; the home currency uses the config default. A different currency
    /// needs a new exchange rate.
    public func setCurrency(_ currency: CurrencyCode, on document: inout Document) {
        if currency != document.currency { document.exchangeRate = nil }
        document.currency = currency
        document.roundOff = currency == business.homeCurrency ? nil : false
    }

    /// The due date and valid-until date move with the issue date.
    public func setIssueDate(_ date: LocalDate, on document: inout Document) {
        let days = date.daysSinceEpoch - document.issueDate.daysSinceEpoch
        document.issueDate = date
        document.dueDate = document.dueDate?.adding(days: days)
        document.validUntil = document.validUntil?.adding(days: days)
    }

    public func setDocType(_ docType: DocumentType, on document: inout Document) {
        guard docType != document.docType else { return }
        document.docType = docType
        applyTypeDates(&document)
    }

    // MARK: §3 Lines

    /// A line for a catalogue item; `needsPrice` when its price could not be converted (§3.1).
    public func line(from item: CatalogItem, for document: Document, id: String) -> (line: LineItem, needsPrice: Bool) {
        let config = config(for: document)
        let price = LinePricing.unitPrice(
            item: item, rate: config.rate(item.rateId, customRates: business.customRates),
            chargesTax: chargesTax(config), homeCurrency: business.homeCurrency, documentCurrency: document.currency,
            exchangeRate: document.exchangeRate, documentInclusive: document.pricesIncludeTax,
            currencies: currencies, mode: config.rounding.amountMode
        )
        let line = LineItem(id: id, position: document.lines.count, catalogItemId: item.id, description: item.name,
                            productCode: item.productCode, unit: item.unit, quantity: "1",
                            unitPriceMinor: (try? price.get()) ?? 0, rateId: item.rateId)
        return (line, (try? price.get()) == nil)
    }

    /// A one-off line's rate: the previous line's; with none, the first rate in force when the seller does not
    /// charge tax (the rate is not shown then), otherwise empty (the user picks one).
    public func oneOffRateID(for document: Document) -> String {
        if let previous = document.lines.last?.rateId, !previous.isEmpty { return previous }
        let config = config(for: document)
        guard !chargesTax(config) else { return "" }
        return config.ratesInForce(on: document.effectiveDate, customRates: business.customRates).first?.id ?? ""
    }

    /// Rates offered for a line: those in force on the document's date, plus the line's own rate when it no longer is.
    public func rateChoices(for document: Document, selected: String?) -> [TaxRate] {
        let config = config(for: document)
        var choices = config.ratesInForce(on: document.effectiveDate, customRates: business.customRates)
        if let selected, !selected.isEmpty, !choices.contains(where: { $0.id == selected }),
           let saved = config.rate(selected, customRates: business.customRates) {
            choices.append(saved)
        }
        return choices
    }

    // MARK: §4 Snapshots

    public func sellerSnapshot(config: TaxConfig) -> SellerSnapshot {
        SellerSnapshot(
            registration: business.taxRegistration, taxId: business.taxId?.trimmedOrNil,
            region: business.region(config: config), country: business.countryCode,
            homeCurrency: business.homeCurrency, lutReference: business.extraIds?.lutReference?.trimmedOrNil,
            address: business.address?.singleLine.trimmedOrNil, turnoverMinor: business.turnoverMinor,
            customRates: business.customRates, name: business.name, legalName: business.legalName?.trimmedOrNil,
            postalAddress: business.address, email: business.email?.trimmedOrNil, phone: business.phone?.trimmedOrNil,
            website: business.website?.trimmedOrNil, extraIds: business.extraIds.flatMap { $0.isEmpty ? nil : $0 },
            bank: business.bank.flatMap { $0.isEmpty ? nil : $0 }, upiVpa: business.upiVpa?.trimmedOrNil,
            logoAssetId: business.logoAssetId, signatureAssetId: business.signatureAssetId
        )
    }

    public func buyerSnapshot(client: Client) -> BuyerSnapshot {
        BuyerSnapshot(
            name: client.name, address: client.billingAddress?.singleLine.trimmedOrNil, country: client.countryCode,
            region: client.regionCode?.trimmedOrNil, taxId: client.taxId?.trimmedOrNil,
            isBusiness: client.isBusiness, contactName: client.contactName?.trimmedOrNil,
            email: client.email?.trimmedOrNil, phone: client.phone?.trimmedOrNil,
            billingAddress: client.billingAddress, shippingAddress: client.shippingAddress
        )
    }

    /// The buyer of `document`: none without a client; the live client when it exists; otherwise (the client was
    /// deleted) the last snapshot the document kept.
    public func buyerSnapshot(for document: Document, client: Client?) -> BuyerSnapshot? {
        guard let clientID = document.clientId else { return nil }
        if let client, client.id == clientID { return buyerSnapshot(client: client) }
        return document.buyerSnapshot
    }

    // MARK: Engine

    public func engineInput(for document: Document, seller: SellerSnapshot, buyer: BuyerSnapshot?) -> EngineInput {
        let draft = EngineDraft(
            docType: document.docType, issueDate: document.issueDate, supplyDate: document.supplyDate,
            dueDate: document.dueDate, currency: document.currency, exchangeRate: document.exchangeRate?.trimmedOrNil,
            supplyType: document.supplyType, placeOfSupply: document.placeOfSupply?.trimmedOrNil,
            reverseCharge: document.reverseCharge, pricesIncludeTax: document.pricesIncludeTax,
            lines: document.lines.map { line in
                EngineLine(description: line.description, productCode: line.productCode, quantity: line.quantity,
                           unitPrice: line.unitPriceMinor, discount: line.discount, rateId: line.rateId)
            },
            discount: document.discount, shipping: document.shippingMinor > 0 ? document.shippingMinor : nil,
            roundOff: document.roundOff
        )
        return EngineInput(config: config(for: document), seller: seller.engineSeller,
                           buyer: buyer?.engineBuyer ?? EngineBuyer(), draft: draft, currencies: currencies)
    }

    public func compute(_ document: Document, seller: SellerSnapshot, buyer: BuyerSnapshot?)
        -> Result<ComputedDocument, TaxEngineError> {
        do {
            return .success(try TaxEngine.compute(engineInput(for: document, seller: seller, buyer: buyer)))
        } catch {
            return .failure(error)
        }
    }

    // MARK: §5 Saving a draft

    /// A draft as it is saved: snapshots from the live business and client, the ref of the config in force and the
    /// totals of `result` (0 when the engine failed). `computed` stays nil until issue.
    public func preparedDraft(_ document: Document, client: Client?) -> Document {
        var draft = document
        let config = config(for: document)
        let seller = sellerSnapshot(config: config)
        let buyer = buyerSnapshot(for: document, client: client)
        draft.sellerSnapshot = seller
        draft.buyerSnapshot = buyer
        draft.taxConfigRef = config.ref
        draft.computed = nil
        draft.lines = document.lines.enumerated().map { index, line in
            var line = line.clearingComputed
            line.position = index
            return line
        }
        switch compute(draft, seller: seller, buyer: buyer) {
        case .success(let computed): draft.totals = DocumentTotals(computed.totals)
        case .failure: draft.totals = .zero
        }
        return draft
    }

    // MARK: §6 Issuing

    /// Problems that block issuing, from the document and its engine result (§6 step 3).
    public func issueProblems(_ document: Document, result: Result<ComputedDocument, TaxEngineError>)
        -> [IssueProblem] {
        var problems: [IssueProblem] = []
        if document.lines.isEmpty { problems.append(.noLines) }
        let noDescription = document.lines.indices.filter { document.lines[$0].description.trimmedOrNil == nil }
        if !noDescription.isEmpty { problems.append(.lineDescriptionMissing(noDescription)) }
        let noRate = document.lines.indices.filter { document.lines[$0].rateId.trimmedOrNil == nil }
        if !noRate.isEmpty { problems.append(.lineRateMissing(noRate)) }
        switch result {
        case .failure(let error):
            // A missing rate is already reported for its line.
            if !(error.code == .unknownRate && error.line.map(noRate.contains) == true) {
                problems.append(.engine(error))
            }
        case .success(let computed):
            problems += computed.issues.filter { $0.severity == .error }.map(IssueProblem.blockingIssue)
        }
        return problems
    }

    /// The issued form of `document` (§6 step 6): lifecycle, number, frozen snapshots, stored results.
    public func issued(_ document: Document, seller: SellerSnapshot, buyer: BuyerSnapshot?,
                       computed: ComputedDocument, allocation: NumberAllocator.Allocation) -> Document {
        let config = config(for: document)
        let lineLevel = config.rounding.taxLevel == .line
        var issued = document
        issued.lifecycle = .issued
        issued.number = allocation.number
        issued.seriesId = allocation.series.id
        issued.periodKey = allocation.periodKey
        issued.sequence = allocation.sequence
        issued.sellerSnapshot = seller
        issued.buyerSnapshot = buyer
        issued.taxConfigRef = config.ref
        issued.revision = 1
        issued.totals = DocumentTotals(computed.totals)
        issued.computed = computed
        issued.lines = zip(document.lines.indices, zip(document.lines, computed.lines)).map { index, pair in
            var line = pair.0
            let result = pair.1
            line.position = index
            line.rateSnapshot = RateSnapshot(
                percent: result.rate, category: result.category,
                label: config.rate(line.rateId, customRates: seller.customRates)?.label ?? line.rateId
            )
            line.amountMinor = result.amount
            line.taxableMinor = result.taxable
            line.taxMinor = lineLevel ? result.tax : nil
            line.totalMinor = lineLevel ? result.taxable + result.tax : nil
            return line
        }
        return issued
    }

    // MARK: §7 Duplicate and convert

    /// A new draft copying `source`'s content, dated `today` (§7).
    public func duplicate(_ source: Document, id: String, today: LocalDate, now: Int64,
                          newLineID: () -> String) -> Document {
        var copy = Document(
            id: id, createdAt: now, updatedAt: now, businessId: source.businessId, docType: source.docType,
            issueDate: today, currency: source.currency, exchangeRate: source.exchangeRate,
            supplyType: source.supplyType, placeOfSupply: source.placeOfSupply, reverseCharge: source.reverseCharge,
            pricesIncludeTax: source.pricesIncludeTax, roundOff: source.roundOff, clientId: source.clientId,
            buyerSnapshot: source.buyerSnapshot, discount: source.discount, shippingMinor: source.shippingMinor,
            notes: source.notes, terms: source.terms, templateId: source.templateId,
            taxConfigRef: config(on: today).ref,
            lines: source.lines.enumerated().map { index, line in
                var copy = line.clearingComputed
                copy.id = newLineID()
                copy.position = index
                return copy
            }
        )
        applyTypeDates(&copy)
        return copy
    }

    /// An invoice draft from an issued quote (§7); the caller marks the quote `converted` in the same transaction.
    public func convertedInvoice(from quote: Document, id: String, today: LocalDate, now: Int64,
                                 newLineID: () -> String) -> Document {
        var invoice = duplicate(quote, id: id, today: today, now: now, newLineID: newLineID)
        invoice.docType = .invoice
        invoice.convertedFromId = quote.id
        applyTypeDates(&invoice)
        return invoice
    }

    public func canConvert(_ document: Document) -> Bool {
        document.docType == .quote && document.lifecycle == .issued && document.deletedAt == nil
            && document.quoteOutcome != .converted
    }
}
