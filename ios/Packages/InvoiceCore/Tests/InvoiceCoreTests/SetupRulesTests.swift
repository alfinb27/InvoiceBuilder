import Foundation
import Testing
@testable import InvoiceCore

enum TestConfigs {
    static let store = try! TaxConfigStore.bundled()
    static let india = store.latest(family: "IN")!
    static let uk = store.latest(family: "GB")!
    static let generic = store.latest(family: "GENERIC")!
    static let reference = try! ReferenceData.bundled()
    static let today = LocalDate(iso: "2026-09-19")!
}

@Suite("Business rules (setup.md §3–4)")
struct BusinessRulesTests {
    let india = BusinessRules(config: TestConfigs.india)
    let uk = BusinessRules(config: TestConfigs.uk)
    let generic = BusinessRules(config: TestConfigs.generic)

    func indianDraft(registration: String = "regular") -> BusinessDraft {
        var draft = BusinessDraft()
        draft.countryCode = "IN"
        draft.taxRegistration = registration
        draft.name = "  Bharat Web Studio "
        draft.taxId = "29aagcb7383j1z4"
        draft.address = AddressDraft(line1: "12 MG Road", city: "Bengaluru", postalCode: "560 001")
        draft.ifsc = "exmp0001234"
        draft.upiVpa = " BharatWeb@ExampleBank "
        return draft
    }

