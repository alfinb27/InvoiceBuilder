import Foundation
import InvoiceCore

/// Sample businesses, clients and items for previews, UI tests and screenshots (`-seed IN` / `-seed GB`).
public enum SampleData {
    public enum Country: String, Sendable {
        case india = "IN"
        case uk = "GB"
    }

    /// Onboards a sample business on this device and fills its client list and catalogue.
    @discardableResult
    public static func seed(_ country: Country, dependencies: AppDependencies, deviceID: String) async throws
        -> Business {
        let family = country.rawValue
        guard let config = dependencies.taxConfigs.latest(family: family) else {
            throw SpecLoadingError(path: "tax/\(family).json", reason: "missing")
        }
        let rules = BusinessRules(config: config)
        let today = dependencies.time.today()
        var draft = BusinessDraft()
        draft.countryCode = country.rawValue
        switch country {
        case .india:
            draft.taxRegistration = "regular"
            draft.name = "Bharat Web Studio"
            draft.legalName = "Bharat Web Studio LLP"
            draft.taxId = "29AAGCB7383J1Z4"
            draft.address = AddressDraft(line1: "12 MG Road", city: "Bengaluru", postalCode: "560001")
            draft.email = "hello@bharatweb.example"
            draft.phone = "+91 80 5555 0100"
            draft.bankAccountName = "Bharat Web Studio LLP"
            draft.bankAccountNumber = "000123456789"
            draft.bankName = "Example Bank"
            draft.ifsc = "EXMP0001234"
            draft.upiVpa = "bharatweb@examplebank"
        case .uk:
            draft.taxRegistration = "vatRegistered"
            draft.name = "Thames Design Ltd"
            draft.taxId = "GB980780684"
            draft.address = AddressDraft(line1: "1 Bridge Street", city: "London", postalCode: "SE1 9DA")
            draft.email = "studio@thamesdesign.example"
            draft.companyNumber = "01234567"
            draft.bankAccountName = "Thames Design Ltd"
            draft.bankAccountNumber = "12345678"
            draft.sortCode = "12-34-56"
        }
        rules.applyDerivations(to: &draft)
        let business = rules.makeBusiness(from: draft, id: dependencies.ids.make(), now: dependencies.time.now(),
                                          today: today, newID: dependencies.ids.make)
        let series = BusinessSetup.defaultSeries(businessID: business.id, config: config, ownerDeviceID: deviceID,
                                                 now: dependencies.time.now(), newID: dependencies.ids.make)
        let created = try await dependencies.setup.createBusiness(business, series: series, logo: nil, signature: nil,
                                                                  deviceID: deviceID)

        let clientRules = ClientRules(config: config, businessCountry: country.rawValue)
        for sample in clients(for: country) {
            try await dependencies.clients.save(
                clientRules.makeClient(from: sample, id: dependencies.ids.make(), businessID: created.id,
                                       now: dependencies.time.now()))
        }
        let itemRules = CatalogItemRules(config: config, business: created,
                                         currencies: dependencies.reference.currencies,
                                         units: dependencies.reference.units, today: today)
        for sample in items(for: country) {
            try await dependencies.catalog.save(
                itemRules.makeItem(from: sample, id: dependencies.ids.make(), now: dependencies.time.now()))
        }
        return created
    }

