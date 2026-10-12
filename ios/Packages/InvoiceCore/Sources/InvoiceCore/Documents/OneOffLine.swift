import Foundation

/// The "Add an item" sheet's rules (`spec/documents.md` §3.2): the rate chips, how a typed price is read, and the
/// catalogue item "Save to my items" creates.
public struct RateChips: Decodable, Sendable {
    public struct Family: Decodable, Sendable {
        public let rates: [String]
        public let hint: String

        public init(rates: [String], hint: String) {
            self.rates = rates
            self.hint = hint
        }
    }

    public let maxChips: Int
    public let families: [String: Family]

    public init(maxChips: Int, families: [String: Family]) {
        self.maxChips = maxChips
        self.families = families
    }

    /// `spec/design/rate-chips.json`.
    public static func bundled() throws -> RateChips {
        try JSONDecoder().decode(RateChips.self, from: SpecResources.data("design/rate-chips.json"))
    }

    /// The chips and the "Other rates" list for `config`, among the rates in force on `date`.
    public func choices(config: TaxConfig, customRates: [TaxRate]?, on date: LocalDate)
        -> (chips: [TaxRate], others: [TaxRate], hint: String?) {
        let inForce = config.ratesInForce(on: date, customRates: customRates)
        let chips: [TaxRate]
        if let family = families[config.family] {
            chips = family.rates.compactMap { id in inForce.first { $0.id == id } }
        } else {
            chips = Array(inForce.prefix(maxChips))
        }
        let chipIDs = Set(chips.map(\.id))
        return (chips, inForce.filter { !chipIDs.contains($0.id) }, families[config.family]?.hint)
    }
}

public enum OneOffLine {
    /// True when the includes-tax switch sets the document's own basis: no line other than `lineID` is on it.
    public static func setsDocumentBasis(_ document: Document, editing lineID: String?) -> Bool {
        document.lines.allSatisfy { $0.id == lineID }
    }

    /// The line's `unitPriceMinor` for a price typed in the document currency and read with `includesTax`: as typed
    /// when that is the document's basis, otherwise converted with the §3.1 basis factor and one rounding.
    public static func unitPrice(typedMinor: Int64, includesTax: Bool, rate: TaxRate?, document: Document,
                                 chargesTax: Bool, currencies: CurrencyCatalog, mode: RoundingMode) -> Int64 {
        guard chargesTax, includesTax != document.pricesIncludeTax else { return typedMinor }
        let item = CatalogItem(id: "", businessId: document.businessId, name: "", unit: "",
                               unitPriceMinor: typedMinor, currency: document.currency, rateId: rate?.id ?? "",
                               priceIncludesTax: includesTax)
        let price = LinePricing.unitPrice(
            item: item, rate: rate, chargesTax: chargesTax, homeCurrency: document.currency,
            documentCurrency: document.currency, exchangeRate: nil, documentInclusive: document.pricesIncludeTax,
            currencies: currencies, mode: mode)
        return (try? price.get()) ?? typedMinor
    }

    /// "Save to my items": the catalogue item for a one-off line (`setup.md` §10 defaults for a service).
    public static func catalogItem(for line: LineItem, typedMinor: Int64, includesTax: Bool, chargesTax: Bool,
                                   businessID: String, currency: CurrencyCode, id: String, now: Int64) -> CatalogItem {
        CatalogItem(id: id, createdAt: now, updatedAt: now, businessId: businessID, name: line.description,
                    kind: .service, unit: line.unit ?? ItemKind.service.defaultUnit,
                    unitPriceMinor: typedMinor, currency: currency, rateId: line.rateId,
                    productCode: line.productCode, priceIncludesTax: chargesTax && includesTax)
    }
}