    @Test func indianRegularDealer() {
        var draft = indianDraft()
        india.applyDerivations(to: &draft)
        #expect(draft.pan == "AAGCB7383J")
        #expect(india.regionFromTaxID(draft) == "29")
        #expect(india.issues(draft).isEmpty)

        let business = india.makeBusiness(from: draft, id: "b1", now: 1_000, today: TestConfigs.today) { "unused" }
        #expect(business.name == "Bharat Web Studio")
        #expect(business.taxConfig == "IN")
        #expect(business.homeCurrency == .inr)
        #expect(business.taxId == "29AAGCB7383J1Z4")
        #expect(business.address == Address(line1: "12 MG Road", city: "Bengaluru", regionCode: "29",
                                            postalCode: "560001", countryCode: "IN"))
        #expect(business.bank == BankDetails(ifsc: "EXMP0001234"))
        #expect(business.upiVpa == "bharatweb@examplebank")
        #expect(business.extraIds == ExtraIDs(pan: "AAGCB7383J"))
        #expect(business.turnoverMinor == nil)
        #expect(business.customRates == nil)
        #expect(business.createdAt == 1_000 && business.updatedAt == 1_000)
        #expect(business.paymentTermsDays == 15 && business.templateId == .modern)
    }

    @Test func stepsReportOnlyTheirOwnFields() {
        var draft = BusinessDraft()
        #expect(india.issues(draft, steps: [.country]) == [.country: .required])
        draft.countryCode = "IN"
        #expect(india.issues(draft, steps: [.country]).isEmpty)
        #expect(india.issues(draft, steps: [.registration]) == [.registration: .required])
        draft.taxRegistration = "regular"
        #expect(india.issues(draft, steps: [.business]) == [
            .name: .required, .taxId: .required, .addressLine1: .required, .region: .required,
        ])
        #expect(india.issues(draft, steps: [.bank, .images]).isEmpty)
    }

    @Test func invalidGSTINBlocksAndDerivesNothing() {
        var draft = indianDraft()
        draft.taxId = "29AAGCB7383J1Z5"
        india.applyDerivations(to: &draft)
        #expect(draft.pan.isEmpty)
        let issues = india.issues(draft, steps: [.business])
        #expect(issues[.taxId] == .invalidTaxID(.checksum))
        #expect(issues[.region] == .required) // no valid GSTIN, no state picked
        draft.regionCode = "29"
        #expect(india.issues(draft, steps: [.business])[.region] == nil)
    }

    @Test func unregisteredIndianBusinessHasNoGSTIN() {
        var draft = indianDraft(registration: "unregistered")
        #expect(!india.showsTaxID(draft))
        #expect(!india.showsTurnoverTier(draft))
        #expect(!india.showsLUT(draft))
        #expect(india.issues(draft)[.region] == .required) // the GSTIN is ignored, so pick the state
        draft.regionCode = "27"
        #expect(india.issues(draft).isEmpty)
        let business = india.makeBusiness(from: draft, id: "b", now: 1, today: TestConfigs.today) { "x" }
        #expect(business.taxId == nil)
        #expect(business.address?.regionCode == "27")
    }

    @Test func turnoverTiers() {
        #expect(india.turnoverTiers.count == 2)
        #expect(india.turnoverMinor(forTier: 0) == nil)
        #expect(india.turnoverMinor(forTier: 1) == 5_000_000_001)
        #expect(india.turnoverTier(for: nil) == 0)
        #expect(india.turnoverTier(for: 5_000_000_000) == 0)
        #expect(india.turnoverTier(for: 5_000_000_001) == 1)
        #expect(india.showsTurnoverTier(indianDraft(registration: "composition")))

        var draft = indianDraft()
        draft.turnoverTier = 1
        let business = india.makeBusiness(from: draft, id: "b", now: 1, today: TestConfigs.today) { "x" }
        #expect(business.turnoverMinor == 5_000_000_001)
    }

    @Test func lutDetailsOnlyForRegularDealers() {
        var draft = indianDraft()
        draft.lutReference = " ad2903260123456 "
        draft.lutValidUntil = LocalDate(iso: "2027-03-31")
        let business = india.makeBusiness(from: draft, id: "b", now: 1, today: TestConfigs.today) { "x" }
        #expect(business.extraIds?.lutReference == "AD2903260123456")
        #expect(business.extraIds?.lutValidUntil == LocalDate(iso: "2027-03-31"))

        draft.taxRegistration = "composition"
        let composition = india.makeBusiness(from: draft, id: "b", now: 1, today: TestConfigs.today) { "x" }
        #expect(composition.extraIds?.lutReference == nil)
    }

    @Test func ukVATRegisteredBusiness() {
        var draft = BusinessDraft()
        draft.countryCode = "GB"
        draft.taxRegistration = "vatRegistered"
        draft.name = "Thames Design Ltd"
        draft.taxId = "980 7806 84"
        draft.address = AddressDraft(line1: "1 Bridge St", city: "London", postalCode: "sw1a1aa")
        draft.companyNumber = "1234567"
        draft.sortCode = "123456"
        draft.bankAccountNumber = "1234 5678"
        draft.ifsc = "IGNORED0001" // not a UK field
        #expect(uk.issues(draft).isEmpty)
        #expect(!uk.showsRegion)

        let business = uk.makeBusiness(from: draft, id: "b", now: 1, today: TestConfigs.today) { "x" }
        #expect(business.homeCurrency == .gbp)
        #expect(business.taxId == "GB980780684")
        #expect(business.address?.postalCode == "SW1A 1AA")
        #expect(business.address?.regionCode == nil)
        #expect(business.extraIds?.companyNumber == "01234567")
        #expect(business.bank == BankDetails(accountNumber: "12345678", sortCode: "12-34-56"))
        #expect(business.upiVpa == nil)
    }

    @Test func ukFieldRulesReportIssues() {
        var draft = BusinessDraft()
        draft.countryCode = "GB"
        draft.taxRegistration = "vatRegistered"
        draft.name = "Thames"
        draft.taxId = "GB123456789"
        draft.address = AddressDraft(line1: "1 Bridge St", postalCode: "12345")
        draft.sortCode = "12-34"
        draft.iban = "GB82WEST12345698765433"
        let issues = uk.issues(draft)
        #expect(issues[.taxId] == .invalidTaxID(.checksum))
        #expect(issues[.postalCode] == .invalid(.postalCodeGB, .format))
        #expect(issues[.sortCode] == .invalid(.sortCode, .format))
        #expect(issues[.iban] == .invalid(.iban, .checksum))
    }

    @Test func genericBusinessNamesItsFirstRate() throws {
        var draft = BusinessDraft()
        draft.countryCode = "US"
        draft.taxRegistration = "registered"
        #expect(generic.asksForHomeCurrency)
        #expect(generic.issues(draft, steps: [.country]) == [.homeCurrency: .required])
        draft.homeCurrency = "USD"
        draft.genericTaxName = "Sales tax"
        #expect(generic.issues(draft, steps: [.registration]) == [.genericTaxPercent: .required])
        draft.genericTaxPercent = "abc"
        #expect(generic.issues(draft, steps: [.registration]) == [.genericTaxPercent: .invalidNumber(.invalid)])
        draft.genericTaxPercent = "150"
        #expect(generic.issues(draft, steps: [.registration]) == [.genericTaxPercent: .outOfRange(0...100)])
        draft.genericTaxPercent = "8.8750"
        #expect(generic.issues(draft, steps: [.registration]).isEmpty)
        #expect(generic.showsTaxID(draft) && !generic.requiresTaxID(draft))

        draft.name = "Main St Bakery"
        draft.address = AddressDraft(line1: "200 Main St")
        draft.taxId = " ein-12 "
        let ids = IDGenerator.sequential(startingAt: 0xabcdef12)
        let business = generic.makeBusiness(from: draft, id: "b", now: 1, today: TestConfigs.today, newID: ids.make)
        #expect(business.taxConfig == "GENERIC")
        #expect(business.homeCurrency == "USD")
        #expect(business.taxId == "ein-12")
        let rates = try #require(business.customRates)
        #expect(rates.count == 2)
        #expect(rates[0].id == "r00000000")
        #expect(rates[0].label == "Sales tax 8.875%")
        #expect(rates[0].components == [RateComponent(code: "SALESTAX", label: "Sales tax", percent: "8.875")])
        #expect(rates[0].effectiveFrom == TestConfigs.today)
        #expect(rates[1] == CustomRates.noTax)
    }

    @Test func genericBusinessNotChargingTaxGetsOnlyNoTax() {
        var draft = BusinessDraft()
        draft.countryCode = "US"
        draft.homeCurrency = "USD"
        draft.taxRegistration = "notRegistered"
        draft.name = "Main St Bakery"
        draft.address = AddressDraft(line1: "200 Main St")
        #expect(!generic.asksForFirstTaxRate(draft))
        #expect(!generic.showsTaxID(draft))
        #expect(generic.issues(draft).isEmpty)
        let business = generic.makeBusiness(from: draft, id: "b", now: 1, today: TestConfigs.today) { "x" }
        #expect(business.customRates == [CustomRates.noTax])
    }

    @Test func profileRangesAndUpdatesKeepIdentity() {
        var draft = indianDraft()
        draft.paymentTermsDays = 400
        draft.reminderDaysAfterDue = 90
        #expect(india.issues(draft)[.paymentTermsDays] == .outOfRange(0...365))
        #expect(india.issues(draft)[.reminderDaysAfterDue] == .outOfRange(0...60))
        #expect(india.issues(draft, steps: Set(OnboardingStep.allCases))[.paymentTermsDays] == nil)

        var original = india.makeBusiness(from: indianDraft(), id: "b1", now: 5, today: TestConfigs.today) { "x" }
        original.logoAssetId = "logo"
        var edit = BusinessDraft(business: original, rules: india)
        #expect(edit.taxId == "29AAGCB7383J1Z4" && edit.regionCode == "29")
        edit.name = "Bharat Web Studio LLP"
        edit.paymentTermsDays = 30
        let updated = india.updating(original, from: edit)
        #expect(updated.id == "b1" && updated.createdAt == 5 && updated.logoAssetId == "logo")
        #expect(updated.name == "Bharat Web Studio LLP" && updated.paymentTermsDays == 30)
        #expect(updated.address == original.address)
    }
}

