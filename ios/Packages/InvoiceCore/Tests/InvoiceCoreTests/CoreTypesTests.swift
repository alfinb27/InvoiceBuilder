import Foundation
import Testing
@testable import InvoiceCore

@Suite("LocalDate")
struct LocalDateTests {
    @Test func parsesOnlyRealDates() {
        #expect(LocalDate(iso: "2026-09-19") == LocalDate(year: 2026, month: 9, day: 19))
        #expect(LocalDate(iso: "2024-02-29") != nil)
        #expect(LocalDate(iso: "2026-02-29") == nil)
        #expect(LocalDate(iso: "2026-9-19") == nil)
        #expect(LocalDate(iso: "2026-09-19T00:00") == nil)
        #expect(LocalDate(iso: "2026-13-01") == nil)
        #expect(LocalDate(iso: "20a6-01-01") == nil)
        #expect(LocalDate(year: 1900, month: 2, day: 29) == nil) // not a leap year
        #expect(LocalDate(year: 2000, month: 2, day: 29) != nil)
    }

    @Test func dayArithmeticCrossesMonthsAndYears() throws {
        #expect(LocalDate(daysSinceEpoch: 0).iso == "1970-01-01")
        let date = try #require(LocalDate(iso: "2026-12-31"))
        #expect(date.adding(days: 1).iso == "2027-01-01")
        #expect(date.adding(days: -365).iso == "2025-12-31")
        #expect(try #require(LocalDate(iso: "2024-02-28")).adding(days: 1).iso == "2024-02-29")
        for days in stride(from: -800_000, through: 800_000, by: 997) {
            #expect(LocalDate(daysSinceEpoch: days).daysSinceEpoch == days)
        }
    }

    @Test func todayUsesTheGivenTimeZone() throws {
        // 2026-09-18 20:00 UTC is already 19 September in India (UTC+5:30).
        let instant = Date(timeIntervalSince1970: 1_789_761_600)
        #expect(LocalDate.today(in: TimeZone(identifier: "UTC")!, at: instant).iso == "2026-09-18")
        #expect(LocalDate.today(in: TimeZone(identifier: "Asia/Kolkata")!, at: instant).iso == "2026-09-19")
    }

    @Test func codableAsISOString() throws {
        let date = try #require(LocalDate(iso: "2026-09-19"))
        let data = try JSONEncoder().encode([date])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-09-19"]"#)
        #expect(try JSONDecoder().decode([LocalDate].self, from: data) == [date])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([LocalDate].self, from: Data(#"["19/09/2026"]"#.utf8)) }
    }

    @Test func monthDayParsing() {
        #expect(MonthDay(text: "04-06") == MonthDay(month: 4, day: 6))
        #expect(MonthDay(text: "4-6") == nil)
        #expect(MonthDay(text: "02-30") == nil)
    }
}

@Suite("Decimal strings")
struct DecimalStringTests {
    @Test(arguments: ["0", "18", "-1.5", "0.25", "8.875", "12345678901234567890.5"])
    func acceptsSpecDecimals(_ text: String) {
        #expect(DecimalString.isValid(text))
        #expect(DecimalString.parse(text) != nil)
    }

    @Test(arguments: ["", "-", "01", "1.", ".5", "1.5abc", "1e5", "+1", "1,5", " 1", "--1", "1..2", "٣"])
    func rejectsEverythingElse(_ text: String) {
        #expect(!DecimalString.isValid(text))
        #expect(DecimalString.parse(text) == nil)
    }

    @Test func canonicalForm() {
        #expect(DecimalString.canonical("18.00") == "18")
        #expect(DecimalString.canonical("8.8750") == "8.875")
        #expect(DecimalString.canonical("-0.0") == "0")
        #expect(DecimalString.canonical("100") == "100")
        #expect(DecimalString.canonical("abc") == nil)
        #expect(DecimalString.string(from: Decimal(string: "12.500")!) == "12.5")
        #expect(DecimalString.string(from: Decimal(string: "0.0001")!) == "0.0001")
        #expect(DecimalString.string(from: Decimal(1_000_000)) == "1000000")
    }
}

