/// The onboarding steps, in order (`spec/setup.md` §3).
public enum OnboardingStep: Int, CaseIterable, Comparable, Sendable {
    case country
    case registration
    case business
    case bank
    case images

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum BusinessField: Hashable, Sendable {
    case country, homeCurrency
    case registration, genericTaxName, genericTaxPercent
    case name, taxId, addressLine1, region, postalCode, email, pan, companyNumber
    case ifsc, sortCode, iban, swift, upiVpa
    case paymentTermsDays, reminderDaysAfterDue

    /// The onboarding step that shows the field; nil for business-profile-only fields.
    public var step: OnboardingStep? {
        switch self {
        case .country, .homeCurrency: .country
        case .registration, .genericTaxName, .genericTaxPercent: .registration
        case .name, .taxId, .addressLine1, .region, .postalCode, .email, .pan, .companyNumber: .business
        case .ifsc, .sortCode, .iban, .swift, .upiVpa: .bank
        case .paymentTermsDays, .reminderDaysAfterDue: nil
        }
    }
}

/// A business being set up or edited: plain text fields, normalised when saved.
public struct BusinessDraft: Equatable, Sendable {
    public var countryCode: String?
    /// GENERIC only; IN and GB use the config's currency.
    public var homeCurrency: CurrencyCode?
    public var taxRegistration: String?
    /// Index into the config's `productCodes.tiers` (`spec/setup.md` §3.1).
    public var turnoverTier = 0
    /// GENERIC onboarding: the first custom rate (`spec/setup.md` §7).
    public var genericTaxName = "Tax"
    public var genericTaxPercent = ""

    public var name = ""
    public var legalName = ""
    public var taxId = ""
    public var address = AddressDraft()
    public var regionCode: String?
    public var email = ""
    public var phone = ""
    public var website = ""
    public var pan = ""
    public var companyNumber = ""
    public var registeredOffice = ""
    public var lutReference = ""
    public var lutValidUntil: LocalDate?

    public var bankAccountName = ""
    public var bankAccountNumber = ""
    public var bankName = ""
    public var ifsc = ""
    public var sortCode = ""
    public var iban = ""
    public var swift = ""
    public var upiVpa = ""

    public var paymentTermsDays = 15
    public var defaultNotes = ""
    public var defaultTerms = ""
    public var templateId: TemplateID = .modern
    public var accentColor: String?
    public var reminderDaysAfterDue: Int?

    public init() {}

    /// The draft for editing `business` in Settings.
    public init(business: Business, rules: BusinessRules) {
        countryCode = business.countryCode
        homeCurrency = business.homeCurrency
        taxRegistration = business.taxRegistration
        turnoverTier = rules.turnoverTier(for: business.turnoverMinor)
        name = business.name
        legalName = business.legalName ?? ""
        taxId = business.taxId ?? ""
        address = AddressDraft(business.address)
        regionCode = business.address?.regionCode
        email = business.email ?? ""
        phone = business.phone ?? ""
        website = business.website ?? ""
        pan = business.extraIds?.pan ?? ""
        companyNumber = business.extraIds?.companyNumber ?? ""
        registeredOffice = business.extraIds?.registeredOffice ?? ""
        lutReference = business.extraIds?.lutReference ?? ""
        lutValidUntil = business.extraIds?.lutValidUntil
        bankAccountName = business.bank?.accountName ?? ""
        bankAccountNumber = business.bank?.accountNumber ?? ""
        bankName = business.bank?.bankName ?? ""
        ifsc = business.bank?.ifsc ?? ""
        sortCode = business.bank?.sortCode ?? ""
        iban = business.bank?.iban ?? ""
        swift = business.bank?.swift ?? ""
        upiVpa = business.upiVpa ?? ""
        paymentTermsDays = business.paymentTermsDays
        defaultNotes = business.defaultNotes ?? ""
        defaultTerms = business.defaultTerms ?? ""
        templateId = business.templateId
        accentColor = business.accentColor
        reminderDaysAfterDue = business.reminderDaysAfterDue
    }
}

/// Which business fields apply, how they validate and what they derive, for one tax config
/// (`spec/setup.md` §3–4). Pure: the screens only render what these rules say.
public struct BusinessRules: Sendable {
    public let config: TaxConfig

    public init(config: TaxConfig) {
        self.config = config
    }

    public static let paymentTermsRange = 0...365
    public static let reminderDaysRange = 0...60

    // MARK: Registration

    public func registration(_ draft: BusinessDraft) -> TaxRegistration? {
        draft.taxRegistration.flatMap(config.registration)
    }

    public func chargesTax(_ draft: BusinessDraft) -> Bool {
        registration(draft)?.chargesTax ?? false
    }

    /// GENERIC asks for the home currency; IN and GB use the config's.
    public var asksForHomeCurrency: Bool { config.currency == nil }

    public func homeCurrency(_ draft: BusinessDraft) -> CurrencyCode? {
        config.currency ?? draft.homeCurrency
    }