@Suite("Client rules (setup.md §5)")
struct ClientRulesTests {
    let rules = ClientRules(config: TestConfigs.india, businessCountry: "IN")

    @Test func domesticB2BClientTakesTheStateFromItsGSTIN() {
        var draft = ClientDraft(countryCode: "IN")
        draft.name = "Umesh Foods"
        draft.isBusiness = true
        draft.taxId = "27aapfu0939f1zv"
        draft.regionCode = "29" // overridden by the GSTIN
        draft.billing = AddressDraft(line1: "8 Link Road", city: "Mumbai", postalCode: "400 053")
        #expect(rules.regionFromTaxID(draft) == "27")
        #expect(rules.issues(draft).isEmpty)
        let client = rules.makeClient(from: draft, id: "c1", businessID: "b1", now: 7)
        #expect(client.taxId == "27AAPFU0939F1ZV")
        #expect(client.regionCode == "27")
        #expect(client.billingAddress?.regionCode == "27")
        #expect(client.billingAddress?.postalCode == "400053")
        #expect(client.shippingAddress == nil)
        #expect(client.businessId == "b1" && client.createdAt == 7)
    }

    @Test func invalidDomesticGSTINBlocksSaving() {
        var draft = ClientDraft(countryCode: "IN")
        draft.name = "Rao Traders"
        draft.isBusiness = true
        draft.taxId = "29AAGCB7383J1Z5"
        #expect(rules.issues(draft)[.taxId] == .invalidTaxID(.checksum))
        draft.isBusiness = false // B2C clients have no tax ID, so the typed value is ignored
        #expect(rules.issues(draft)[.taxId] == nil)
        #expect(rules.makeClient(from: draft, id: "c", businessID: "b", now: 1).taxId == nil)
    }

