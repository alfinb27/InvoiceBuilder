import Foundation
import Testing
@testable import InvoiceCore

/// Runs the golden fixtures that InvoiceCore implements so far. Kinds still waiting for Phase 2a are listed in
/// `pendingKinds`, so the fixture count stays an explicit parity metric (`docs/parity.md`).
@Suite("Spec fixtures")
struct FixtureTests {
    static let implementedKinds: Set = ["validation", "field", "input", "format", "numbering"]
    /// Tax engine, rounding, allocation, words, status and UPI arrive with Phase 2a.
    static let pendingKinds: Set = ["tax", "rounding", "distribute", "words", "status", "upi"]

    static let configs = try! TaxConfigStore.bundled()
    static let formatter = SpecFormatter(currencies: try! ReferenceData.bundled().currencies)

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
}
