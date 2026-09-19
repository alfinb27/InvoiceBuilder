public enum CatalogItemField: Hashable, Sendable {
    case name, unit, price, rate, productCode
}

/// A catalogue item being created or edited: plain text fields, normalised when saved.
public struct CatalogItemDraft: Equatable, Sendable {
    public var name = ""
    public var description = ""
    public var kind: ItemKind = .service
    public var unit = ItemKind.service.defaultUnit
    /// Typed price in the business home currency (`spec/setup.md` §11).
    public var priceText = ""
    public var rateId: String?
    public var productCode = ""
    public var priceIncludesTax = false

    public init() {}

    public init(item: CatalogItem, exponent: Int) {
        name = item.name
        description = item.description ?? ""
        kind = item.kind
        unit = item.unit
        priceText = MoneyInput.editingText(minor: item.unitPriceMinor, exponent: exponent)
        rateId = item.rateId
        productCode = item.productCode ?? ""
        priceIncludesTax = item.priceIncludesTax
    }

    /// Switching kind moves the unit to the new kind's default if the unit was still the old default.
    public mutating func setKind(_ newKind: ItemKind) {
        if unit == kind.defaultUnit { unit = newKind.defaultUnit }
        kind = newKind
    }
}

/// Which item fields apply and how they validate for a business (`spec/setup.md` §10).
public struct CatalogItemRules: Sendable {
    public let config: TaxConfig
    public let business: Business
    public let currencies: CurrencyCatalog
    public let units: [QuantityUnit]
    public let today: LocalDate

    public init(config: TaxConfig, business: Business, currencies: CurrencyCatalog, units: [QuantityUnit],
                today: LocalDate) {
        self.config = config
        self.business = business
        self.currencies = currencies
        self.units = units
        self.today = today
    }

    public var currency: CurrencyCode { business.homeCurrency }
    public var exponent: Int { currencies.exponent(of: currency) }

    public var chargesTax: Bool {
        config.registration(business.taxRegistration)?.chargesTax ?? false
    }

    /// Rates in force today, plus the item's saved rate when it no longer is (so it stays visible).
    public func rateChoices(selected: String?) -> [TaxRate] {
        var choices = config.ratesInForce(on: today, customRates: business.customRates)
        if let selected, !choices.contains(where: { $0.id == selected }),
           let saved = config.rate(selected, customRates: business.customRates) {
            choices.append(saved)
        }
        return choices
    }

    /// False when the saved rate exists but is not in force today (the editor shows a warning).
    public func isInForce(rateID: String) -> Bool {
        config.rate(rateID, customRates: business.customRates)?.isInForce(on: today) ?? false
    }

    public var showsInclusivePrice: Bool { chargesTax }

    /// India: HSN/SAC digits only.
    public var productCodeRule: FieldRule? { config.family == "IN" ? .hsnSac : nil }

    /// Digits the business must print on B2B / B2C invoices (the turnover tier, `ENGINE.md` Step 12).
    public var requiredProductCodeDigits: (b2b: Int, b2c: Int)? {
        guard let tiers = config.productCodes?.tiers, !tiers.isEmpty else { return nil }
        let tier = business.turnoverMinor.flatMap { turnover in
            tiers.first { $0.maxTurnoverMinor.map { turnover <= $0 } ?? true }
        } ?? tiers[0]
        return (tier.b2bDigits, tier.b2cDigits)
    }

    public func issues(_ draft: CatalogItemDraft) -> [CatalogItemField: FieldIssue] {
        var issues: [CatalogItemField: FieldIssue] = [:]
        if draft.name.trimmedOrNil == nil { issues[.name] = .required }
        if !units.contains(where: { $0.id == draft.unit }) { issues[.unit] = .required }
        if case .failure(let error) = MoneyInput.parse(draft.priceText, exponent: exponent) {
            issues[.price] = error == .empty ? .required : .invalidNumber(error)
        }
        if draft.rateId.flatMap({ config.rate($0, customRates: business.customRates) }) == nil {
            issues[.rate] = .required
        }
        if let rule = productCodeRule { issues.check(.productCode, draft.productCode, rule: rule) }
        return issues
    }

    public func makeItem(from draft: CatalogItemDraft, id: String, now: Int64) -> CatalogItem {
        var item = CatalogItem(id: id, createdAt: now, updatedAt: now, businessId: business.id, name: "",
                               unit: draft.unit, unitPriceMinor: 0, currency: currency, rateId: "")
        apply(draft, to: &item)
        return item
    }

    public func updating(_ item: CatalogItem, from draft: CatalogItemDraft) -> CatalogItem {
        var updated = item
        apply(draft, to: &updated)
        return updated
    }

    private func apply(_ draft: CatalogItemDraft, to item: inout CatalogItem) {
        item.name = draft.name.trimmedOrNil ?? item.name
        item.description = draft.description.trimmedOrNil
        item.kind = draft.kind
        item.unit = draft.unit
        item.unitPriceMinor = (try? MoneyInput.parse(draft.priceText, exponent: exponent).get()) ?? item.unitPriceMinor
        item.currency = currency
        item.rateId = draft.rateId ?? item.rateId
        item.productCode = productCodeRule.map { normalized(draft.productCode, rule: $0) }
            ?? draft.productCode.trimmedOrNil
        item.priceIncludesTax = showsInclusivePrice && draft.priceIncludesTax
    }
}