    @Test func foreignClientTaxIDIsFreeText() {
        var draft = ClientDraft(countryCode: "US")
        draft.name = "Acme Inc."
        draft.isBusiness = true
        draft.taxId = " ab-123 "
        draft.regionCode = "29"
        #expect(!rules.showsRegion(draft))
        #expect(!rules.validatesTaxID(draft))
        #expect(rules.issues(draft).isEmpty)
        let client = rules.makeClient(from: draft, id: "c", businessID: "b", now: 1)
        #expect(client.taxId == "AB-123")
        #expect(client.regionCode == nil)
    }

    @Test func addressesNeedALineOnceStarted() {
        var draft = ClientDraft(countryCode: "GB")
        draft.name = "Thames Ltd"
        draft.billing.city = "London"
        draft.billing.postalCode = "12345"
        draft.hasShippingAddress = true
        let issues = rules.issues(draft)
        #expect(issues[.billingLine1] == .required)
        #expect(issues[.billingPostalCode] == .invalid(.postalCodeGB, .format))
        #expect(issues[.shippingLine1] == .required)
    }

    @Test func duplicateTaxIDIsAWarningAmongLiveClients() {
        var draft = ClientDraft(countryCode: "IN")
        draft.name = "Umesh Foods again"
        draft.isBusiness = true
        draft.taxId = "27AAPFU0939F1ZV"
        let existing = Client(id: "c1", businessId: "b", name: "Umesh Foods", countryCode: "IN",
                              taxId: "27AAPFU0939F1ZV", isBusiness: true)
        var deleted = existing
        deleted.id = "c0"
        deleted.deletedAt = 5
        #expect(rules.duplicate(of: draft, editingID: nil, among: [deleted, existing])?.id == "c1")
        #expect(rules.duplicate(of: draft, editingID: "c1", among: [deleted, existing]) == nil)
    }
}

@Suite("Catalogue rules (setup.md §10)")
struct CatalogItemRulesTests {
    static func business(registration: String = "regular", turnover: Int64? = nil) -> Business {
        Business(id: "b1", name: "Bharat", countryCode: "IN", taxConfig: "IN", taxRegistration: registration,
                 homeCurrency: .inr, turnoverMinor: turnover)
    }

    func rules(_ business: Business = CatalogItemRulesTests.business(),
               config: TaxConfig = TestConfigs.india) -> CatalogItemRules {
        CatalogItemRules(config: config, business: business, currencies: TestConfigs.reference.currencies,
                         units: TestConfigs.reference.units, today: TestConfigs.today)
    }

    @Test func offersRatesInForceTodayAndKeepsAnOldSavedRate() {
        let rules = rules()
        let choices = rules.rateChoices(selected: nil).map(\.id)
        #expect(!choices.contains("gst_12") && choices.contains("gst_18") && choices.contains("gst_40"))
        #expect(rules.rateChoices(selected: "gst_12").map(\.id).last == "gst_12")
        #expect(!rules.isInForce(rateID: "gst_12"))
        #expect(rules.isInForce(rateID: "gst_18"))
    }

