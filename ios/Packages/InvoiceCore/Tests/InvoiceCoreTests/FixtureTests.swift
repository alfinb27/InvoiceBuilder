import Foundation
import Testing
@testable import InvoiceCore

/// Runs the golden fixtures that InvoiceCore implements so far. Kinds still waiting for a runner are listed in
/// `pendingKinds`, so the fixture count stays an explicit parity metric (`docs/parity.md`).
@Suite("Spec fixtures")
struct FixtureTests {
    static let implementedKinds: Set = ["validation", "field", "input", "format", "numbering", "tax", "rounding",
                                        "distribute", "words", "status", "upi", "document", "pdf", "reminder", "backup", "series", "billing"]
    /// Kinds with no runner yet (none: every spec fixture kind runs on iOS).
    static let pendingKinds: Set<String> = []

    static let configs = try! TaxConfigStore.bundled()
    static let currencies = try! ReferenceData.bundled().currencies
    static let formatter = SpecFormatter(currencies: currencies)

    @Test func everyKindIsImplementedOrExplicitlyPending() {
        let kinds = Set(Fixtures.all.map(\.kind))
        #expect(!Fixtures.all.isEmpty, "no fixtures found under \(Spec.root.path)")
        #expect(kinds.subtracting(Self.implementedKinds).subtracting(Self.pendingKinds).isEmpty,
                "fixture kinds with no runner: \(kinds.subtracting(Self.implementedKinds.union(Self.pendingKinds)))")
        for kind in Self.implementedKinds {
            #expect(!Fixtures.cases(kind: kind).isEmpty, "no \(kind) fixtures")
        }
    }

    @Test func caseIDsAreUnique() {
        let ids = Fixtures.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: ENGINE.md §8

    @Test(arguments: Fixtures.cases(kind: "validation"))
    func taxID(_ fixture: FixtureCase) throws {
        let config = try #require(Self.configs.config(ref: try fixture.string("config")))
        let formatID = try fixture.string("format")
        let format = try #require(config.taxIdFormats.first { $0.id == formatID })
        let result = TaxIDValidator.validate(try fixture.string("value"), format: format, regions: config.regions)
        expectFixture(fixture, .object([
            "valid": .bool(result.valid),
            "normalized": .string(result.normalized),
            "region": .optional(result.region),
            "error": .optional(result.error?.rawValue),
        ]))
    }

    // MARK: setup.md §8

    @Test(arguments: Fixtures.cases(kind: "field"))
    func fieldRule(_ fixture: FixtureCase) throws {
        let rule = try #require(FieldRule(rawValue: try fixture.string("rule")))
        let result = rule.validate(try fixture.string("value"))
        expectFixture(fixture, .object([
            "valid": .bool(result.valid),
            "normalized": .string(result.normalized),
            "error": .optional(result.error?.rawValue),
        ]))
    }

    // MARK: setup.md §11

    @Test(arguments: Fixtures.cases(kind: "input"))
    func typedInput(_ fixture: FixtureCase) throws {
        let text = try fixture.string("text")
        switch try fixture.string("op") {
        case "money":
            let currency = CurrencyCode(rawValue: try fixture.string("currency"))
            let exponent = try #require(Self.formatter.currencies[currency]).minorUnits
            switch MoneyInput.parse(text, exponent: exponent) {
            case .success(let minor): expectFixture(fixture, .object(["minor": .int(minor)]))
            case .failure(let error): expectFixture(fixture, .object(["error": .string(error.rawValue)]))
            }
        case "decimal":
            switch DecimalInput.parse(text) {
            case .success(let value): expectFixture(fixture, .object(["value": .string(value)]))
            case .failure(let error): expectFixture(fixture, .object(["error": .string(error.rawValue)]))
            }
        case let op:
            Issue.record("\(fixture.id): unknown op \(op)")
        }
    }

    // MARK: ENGINE.md §7.1–7.2

    @Test(arguments: Fixtures.cases(kind: "format"))
    func format(_ fixture: FixtureCase) throws {
        let text: String
        switch try fixture.string("op") {
        case "money":
            let minor = try #require(fixture.input["minor"]?.intValue)
            text = Self.formatter.money(minor, currency: CurrencyCode(rawValue: try fixture.string("currency")),
                                        homeCurrency: CurrencyCode(rawValue: try fixture.string("homeCurrency")))
        case "percent":
            text = SpecFormatter.percent(try fixture.string("value"))
        case "quantity":
            text = SpecFormatter.quantity(try fixture.string("value"))
        case let op:
            Issue.record("\(fixture.id): unknown op \(op)")
            return
        }
        expectFixture(fixture, .object(["text": .string(text)]))
    }

    // MARK: ENGINE.md §5

    @Test(arguments: Fixtures.cases(kind: "numbering"))
    func numbering(_ fixture: FixtureCase) throws {
        let date = try #require(LocalDate(iso: try fixture.string("date")))
        let fiscalYearStart = try #require(MonthDay(text: try fixture.string("fiscalYearStart")))
        let seq = Int(try #require(fixture.input["seq"]?.intValue))
        let result = Numbering.format(
            pattern: try fixture.string("pattern"), reset: NumberingReset(rawValue: try fixture.string("reset")),
            date: date, seq: seq, fiscalYearStart: fiscalYearStart,
            maxLength: fixture.input["maxLength"]?.intValue.map(Int.init),
            allowedPattern: fixture.input["allowedPattern"]?.stringValue
        )
        switch result {
        case .success(let value):
            expectFixture(fixture, .object(["number": .string(value.number), "periodKey": .string(value.periodKey)]))
        case .failure(let error):
            expectFixture(fixture, .object(["error": .string(error.rawValue)]))
        }
    }

    // MARK: ENGINE.md §1–4

    struct TaxCaseInput: Decodable {
        let seller: EngineSeller
        let buyer: EngineBuyer
        let draft: EngineDraft
    }

    @Test(arguments: Fixtures.cases(kind: "tax"))
    func tax(_ fixture: FixtureCase) throws {
        let ref = try #require(fixture.config, "\(fixture.id): no config")
        let config = try #require(Self.configs.config(ref: ref), "\(fixture.id): unknown config \(ref)")
        let input = try JSONDecoder().decode(TaxCaseInput.self, from: fixture.inputData)
        let engineInput = EngineInput(config: config, seller: input.seller, buyer: input.buyer, draft: input.draft,
                                      currencies: Self.currencies)
        do {
            expectFixture(fixture, try JSONValue.encoding(TaxEngine.compute(engineInput)))
        } catch let error as TaxEngineError {
            var fields: [String: JSONValue] = ["error": .string(error.code.rawValue)]
            if let line = error.line { fields["line"] = .int(Int64(line)) }
            expectFixture(fixture, .object(fields))
        }
    }

    // MARK: ENGINE.md §2.2–2.4

    @Test(arguments: Fixtures.cases(kind: "rounding"))
    func rounding(_ fixture: FixtureCase) throws {
        let value = try #require(DecimalString.parse(try fixture.string("value")))
        let mode = try #require(RoundingMode(rawValue: try fixture.string("mode")))
        expectFixture(fixture, .object(["result": .int(SpecMath.round(value, mode))]))
    }

    @Test(arguments: Fixtures.cases(kind: "distribute"))
    func distribute(_ fixture: FixtureCase) throws {
        let total = try #require(fixture.input["total"]?.intValue)
        let parts: [Int64]
        if case .array(let exacts)? = fixture.input["exacts"] {
            parts = SpecMath.distribute(total, try exacts.map { try #require($0.stringValue.flatMap(DecimalString.parse)) })
        } else if case .array(let weights)? = fixture.input["weights"] {
            parts = SpecMath.allocateProportional(total, try weights.map { try #require($0.intValue) })
        } else {
            Issue.record("\(fixture.id): needs exacts or weights")
            return
        }
        expectFixture(fixture, .object(["parts": .array(parts.map(JSONValue.int))]))
    }

    // MARK: ENGINE.md §7.3

    @Test(arguments: Fixtures.cases(kind: "words"))
    func words(_ fixture: FixtureCase) throws {
        let minor = try #require(fixture.input["minor"]?.intValue)
        let text = AmountInWords.text(minor: minor, currency: CurrencyCode(rawValue: try fixture.string("currency")),
                                      currencies: Self.currencies)
        expectFixture(fixture, .object(["text": .string(text)]))
    }

    // MARK: ENGINE.md §6

    @Test(arguments: Fixtures.cases(kind: "status"))
    func status(_ fixture: FixtureCase) throws {
        let input = DocumentStatus.Input(
            docType: DocumentType(rawValue: try fixture.string("docType")),
            lifecycle: DocumentLifecycle(rawValue: try fixture.string("lifecycle")),
            total: try #require(fixture.input["total"]?.intValue), paid: try #require(fixture.input["paid"]?.intValue),
            dueDate: fixture.input["dueDate"]?.stringValue.flatMap(LocalDate.init(iso:)),
            validUntil: fixture.input["validUntil"]?.stringValue.flatMap(LocalDate.init(iso:)),
            sentAt: fixture.input["sentAt"]?.intValue,
            outcome: fixture.input["outcome"]?.stringValue.map(QuoteOutcome.init(rawValue:)),
            today: try #require(LocalDate(iso: try fixture.string("today")))
        )
        var fields: [String: JSONValue] = ["status": .string(DocumentStatus.derive(input).rawValue)]
        if let outstanding = DocumentStatus.outstanding(input) { fields["outstanding"] = .int(outstanding) }
        expectFixture(fixture, .object(fields))
    }

    // MARK: documents.md §2, §3.1

    struct DefaultsInput: Decodable {
        struct BusinessFields: Decodable {
            let countryCode: String
            let homeCurrency: CurrencyCode
            let paymentTermsDays: Int
            let lutReference: String?
        }

        struct ClientFields: Decodable {
            let countryCode: String
            let isBusiness: Bool
            let defaultCurrency: CurrencyCode?
        }

        let config: String
        let docType: DocumentType
        let today: LocalDate
        let business: BusinessFields
        let client: ClientFields?
    }

    struct LinePriceInput: Decodable {
        struct ItemFields: Decodable {
            let unitPriceMinor: Int64
            let currency: CurrencyCode
            let priceIncludesTax: Bool
            let rateId: String
        }

        struct DocumentFields: Decodable {
            let currency: CurrencyCode
            let exchangeRate: String?
            let pricesIncludeTax: Bool
        }

        let config: String
        let registration: String
        let homeCurrency: CurrencyCode
        let customRates: [TaxRate]?
        let item: ItemFields
        let document: DocumentFields
    }

    @Test(arguments: Fixtures.cases(kind: "document"))
    func document(_ fixture: FixtureCase) throws {
        switch try fixture.string("op") {
        case "defaults":
            let input = try JSONDecoder().decode(DefaultsInput.self, from: fixture.inputData)
            let config = try #require(Self.configs.config(ref: input.config))
            let business = Business(
                id: "b", name: "Business", countryCode: input.business.countryCode, taxConfig: config.family,
                taxRegistration: config.registrations[0].id,
                extraIds: input.business.lutReference.map { ExtraIDs(lutReference: $0) },
                homeCurrency: input.business.homeCurrency, paymentTermsDays: input.business.paymentTermsDays
            )
            let client = input.client.map { fields in
                Client(id: "c", businessId: "b", name: "Client", countryCode: fields.countryCode,
                       isBusiness: fields.isBusiness, defaultCurrency: fields.defaultCurrency)
            }
            let rules = try DocumentRules(configs: Self.configs, business: business, currencies: Self.currencies)
            let document = rules.newDocument(docType: input.docType, id: "d", today: input.today, client: client,
                                             now: 0)
            expectFixture(fixture, .object([
                "issueDate": .string(document.issueDate.iso),
                "dueDate": .optional(document.dueDate?.iso),
                "validUntil": .optional(document.validUntil?.iso),
                "currency": .string(document.currency.rawValue),
                "supplyType": .string(document.supplyType),
                "roundOff": document.roundOff.map(JSONValue.bool) ?? .null,
            ]))
        case "linePrice":
            let input = try JSONDecoder().decode(LinePriceInput.self, from: fixture.inputData)
            let config = try #require(Self.configs.config(ref: input.config))
            let item = CatalogItem(id: "i", businessId: "b", name: "Item", unit: "NOS",
                                   unitPriceMinor: input.item.unitPriceMinor, currency: input.item.currency,
                                   rateId: input.item.rateId, priceIncludesTax: input.item.priceIncludesTax)
            let result = LinePricing.unitPrice(
                item: item, rate: config.rate(input.item.rateId, customRates: input.customRates),
                chargesTax: try #require(config.registration(input.registration)).chargesTax,
                homeCurrency: input.homeCurrency, documentCurrency: input.document.currency,
                exchangeRate: input.document.exchangeRate, documentInclusive: input.document.pricesIncludeTax,
                currencies: Self.currencies, mode: config.rounding.amountMode
            )
            switch result {
            case .success(let minor): expectFixture(fixture, .object(["unitPriceMinor": .int(minor)]))
            case .failure(let error): expectFixture(fixture, .object(["error": .string(error.rawValue)]))
            }
        case let op:
            Issue.record("\(fixture.id): unknown op \(op)")
        }
    }

    // MARK: pdf/RENDERING.md §1

    struct PDFCaseInput: Decodable {
        let template: String
        let document: Document
    }

    static let pdfLabels = try! PDFLabels.bundled()
    static let reference = try! ReferenceData.bundled()

    @Test(arguments: Fixtures.cases(kind: "pdf"))
    func pdf(_ fixture: FixtureCase) throws {
        let input = try JSONDecoder().decode(PDFCaseInput.self, from: fixture.inputData)
        let document = input.document
        let config = try #require(Self.configs.config(ref: document.taxConfigRef))
        let seller = try #require(document.sellerSnapshot)
        let engineInput = EngineInput(document: document, seller: seller.engineSeller,
                                      buyer: document.buyerSnapshot?.engineBuyer ?? EngineBuyer(), config: config,
                                      currencies: Self.currencies)
        let computed = try TaxEngine.compute(engineInput)
        let model = PDFModelBuilder.build(document: document, computed: computed, config: config,
                                          labels: Self.pdfLabels, reference: Self.reference)
        expectFixture(fixture, try JSONValue.encoding(model))
    }

    // MARK: ENGINE.md §9

    @Test(arguments: Fixtures.cases(kind: "upi"))
    func upi(_ fixture: FixtureCase) throws {
        let url = UPIPaymentLink.url(vpa: try fixture.string("vpa"), payeeName: try fixture.string("payeeName"),
                                     amountMinor: try #require(fixture.input["amountMinor"]?.intValue),
                                     invoiceNumber: try fixture.string("invoiceNumber"))
        expectFixture(fixture, .object(["url": .string(url)]))
    }

    // MARK: reminders.md §3

    struct ReminderCandidateInput: Decodable {
        let documentId: String
        let dueDate: String?
        let overrideDays: Int?
        let status: String
    }

    struct ReminderPlanInput: Decodable {
        let businessDefaultDays: Int?
        let cap: Int
        let candidates: [ReminderCandidateInput]
    }

    @Test(arguments: Fixtures.cases(kind: "reminder"))
    func reminder(_ fixture: FixtureCase) throws {
        let input = try JSONDecoder().decode(ReminderPlanInput.self, from: fixture.inputData)
        var candidates: [ReminderCandidate] = []
        for candidate in input.candidates {
            let status = try #require(DocumentStatus(rawValue: candidate.status))
            candidates.append(ReminderCandidate(documentId: candidate.documentId,
                                                dueDate: candidate.dueDate.flatMap(LocalDate.init(iso:)),
                                                overrideDays: candidate.overrideDays, status: status))
        }
        let scheduled = ReminderScheduler.plan(businessDefaultDays: input.businessDefaultDays, cap: input.cap,
                                               candidates: candidates)
        expectFixture(fixture, .object([
            "scheduled": .array(scheduled.map { .object(["documentId": .string($0.documentId),
                                                          "remindOn": .string($0.remindOn.iso)]) }),
        ]))
    }

    // MARK: backup.md §3

    struct BackupInput: Decodable {
        let appSchemaVersion: Int
        let base: String?
        let raw: String?
    }

    @Test(arguments: Fixtures.cases(kind: "backup"))
    func backup(_ fixture: FixtureCase) throws {
        let input = try JSONDecoder().decode(BackupInput.self, from: fixture.inputData)
        let bytes: Data
        if let raw = input.raw {
            bytes = Data(raw.utf8)
        } else {
            let base = try #require(input.base)
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: Spec.root.appending(path: base)))
            let raw = try JSONSerialization.jsonObject(with: fixture.inputData) as? [String: Any] ?? [:]
            var patched: Any = object
            for pointer in raw["remove"] as? [String] ?? [] { patched = JSONPointer.remove(pointer, in: patched) }
            for (pointer, value) in raw["set"] as? [String: Any] ?? [:] {
                patched = JSONPointer.set(pointer, to: value, in: patched)
            }
            bytes = try JSONSerialization.data(withJSONObject: patched)
        }
        switch BackupCodec.validate(bytes, appSchemaVersion: input.appSchemaVersion) {
        case .success(let preview):
            let live = preview.live
            expectFixture(fixture, .object(["live": .object([
                "businesses": .int(Int64(live.businesses)), "clients": .int(Int64(live.clients)),
                "catalogItems": .int(Int64(live.catalogItems)), "numberingSeries": .int(Int64(live.numberingSeries)),
                "documents": .int(Int64(live.documents)), "payments": .int(Int64(live.payments)),
                "assets": .int(Int64(live.assets)),
            ])]))
        case .failure(let error):
            expectFixture(fixture, .object(["error": .string(error.code.rawValue)]))
        }
    }
}

extension FixtureTests {
    // MARK: sync.md §3–4

    struct SeriesInput: Decodable {
        struct Row: Decodable {
            let id: String
            let docType: String
            let lifecycle: String
            let number: String?
        }

        let op: String
        let docType: String?
        let pattern: String?
        let existingPatterns: [String]?
        let counters: [String: Int]?
        let highest: [String: Int]?
        let documents: [Row]?
    }

    @Test(arguments: Fixtures.cases(kind: "series"))
    func series(_ fixture: FixtureCase) throws {
        let input = try JSONDecoder().decode(SeriesInput.self, from: fixture.inputData)
        switch input.op {
        case "deviceSeries":
            let result = SeriesOwnership.deviceSeriesPattern(
                defaultPattern: try #require(input.pattern), docType: DocumentType(rawValue: try #require(input.docType)),
                existingPatterns: input.existingPatterns ?? [])
            switch result {
            case .success(let value):
                expectFixture(fixture, .object(["pattern": .string(value.pattern), "label": .string(value.label)]))
            case .failure(let error):
                expectFixture(fixture, .object(["error": .string(error.rawValue)]))
            }
        case "takeOver":
            let counters = SeriesOwnership.takeOverCounters(input.counters ?? [:], highest: input.highest ?? [:])
            expectFixture(fixture, .object(["counters": .object(counters.mapValues { .int(Int64($0)) })]))
        case "duplicates":
            let rows = (input.documents ?? []).map {
                DuplicateNumbers.Row(id: $0.id, docType: DocumentType(rawValue: $0.docType),
                                     lifecycle: DocumentLifecycle(rawValue: $0.lifecycle), number: $0.number)
            }
            let groups = DuplicateNumbers.find(rows)
            expectFixture(fixture, .object(["groups": .array(groups.map {
                .object(["docType": .string($0.docType.rawValue), "number": .string($0.number),
                         "ids": .array($0.ids.map(JSONValue.string))])
            })]))
        default:
            Issue.record("\(fixture.id): unknown op \(input.op)")
        }
    }
}

extension FixtureTests {
    // MARK: billing.md, Transitions

    struct BillingInput: Decodable {
        let state: String
        let event: String
        let count: Int
    }

    @Test(arguments: Fixtures.cases(kind: "billing"))
    func billing(_ fixture: FixtureCase) throws {
        let input = try JSONDecoder().decode(BillingInput.self, from: fixture.inputData)
        let state = try #require(EntitlementState(rawValue: input.state))
        let event = try #require(EntitlementEvent(rawValue: input.event))
        let next = EntitlementMachine.next(state, event, count: input.count)
        expectFixture(fixture, .object([
            "state": .string(next.rawValue),
            "canIssueInvoice": .bool(EntitlementMachine.canIssueInvoice(next, count: input.count)),
            "remaining": .int(Int64(FreeTier.remaining(count: input.count))),
        ]))
    }
}

/// RFC 6901 pointers over `JSONSerialization` values, for patching backup fixtures.
enum JSONPointer {
    static func set(_ pointer: String, to value: Any, in root: Any) -> Any {
        update(parts(pointer)[...], in: root) { _ in value }
    }

    static func remove(_ pointer: String, in root: Any) -> Any {
        update(parts(pointer)[...], in: root) { _ in nil }
    }

    private static func parts(_ pointer: String) -> [String] {
        pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
            .map { $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~") }
    }

    private static func update(_ path: ArraySlice<String>, in node: Any, _ change: (Any?) -> Any?) -> Any {
        guard let key = path.first else { return change(node) ?? NSNull() }
        let rest = path.dropFirst()
        if var array = node as? [Any], let index = Int(key), array.indices.contains(index) {
            if rest.isEmpty {
                if let value = change(array[index]) { array[index] = value } else { array.remove(at: index) }
            } else {
                array[index] = update(rest, in: array[index], change)
            }
            return array
        }
        var object = node as? [String: Any] ?? [:]
        if rest.isEmpty {
            object[key] = change(object[key])
        } else {
            object[key] = update(rest, in: object[key] ?? [String: Any](), change)
        }
        return object
    }
}