    public var turnoverTiers: [ProductCodeTier] { config.productCodes?.tiers ?? [] }

    /// IN regular and composition dealers pick a turnover tier (it sets the HSN digits they need).
    public func showsTurnoverTier(_ draft: BusinessDraft) -> Bool {
        turnoverTiers.count > 1 && registration(draft)?.requiresTaxId == true
    }

    /// Tier 0 → nil; tier k > 0 → the previous tier's bound + 1 (`spec/setup.md` §3.1).
    public func turnoverMinor(forTier index: Int) -> Int64? {
        guard index > 0, index < turnoverTiers.count, let bound = turnoverTiers[index - 1].maxTurnoverMinor else {
            return nil
        }
        return bound + 1
    }

    public func turnoverTier(for turnoverMinor: Int64?) -> Int {
        guard let turnoverMinor else { return 0 }
        return turnoverTiers.firstIndex { tier in tier.maxTurnoverMinor.map { turnoverMinor <= $0 } ?? true } ?? 0
    }

    /// GENERIC businesses that charge tax name their first rate during onboarding.
    public func asksForFirstTaxRate(_ draft: BusinessDraft) -> Bool {
        config.ratesFrom == .business && chargesTax(draft)
    }

    // MARK: Business details

    /// The config's tax ID when the registration requires one; a free-text tax ID for GENERIC charging registrations.
    public func showsTaxID(_ draft: BusinessDraft) -> Bool {
        guard let registration = registration(draft) else { return false }
        return config.taxIDFormat != nil ? registration.requiresTaxId : registration.chargesTax
    }

    public func requiresTaxID(_ draft: BusinessDraft) -> Bool {
        config.taxIDFormat != nil && registration(draft)?.requiresTaxId == true
    }

    /// Live validation of a typed GSTIN / VAT number; nil when blank or when the config has no format.
    public func taxIDValidation(_ draft: BusinessDraft) -> TaxIDValidation? {
        guard showsTaxID(draft), draft.taxId.trimmedOrNil != nil else { return nil }
        return TaxIDValidator.validate(draft.taxId, config: config)
    }

    /// The state a valid GSTIN names; the region picker is then read-only.
    public func regionFromTaxID(_ draft: BusinessDraft) -> String? {
        guard let validation = taxIDValidation(draft), validation.valid else { return nil }
        return validation.region
    }

    public var showsRegion: Bool { !config.regions.isEmpty }

    public func region(_ draft: BusinessDraft) -> String? {
        showsRegion ? regionFromTaxID(draft) ?? draft.regionCode : nil
    }

    public var isIndia: Bool { config.family == "IN" }
    public var isUK: Bool { config.family == "GB" }

    /// Exports under LUT (IN regular dealers only).
    public func showsLUT(_ draft: BusinessDraft) -> Bool {
        isIndia && registration(draft)?.chargesTax == true
    }

    /// Fills fields that follow from others: an empty PAN from a valid GSTIN (characters 3–12).
    public func applyDerivations(to draft: inout BusinessDraft) {
        if isIndia, draft.pan.trimmedOrNil == nil, let validation = taxIDValidation(draft), validation.valid,
           validation.normalized.count == 15 {
            draft.pan = String(validation.normalized.dropFirst(2).prefix(10))
        }
    }

    // MARK: Validation

    /// Issues for the fields of `steps` (every field, including profile-only ones, when nil).
    public func issues(_ draft: BusinessDraft, steps: Set<OnboardingStep>? = nil) -> [BusinessField: FieldIssue] {
        var issues: [BusinessField: FieldIssue] = [:]
        let includes = { (step: OnboardingStep) in steps?.contains(step) ?? true }

        if includes(.country) {
            if draft.countryCode == nil { issues[.country] = .required }
            if asksForHomeCurrency, draft.homeCurrency == nil { issues[.homeCurrency] = .required }
        }
        if includes(.registration) {
            if registration(draft) == nil { issues[.registration] = .required }
            if asksForFirstTaxRate(draft) {
                if draft.genericTaxName.trimmedOrNil == nil { issues[.genericTaxName] = .required }
                if let issue = CustomRates.percentIssue(draft.genericTaxPercent) { issues[.genericTaxPercent] = issue }
            }
        }
        if includes(.business) {
            if draft.name.trimmedOrNil == nil { issues[.name] = .required }
            if showsTaxID(draft) {
                if let validation = taxIDValidation(draft) {
                    if let error = validation.error { issues[.taxId] = .invalidTaxID(error) }
                } else if requiresTaxID(draft) {
                    issues[.taxId] = .required
                }
            }
            let address = draft.address.issues(countryCode: draft.countryCode ?? "", lineRequired: true)
            if let issue = address.line1 { issues[.addressLine1] = issue }
            if let issue = address.postalCode { issues[.postalCode] = issue }
            if showsRegion, region(draft) == nil { issues[.region] = .required }
            issues.check(.email, draft.email, rule: .email)
            if isIndia { issues.check(.pan, draft.pan, rule: .pan) }
            if isUK { issues.check(.companyNumber, draft.companyNumber, rule: .companyNumberGB) }
        }
        if includes(.bank) {
            if isIndia {
                issues.check(.ifsc, draft.ifsc, rule: .ifsc)
                issues.check(.upiVpa, draft.upiVpa, rule: .upiVpa)
            }
            if isUK { issues.check(.sortCode, draft.sortCode, rule: .sortCode) }
            issues.check(.iban, draft.iban, rule: .iban)
            issues.check(.swift, draft.swift, rule: .bic)
        }
        if steps == nil {
            if !Self.paymentTermsRange.contains(draft.paymentTermsDays) {
                issues[.paymentTermsDays] = .outOfRange(Self.paymentTermsRange)
            }
            if let days = draft.reminderDaysAfterDue, !Self.reminderDaysRange.contains(days) {
                issues[.reminderDaysAfterDue] = .outOfRange(Self.reminderDaysRange)
            }
        }
        return issues
    }