    @Test func validatesEveryField() {
        var draft = CatalogItemDraft()
        #expect(rules().issues(draft) == [.name: .required, .price: .required, .rate: .required])
        draft.name = "Tea leaves"
        draft.unit = "XXX"
        draft.priceText = "12.345"
        draft.rateId = "gst_99"
        draft.productCode = "09A2"
        #expect(rules().issues(draft) == [
            .unit: .required, .price: .invalidNumber(.tooManyDecimals), .rate: .required,
            .productCode: .invalid(.hsnSac, .format),
        ])
    }

    @Test func buildsANormalisedItem() {
        var draft = CatalogItemDraft()
        draft.name = " Website development "
        draft.priceText = "1,234.50"
        draft.rateId = "gst_18"
        draft.productCode = "99 83 14"
        draft.priceIncludesTax = true
        let item = rules().makeItem(from: draft, id: "i1", now: 3)
        #expect(item.name == "Website development")
        #expect(item.unitPriceMinor == 123_450 && item.currency == .inr)
        #expect(item.unit == "OTH" && item.kind == .service)
        #expect(item.productCode == "998314")
        #expect(item.priceIncludesTax)

        let editing = CatalogItemDraft(item: item, exponent: 2)
        #expect(editing.priceText == "1234.50")
    }

    @Test func dealersNotChargingTaxHaveNoInclusivePrices() {
        let rules = rules(Self.business(registration: "composition"))
        #expect(!rules.showsInclusivePrice)
        var draft = CatalogItemDraft()
        draft.name = "Milk"
        draft.priceText = "56"
        draft.rateId = "exempt"
        draft.priceIncludesTax = true
        #expect(!rules.makeItem(from: draft, id: "i", now: 1).priceIncludesTax)
    }

    @Test func productCodeDigitsFollowTheTurnoverTier() {
        #expect(rules().requiredProductCodeDigits! == (4, 0))
        #expect(rules(Self.business(turnover: 5_000_000_001)).requiredProductCodeDigits! == (6, 6))
        let ukBusiness = Business(id: "b", name: "Thames", countryCode: "GB", taxConfig: "GB",
                                  taxRegistration: "vatRegistered", homeCurrency: .gbp)
        let ukRules = rules(ukBusiness, config: TestConfigs.uk)
        #expect(ukRules.requiredProductCodeDigits == nil)
        #expect(ukRules.productCodeRule == nil)
    }

    @Test func genericBusinessesUseTheirOwnRates() {
        var business = Business(id: "b", name: "Bakery", countryCode: "US", taxConfig: "GENERIC",
                                taxRegistration: "registered", homeCurrency: "USD")
        business.customRates = [CustomRateDraft(name: "Sales tax", percent: "8.875").makeRate(id: "r1", today: TestConfigs.today),
                                CustomRates.noTax]
        let rules = rules(business, config: TestConfigs.generic)
        #expect(rules.rateChoices(selected: nil).map(\.id) == ["r1", "none"])
    }

    @Test func switchingKindMovesADefaultUnit() {
        var draft = CatalogItemDraft()
        draft.setKind(.goods)
        #expect(draft.unit == "NOS")
        draft.unit = "KGS"
        draft.setKind(.service)
        #expect(draft.unit == "KGS")
    }
}

@Suite("Numbering series settings (setup.md §6)")
struct NumberingSeriesRulesTests {
    let rules = NumberingSeriesRules(config: TestConfigs.india, today: TestConfigs.today, deviceID: "device-a")
    let series = NumberingSeries(id: "s1", businessId: "b1", docType: .invoice, label: "Invoices",
                                 pattern: "INV/{fy}/{seq:4}", reset: .fiscalYear, ownerDeviceId: "device-a")

    @Test func previewsTheNextNumber() throws {
        #expect(try rules.nextNumber(series).get() == NumberingResult(number: "INV/26-27/0001", periodKey: "FY2026"))
        var draft = NumberingSeriesDraft(series: series, periodKey: "FY2026")
        #expect(draft.nextNumberText == "1")
        draft.nextNumberText = "142"
        #expect(rules.issues(draft).isEmpty)
        #expect(try rules.preview(draft)?.get().number == "INV/26-27/0142")
        let updated = rules.updating(series, from: draft)
        #expect(updated.counters == ["FY2026": 142])
        #expect(try rules.nextNumber(updated).get().number == "INV/26-27/0142")
    }

    @Test func rejectsPatternsThatCannotNumberDocuments() {
        var draft = NumberingSeriesDraft(series: series, periodKey: "FY2026")
        draft.pattern = "INVOICE/{fyLong}/{seq:5}"
        #expect(rules.issues(draft)[.pattern] == .invalidNumbering(.numberTooLong))
        draft.pattern = "INV-{seq:4}-{foo}"
        #expect(rules.issues(draft)[.pattern] == .invalidPattern([.unknownToken("{foo}")]))
        draft.pattern = "INV"
        #expect(rules.issues(draft)[.pattern] == .invalidPattern([.missingSequence]))
        draft.pattern = "INV#{seq:3}"
        #expect(rules.issues(draft)[.pattern] == .invalidNumbering(.numberInvalidChars))
    }

