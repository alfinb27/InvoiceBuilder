import Foundation
import Testing
@testable import InvoiceCore

@Suite("Loading the bundled spec")
struct SpecLoadingTests {
    @Test func bundledCopyMatchesTheSpec() throws {
        let folders = ["tax", "reference", "design", "pdf/labels"]
        for folder in folders {
            let source = Spec.root.appending(path: folder)
            let files = try FileManager.default.contentsOfDirectory(atPath: source.path).filter { $0.hasSuffix(".json") }
            #expect(!files.isEmpty)
            for file in files {
                let original = try Data(contentsOf: source.appending(path: file))
                let bundled = try SpecResources.data("\(folder)/\(file)")
                #expect(original == bundled, "\(folder)/\(file) differs from the bundled copy; run `make sync-spec`")
            }
        }
    }

    @Test func loadsEveryTaxConfig() throws {
        let store = try TaxConfigStore.bundled()
        #expect(store.configs.map(\.ref) == ["GB@2026-09-19", "GENERIC@2026-09-19", "IN@2025-09-22"])

        let india = try #require(store.latest(family: "IN"))
        #expect(india.currency == .inr)
        #expect(india.fiscalYearStart == MonthDay(month: 4, day: 1))
        #expect(india.regions.count == 39)
        #expect(india.activeRegionsByName.count == 37)
        #expect(india.foreignRegion == "96")
        #expect(india.registrations.map(\.id) == ["regular", "composition", "unregistered"])
        #expect(india.numbering.maxLength == 16)
        #expect(india.rounding.grandTotal?.roundToMinor == 100)
        if case .list(let components) = india.componentRules[0].components {
            #expect(components.map(\.code) == ["CGST", "$localComponent"])
        } else {
            Issue.record("IN intra-state rule should list its components")
        }

        let generic = try #require(store.latest(family: "GENERIC"))
        #expect(generic.ratesFrom == .business)
        #expect(generic.currency == nil)
        #expect(generic.componentRules[0].components == .fromRate)
    }

    @Test func everyFixtureConfigRefResolves() throws {
        let store = try TaxConfigStore.bundled()
        let refs = Fixtures.all.compactMap { fixture -> String? in
            if fixture.kind == "validation" { return fixture.input["config"]?.stringValue }
            return nil
        }
        #expect(!refs.isEmpty)
        for ref in Set(refs) { #expect(store.config(ref: ref) != nil, "unknown config \(ref)") }

        // Tax fixtures name their config at the case level, outside `input`.
        let taxFiles = try FileManager.default.contentsOfDirectory(
            at: Spec.root.appending(path: "fixtures/tax"), includingPropertiesForKeys: nil)
        for file in taxFiles where file.pathExtension == "json" {
            let json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
            guard case .array(let cases)? = json["cases"] else { continue }
            for taxCase in cases {
                let ref = try #require(taxCase["config"]?.stringValue)
                #expect(store.config(ref: ref) != nil, "unknown config \(ref) in \(file.lastPathComponent)")
            }
        }
    }

    @Test func latestConfigFollowsTheDate() throws {
        let store = try TaxConfigStore.bundled()
        #expect(store.latest(family: "GB", on: LocalDate(iso: "2030-01-01"))?.ref == "GB@2026-09-19")
        // Every version is newer than the date: fall back to the oldest rather than nothing.
        #expect(store.latest(family: "GB", on: LocalDate(iso: "2020-01-01"))?.ref == "GB@2026-09-19")
        #expect(store.latest(family: "XX") == nil)
        #expect(TaxConfigStore.family(forCountry: "IN") == "IN")
        #expect(TaxConfigStore.family(forCountry: "GB") == "GB")
        #expect(TaxConfigStore.family(forCountry: "US") == "GENERIC")
    }

    @Test func ratesInForceFollowTheirEffectiveDates() throws {
        let india = try #require(try TaxConfigStore.bundled().latest(family: "IN"))
        let before = india.ratesInForce(on: LocalDate(iso: "2025-09-21")!, customRates: nil).map(\.id)
        let after = india.ratesInForce(on: LocalDate(iso: "2025-09-22")!, customRates: nil).map(\.id)
        #expect(before.contains("gst_12") && !before.contains("gst_40"))
        #expect(!after.contains("gst_12") && after.contains("gst_40"))
        #expect(after.first == "gst_0") // config order
    }

    @Test func loadsReferenceData() throws {
        let reference = try ReferenceData.bundled()
        #expect(reference.countries.count == 249)
        #expect(reference.country(code: "IN")?.name == "India")
        #expect(reference.currencies[.inr]?.grouping == [3, 2])
        #expect(reference.currencies.exponent(of: "KWD") == 3)
        #expect(reference.currencies.exponent(of: "XYZ") == 2)
        #expect(reference.unit(id: "NOS") != nil && reference.unit(id: "OTH") != nil)
        #expect(reference.countriesByName.first?.name == "Afghanistan")
    }
}