    // MARK: Building the business

    /// A new business from a complete onboarding draft (`spec/setup.md` §3, Finish).
    public func makeBusiness(from draft: BusinessDraft, id: String, now: Int64, today: LocalDate,
                             newID: () -> String) -> Business {
        var business = Business(
            id: id, createdAt: now, updatedAt: now, name: "",
            countryCode: draft.countryCode ?? config.country, taxConfig: config.family,
            taxRegistration: draft.taxRegistration ?? config.registrations[0].id,
            homeCurrency: homeCurrency(draft) ?? CurrencyCode(rawValue: "USD")
        )
        apply(draft, to: &business)
        if config.ratesFrom == .business {
            business.customRates = CustomRates.initialRates(
                chargesTax: chargesTax(draft), taxName: draft.genericTaxName,
                percent: (try? DecimalInput.parse(draft.genericTaxPercent).get()) ?? "0", today: today, newID: newID
            )
        }
        return business
    }

    /// `business` with every editable field taken from `draft` (Settings → Business profile). Country, tax config,
    /// home currency, custom rates and images are left unchanged.
    public func updating(_ business: Business, from draft: BusinessDraft) -> Business {
        var updated = business
        apply(draft, to: &updated)
        return updated
    }

    private func apply(_ draft: BusinessDraft, to business: inout Business) {
        let country = business.countryCode
        business.taxRegistration = draft.taxRegistration ?? business.taxRegistration
        business.name = draft.name.trimmedOrNil ?? business.name
        business.legalName = draft.legalName.trimmedOrNil
        business.address = draft.address.address(countryCode: country, regionCode: region(draft))
        business.email = normalized(draft.email, rule: .email)
        business.phone = draft.phone.trimmedOrNil
        business.website = draft.website.trimmedOrNil
        business.taxId = showsTaxID(draft) ? (taxIDValidation(draft)?.normalized ?? draft.taxId.trimmedOrNil) : nil

        var extra = business.extraIds ?? ExtraIDs()
        extra.pan = isIndia ? normalized(draft.pan, rule: .pan) : nil
        extra.companyNumber = isUK ? normalized(draft.companyNumber, rule: .companyNumberGB) : nil
        extra.registeredOffice = isUK ? draft.registeredOffice.trimmedOrNil : nil
        let lut = showsLUT(draft)
        extra.lutReference = lut ? draft.lutReference.trimmedOrNil?.uppercased() : nil
        extra.lutValidUntil = lut ? draft.lutValidUntil : nil
        business.extraIds = extra.isEmpty ? nil : extra

        business.turnoverMinor = showsTurnoverTier(draft) ? turnoverMinor(forTier: draft.turnoverTier) : nil

        let bank = BankDetails(
            accountName: draft.bankAccountName.trimmedOrNil,
            accountNumber: draft.bankAccountNumber.removingWhitespace.trimmedOrNil,
            bankName: draft.bankName.trimmedOrNil,
            ifsc: isIndia ? normalized(draft.ifsc, rule: .ifsc) : nil,
            sortCode: isUK ? normalized(draft.sortCode, rule: .sortCode) : nil,
            iban: normalized(draft.iban, rule: .iban),
            swift: normalized(draft.swift, rule: .bic)
        )
        business.bank = bank.isEmpty ? nil : bank
        business.upiVpa = isIndia ? normalized(draft.upiVpa, rule: .upiVpa) : nil

        business.paymentTermsDays = draft.paymentTermsDays
        business.defaultNotes = draft.defaultNotes.trimmedOrNil
        business.defaultTerms = draft.defaultTerms.trimmedOrNil
        business.templateId = draft.templateId
        business.accentColor = draft.accentColor
        business.reminderDaysAfterDue = draft.reminderDaysAfterDue
    }
}