    @Test func nextNumberMustBePositive() {
        var draft = NumberingSeriesDraft(series: series, periodKey: "FY2026")
        draft.nextNumberText = "0"
        #expect(rules.issues(draft)[.nextNumber] == .invalidNumber(.invalid))
        draft.nextNumberText = " "
        #expect(rules.issues(draft)[.nextNumber] == .required)
        draft.label = "  "
        #expect(rules.issues(draft)[.label] == .required)
    }

    @Test func onlyTheOwnerEdits() {
        #expect(rules.isEditable(series))
        var other = series
        other.ownerDeviceId = "device-b"
        #expect(!rules.isEditable(other))
    }

    @Test func patternIssues() {
        #expect(Numbering.issues(inPattern: "INV/{fy}/{seq:4}").isEmpty)
        #expect(Numbering.issues(inPattern: "{yyyy}{mm}-{seq:3}").isEmpty)
        #expect(Numbering.issues(inPattern: "{seq:4}-{seq:2}") == [.multipleSequences])
        #expect(Numbering.issues(inPattern: "{seq:0}") == [.invalidSequenceWidth("{seq:0}")])
        #expect(Numbering.issues(inPattern: "A{seq}") == [.missingSequence, .unknownToken("{seq}")])
        #expect(Numbering.issues(inPattern: "A{seq:3") == [.missingSequence]) // unclosed brace is literal
    }
}

@Suite("Custom rates (setup.md §7)")
struct CustomRatesTests {
    @Test func ids() {
        #expect(CustomRates.rateID(fromUUID: "3D0DD937-B470-5C97-9798-45FB0CCA9D46") == "r3d0dd937")
        let taken = [TaxRate(id: "r3d0dd937", category: .standard, label: "Tax 5%", effectiveFrom: TestConfigs.today)]
        #expect(CustomRates.rateID(fromUUID: "3D0DD937-B470-5C97-9798-45FB0CCA9D46", existing: taken)
                == "r3d0dd937b4705c97979845fb0cca9d46")
        #expect(CustomRates.componentCode(forName: "Sales tax") == "SALESTAX")
        #expect(CustomRates.componentCode(forName: "GST (state) 2026 extra") == "GSTSTATE2026")
        #expect(CustomRates.componentCode(forName: "税") == "TAX")
    }

    @Test func percents() {
        #expect(CustomRates.percentIssue("") == .required)
        #expect(CustomRates.percentIssue("-1") == .invalidNumber(.invalid))
        #expect(CustomRates.percentIssue("100.01") == .outOfRange(0...100))
        #expect(CustomRates.percentIssue("100") == nil)
        #expect(CustomRates.percentIssue("0") == nil)
    }

    @Test func twoComponentRate() {
        var draft = CustomRateDraft(name: "Tax A", percent: "5")
        draft.hasSecondComponent = true
        draft.secondName = "Tax B"
        draft.secondPercent = "10.0"
        draft.secondIsCompound = true
        #expect(draft.issues.isEmpty)
        let rate = draft.makeRate(id: "rabc", today: TestConfigs.today)
        #expect(rate.label == "Tax A 5% + Tax B 10% (compound)")
        #expect(rate.components == [RateComponent(code: "TAXA", label: "Tax A", percent: "5"),
                                    RateComponent(code: "TAXB", label: "Tax B", percent: "10", compound: true)])
        #expect(CustomRateDraft(rate: rate) == draft.normalizedForComparison)
    }
}

extension CustomRateDraft {
    /// The draft as read back from a stored rate (percents canonical).
    var normalizedForComparison: CustomRateDraft {
        var copy = self
        copy.percent = (try? DecimalInput.parse(percent).get()) ?? percent
        copy.secondPercent = (try? DecimalInput.parse(secondPercent).get()) ?? secondPercent
        return copy
    }
}

