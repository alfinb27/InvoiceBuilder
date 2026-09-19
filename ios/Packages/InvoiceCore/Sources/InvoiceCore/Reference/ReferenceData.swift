import Foundation

/// One entry of `spec/reference/countries.json` (ISO 3166-1 alpha-2).
public struct Country: Codable, Hashable, Sendable, Identifiable {
    public let code: String
    public let name: String

    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

/// One entry of `spec/reference/units.json`: a catalogue unit and its GST Unique Quantity Code.
public struct QuantityUnit: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let uqc: String

    public init(id: String, label: String, uqc: String) {
        self.id = id
        self.label = label
        self.uqc = uqc
    }
}

/// Countries, currencies and units from `spec/reference/`.
public struct ReferenceData: Sendable {
    public let countries: [Country]
    public let currencies: CurrencyCatalog
    public let units: [QuantityUnit]
    private let countriesByCode: [String: Country]

    public init(countries: [Country], currencies: [Currency], units: [QuantityUnit]) {
        self.countries = countries
        self.currencies = CurrencyCatalog(currencies)
        self.units = units
        countriesByCode = Dictionary(countries.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func country(code: String) -> Country? { countriesByCode[code] }

    public func unit(id: String) -> QuantityUnit? { units.first { $0.id == id } }

    /// Countries sorted by English name, for pickers.
    public var countriesByName: [Country] {
        countries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The copy bundled in InvoiceCore.
    public static func bundled() throws -> ReferenceData {
        let decoder = JSONDecoder()
        struct Countries: Decodable { let countries: [Country] }
        struct Currencies: Decodable { let currencies: [Currency] }
        struct Units: Decodable { let units: [QuantityUnit] }
        return ReferenceData(
            countries: try decoder.decode(Countries.self, from: SpecResources.data("reference/countries.json")).countries,
            currencies: try decoder.decode(Currencies.self, from: SpecResources.data("reference/currencies.json")).currencies,
            units: try decoder.decode(Units.self, from: SpecResources.data("reference/units.json")).units
        )
    }
}