    /// The demo business's documents (onboarding's "Try it with a sample business"): a paid invoice, an overdue
    /// one, a partly paid one and an open quote, so Home, the list and the reminders have something to show.
    static func addDemoDocuments(business: Business, dependencies: AppDependencies, deviceID: String) async throws {
        let rules = try DocumentRules(configs: dependencies.taxConfigs, business: business,
                                      currencies: dependencies.reference.currencies)
        let today = dependencies.time.today()
        let clientsList = try await firstValue(dependencies.clients.observeClients(businessID: business.id)) ?? []
        let catalog = try await firstValue(dependencies.catalog.observeItems(businessID: business.id)) ?? []
        let clients = clientsList.sorted { $0.name < $1.name }
        guard !clients.isEmpty, !catalog.isEmpty else { return }

        func make(_ docType: DocumentType, client: Client, items: [CatalogItem], issuedDaysAgo: Int) async throws
            -> InvoiceCore.Document {
            var document = rules.newDocument(docType: docType, id: dependencies.ids.make(),
                                             today: today.adding(days: -issuedDaysAgo), client: client,
                                             now: dependencies.time.now())
            for item in items {
                document.lines.append(rules.line(from: item, for: document, id: dependencies.ids.make()).line)
            }
            let saved = try await dependencies.documents.saveDraft(rules.preparedDraft(document, client: client))
            return try await dependencies.documentService.issue(documentID: saved.id, deviceID: deviceID)
        }

        let paid = try await make(.invoice, client: clients[0], items: Array(catalog.prefix(1)), issuedDaysAgo: 20)
        try await dependencies.paymentService.recordPayment(
            documentID: paid.id, amountMinor: paid.totals.totalMinor, date: today.adding(days: -5),
            method: business.countryCode == "IN" ? .upi : .bank, reference: nil, note: nil)
        _ = try await make(.invoice, client: clients[clients.count > 1 ? 1 : 0], items: Array(catalog.prefix(2)),
                           issuedDaysAgo: 45)
        let partly = try await make(.invoice, client: clients[0], items: Array(catalog.suffix(1)), issuedDaysAgo: 3)
        try await dependencies.paymentService.recordPayment(
            documentID: partly.id, amountMinor: partly.totals.totalMinor / 2, date: today, method: .cash,
            reference: nil, note: nil)
        _ = try await make(.quote, client: clients[clients.count > 1 ? 1 : 0], items: Array(catalog.prefix(3)),
                           issuedDaysAgo: 1)
    }

    static func clients(for country: Country) -> [ClientDraft] {
        func client(_ name: String, country: String, business: Bool = false, taxId: String = "", region: String? = nil,
                    line1: String = "", city: String = "", postal: String = "", email: String = "") -> ClientDraft {
            var draft = ClientDraft(countryCode: country)
            draft.name = name
            draft.isBusiness = business
            draft.taxId = taxId
            draft.regionCode = region
            draft.billing = AddressDraft(line1: line1, city: city, postalCode: postal)
            draft.email = email
            return draft
        }
        switch country {
        case .india:
            return [
                client("Rao Traders", country: "IN", business: true, taxId: "29AABCR1234C1ZU",
                       line1: "5 Residency Road", city: "Bengaluru", postal: "560025"),
                client("Umesh Foods", country: "IN", business: true, taxId: "27AAPFU0939F1ZV",
                       line1: "8 Link Road", city: "Mumbai", postal: "400053", email: "accounts@umeshfoods.example"),
                client("Anita Sharma", country: "IN", region: "29", line1: "44 Indiranagar", city: "Bengaluru",
                       postal: "560038"),
                client("Acme Inc.", country: "US", business: true, taxId: "EIN 12-3456789", line1: "200 Main St",
                       city: "Springfield"),
            ]
        case .uk:
            return [
                client("Blackfriars Café", country: "GB", business: true, taxId: "GB999999973",
                       line1: "3 Blackfriars Lane", city: "London", postal: "EC4V 6ER"),
                client("Anna Clarke", country: "GB", line1: "17 Mill Road", city: "Cambridge", postal: "CB1 2AD"),
                client("Müller GmbH", country: "DE", business: true, taxId: "DE123456789", line1: "Hauptstraße 5",
                       city: "Berlin", postal: "10115"),
            ]
        }
    }

    static func items(for country: Country) -> [CatalogItemDraft] {
        func item(_ name: String, kind: ItemKind, unit: String, price: String, rate: String, code: String = "",
                  inclusive: Bool = false) -> CatalogItemDraft {
            var draft = CatalogItemDraft()
            draft.name = name
            draft.kind = kind
            draft.unit = unit
            draft.priceText = price
            draft.rateId = rate
            draft.productCode = code
            draft.priceIncludesTax = inclusive
            return draft
        }
        switch country {
        case .india:
            return [
                item("Website development", kind: .service, unit: "JOB", price: "5000", rate: "gst_18", code: "998314"),
                item("SEO audit", kind: .service, unit: "JOB", price: "4000", rate: "gst_18", code: "998365"),
                item("Tea leaves", kind: .goods, unit: "KGS", price: "240", rate: "gst_5", code: "0902"),
                item("Fresh milk", kind: .goods, unit: "LTR", price: "56", rate: "exempt", code: "0401"),
            ]
        case .uk:
            return [
                item("Logo design", kind: .service, unit: "JOB", price: "450", rate: "standard"),
                item("Consulting", kind: .service, unit: "HRS", price: "85", rate: "standard"),
                item("Printed children's books", kind: .goods, unit: "PCS", price: "12.99", rate: "zero",
                     inclusive: true),
            ]
        }
    }
}