@Suite("Business setup (setup.md §2, §6)")
struct BusinessSetupTests {
    @Test func defaultSeriesComeFromTheConfig() {
        let ids = IDGenerator.sequential()
        let series = BusinessSetup.defaultSeries(businessID: "b1", config: TestConfigs.india, ownerDeviceID: "d1",
                                                 now: 9, newID: ids.make)
        #expect(series.map(\.docType) == [.invoice, .quote])
        #expect(series.map(\.pattern) == ["INV/{fy}/{seq:4}", "QT/{fy}/{seq:4}"])
        #expect(series.map(\.label) == ["Invoices", "Quotes"])
        #expect(series.allSatisfy { $0.reset == .fiscalYear && $0.ownerDeviceId == "d1" && $0.counters.isEmpty })

        let uk = BusinessSetup.defaultSeries(businessID: "b1", config: TestConfigs.uk, ownerDeviceID: "d1", now: 9,
                                             newID: ids.make)
        #expect(uk.map(\.pattern) == ["INV-{seq:4}", "QT-{seq:4}"] && uk[0].reset == .never)
    }

    @Test func activeBusinessResolution() {
        func business(_ id: String, createdAt: Int64, deleted: Bool = false) -> Business {
            Business(id: id, createdAt: createdAt, deletedAt: deleted ? 1 : nil, name: id, countryCode: "IN",
                     taxConfig: "IN", taxRegistration: "regular", homeCurrency: .inr)
        }
        let all = [business("b", createdAt: 5), business("a", createdAt: 5), business("c", createdAt: 1, deleted: true)]
        #expect(BusinessSetup.activeBusiness(preferences: .init(activeBusinessId: "b"), businesses: all)?.id == "b")
        #expect(BusinessSetup.activeBusiness(preferences: .init(activeBusinessId: "c"), businesses: all)?.id == "a")
        #expect(BusinessSetup.activeBusiness(preferences: .init(), businesses: all)?.id == "a")
        #expect(BusinessSetup.activeBusiness(preferences: .init(), businesses: []) == nil)
    }

    @Test func searchMatchesAnyFieldAndSortsByName() {
        let clients = [
            Client(id: "2", businessId: "b", name: "umesh foods", email: "accounts@umesh.in", countryCode: "IN"),
            Client(id: "1", businessId: "b", name: "Rao Traders", countryCode: "IN", taxId: "29AABCR1234C1ZU"),
            Client(id: "3", businessId: "b", name: "Acme Inc.", contactName: "Rao Wile", countryCode: "US"),
        ]
        #expect(SetupSearch.clients(clients, matching: "").map(\.id) == ["3", "1", "2"])
        #expect(SetupSearch.clients(clients, matching: " RAO ").map(\.id) == ["3", "1"])
        #expect(SetupSearch.clients(clients, matching: "29aab").map(\.id) == ["1"])
        #expect(SetupSearch.clients(clients, matching: "@umesh").map(\.id) == ["2"])

        let items = [CatalogItem(id: "i1", businessId: "b", name: "Tea leaves", unit: "KGS", unitPriceMinor: 24_000,
                                 currency: .inr, rateId: "gst_5", productCode: "0902")]
        #expect(SetupSearch.items(items, matching: "0902").count == 1)
        #expect(SetupSearch.items(items, matching: "coffee").isEmpty)
    }
}

/// `spec/setup.md` §2, ADR-0019: a database copied onto another device by an OS backup takes a new device id.
@Suite("Device identity")
struct DeviceIdentityTests {
    @Test func noRowCreatesOne() {
        #expect(DeviceIdentity.check(rowID: nil, marker: .missing) == .create)
        #expect(DeviceIdentity.check(rowID: nil, marker: .found("old")) == .create) // reinstalled: the database is new
    }

    @Test func aMatchingMarkerKeepsTheRow() {
        #expect(DeviceIdentity.check(rowID: "d1", marker: .found("d1")) == .keep)
    }

    @Test func aMissingOrDifferentMarkerReplacesTheId() {
        #expect(DeviceIdentity.check(rowID: "d1", marker: .missing) == .replace) // restored onto a new phone
        #expect(DeviceIdentity.check(rowID: "d1", marker: .found("d2")) == .replace) // another device's database
    }

    @Test func anUnreadableMarkerNeverChangesTheId() {
        #expect(DeviceIdentity.check(rowID: "d1", marker: .unreadable) == .keep)
    }
}