@Suite("Money")
struct MoneyTests {
    @Test func editingTextKeepsEveryFractionDigit() {
        #expect(MoneyInput.editingText(minor: 123_450, exponent: 2) == "1234.50")
        #expect(MoneyInput.editingText(minor: 5, exponent: 2) == "0.05")
        #expect(MoneyInput.editingText(minor: 1235, exponent: 0) == "1235")
        #expect(MoneyInput.editingText(minor: 1235, exponent: 3) == "1.235")
        #expect(MoneyInput.editingText(minor: -50, exponent: 2) == "-0.50")
    }

    @Test func editingTextParsesBack() throws {
        for minor: Int64 in [0, 1, 99, 100, 123_456_789] {
            #expect(try MoneyInput.parse(MoneyInput.editingText(minor: minor, exponent: 2), exponent: 2).get() == minor)
        }
    }

    @Test func grouping() {
        #expect(SpecFormatter.group("1234567", sizes: [3, 2]) == "12,34,567")
        #expect(SpecFormatter.group("123", sizes: [3, 2]) == "123")
        #expect(SpecFormatter.group("1234", sizes: [3]) == "1,234")
        #expect(SpecFormatter.group("1234", sizes: []) == "1234")
    }

    @Test func currencyCodes() {
        #expect(CurrencyCode.inr.isWellFormed)
        #expect(!CurrencyCode(rawValue: "inr").isWellFormed)
        #expect(!CurrencyCode(rawValue: "RUPEE").isWellFormed)
    }
}

@Suite("Ids and time")
struct IdentityTests {
    @Test func randomIDsAreLowercaseUUIDs() {
        let id = IDGenerator.random.make()
        #expect(id == id.lowercased())
        #expect(UUID(uuidString: id) != nil)
    }

    @Test func sequentialIDsForTests() {
        let ids = IDGenerator.sequential()
        #expect(ids.make() == "00000000-0000-4000-8000-000000000001")
        #expect(ids.make() == "00000000-0000-4000-8000-000000000002")
    }
}

@Suite("Document summaries (documents.md §10)")
struct DocumentSummaryTests {
    static let today = LocalDate(iso: "2026-09-19")!

    static func summary(_ id: String, docType: DocumentType = .invoice, lifecycle: DocumentLifecycle = .issued,
                        dueDate: LocalDate? = nil, currency: CurrencyCode = .inr, totalMinor: Int64,
                        paidMinor: Int64 = 0) -> DocumentSummary {
        DocumentSummary(id: id, docType: docType, number: "N-\(id)", lifecycle: lifecycle, issueDate: today,
                        dueDate: dueDate, validUntil: nil, sentAt: nil, quoteOutcome: nil, clientId: "c1",
                        buyerName: "Client", currency: currency, totalMinor: totalMinor, paidMinor: paidMinor,
                        lineCount: 1, updatedAt: 0)
    }

    @Test func statusAndOutstandingComeFromPaidMinor() {
        let unpaid = Self.summary("d1", totalMinor: 100_000)
        #expect(unpaid.status(today: Self.today) == .issued)
        #expect(unpaid.outstanding() == 100_000)

        let paid = Self.summary("d2", totalMinor: 100_000, paidMinor: 100_000)
        #expect(paid.status(today: Self.today) == .paid)
        #expect(paid.outstanding() == 0)

        let quote = Self.summary("d3", docType: .quote, totalMinor: 100_000)
        #expect(quote.outstanding() == nil)
    }

    @Test func outstandingByCurrencyGroupsAndExcludesPaidVoidAndDrafts() {
        let rows = [
            Self.summary("d1", totalMinor: 100_000, paidMinor: 40_000), // partiallyPaid: 60_000 outstanding
            Self.summary("d2", totalMinor: 50_000), // issued: 50_000 outstanding
            Self.summary("d3", totalMinor: 999, paidMinor: 999), // fully paid: excluded
            Self.summary("d4", lifecycle: .void, totalMinor: 500), // void: excluded
            Self.summary("d5", lifecycle: .draft, totalMinor: 500), // draft: excluded
            Self.summary("d6", docType: .quote, totalMinor: 1_000), // quote: excluded
            Self.summary("d7", currency: CurrencyCode(rawValue: "USD"), totalMinor: 20_000), // a second currency
        ]
        let totals = rows.outstandingByCurrency(today: Self.today)
        #expect(totals.map(\.currency) == [.inr, CurrencyCode(rawValue: "USD")]) // sorted by currency code
        #expect(totals.first { $0.currency == .inr }?.minor == 110_000)
        #expect(totals.first { $0.currency.rawValue == "USD" }?.minor == 20_000)
    }
}
