/// The seller (`domain.schema.json#/$defs/Business`). One per user in v1; every other row carries its id.
public struct Business: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var deletedAt: Int64?

    public var name: String
    public var legalName: String?
    public var address: Address?
    public var email: String?
    public var phone: String?
    public var website: String?
    public var countryCode: String
    /// Tax config family: `IN`, `GB` or `GENERIC` (the file name in `spec/tax`).
    public var taxConfig: String
    /// A registration id from that config (`regular`, `composition`, `vatRegistered`, …).
    public var taxRegistration: String
    public var taxId: String?
    public var extraIds: ExtraIDs?
    public var homeCurrency: CurrencyCode
    /// Stands for the turnover tier, never the exact figure (`spec/setup.md` §3.1).
    public var turnoverMinor: Int64?
    public var bank: BankDetails?
    public var upiVpa: String?
    public var paymentTermsDays: Int
    public var defaultNotes: String?
    public var defaultTerms: String?
    public var templateId: TemplateID
    public var accentColor: String?
    public var logoAssetId: String?
    public var signatureAssetId: String?
    public var reminderDaysAfterDue: Int?
    /// Business-defined rates (GENERIC only).
    public var customRates: [TaxRate]?

    public init(id: String, createdAt: Int64 = 0, updatedAt: Int64 = 0, deletedAt: Int64? = nil, name: String,
                legalName: String? = nil, address: Address? = nil, email: String? = nil, phone: String? = nil,
                website: String? = nil, countryCode: String, taxConfig: String, taxRegistration: String,
                taxId: String? = nil, extraIds: ExtraIDs? = nil, homeCurrency: CurrencyCode,
                turnoverMinor: Int64? = nil, bank: BankDetails? = nil, upiVpa: String? = nil,
                paymentTermsDays: Int = 15, defaultNotes: String? = nil, defaultTerms: String? = nil,
                templateId: TemplateID = .modern, accentColor: String? = nil, logoAssetId: String? = nil,
                signatureAssetId: String? = nil, reminderDaysAfterDue: Int? = nil, customRates: [TaxRate]? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.name = name
        self.legalName = legalName
        self.address = address
        self.email = email
        self.phone = phone
        self.website = website
        self.countryCode = countryCode
        self.taxConfig = taxConfig
        self.taxRegistration = taxRegistration
        self.taxId = taxId
        self.extraIds = extraIds
        self.homeCurrency = homeCurrency
        self.turnoverMinor = turnoverMinor
        self.bank = bank
        self.upiVpa = upiVpa
        self.paymentTermsDays = paymentTermsDays
        self.defaultNotes = defaultNotes
        self.defaultTerms = defaultTerms
        self.templateId = templateId
        self.accentColor = accentColor
        self.logoAssetId = logoAssetId
        self.signatureAssetId = signatureAssetId
        self.reminderDaysAfterDue = reminderDaysAfterDue
        self.customRates = customRates
    }

    /// The seller's region: from the address, or the GSTIN prefix (`ENGINE.md` Step 0).
    public func region(config: TaxConfig) -> String? {
        if let region = address?.regionCode?.trimmedOrNil { return region }
        guard let length = config.taxIDFormat?.regionFromPrefix, let taxId, taxId.count >= length else { return nil }
        return String(taxId.prefix(length))
    }
}

/// Other identifiers printed on documents (`extraIds`).
public struct ExtraIDs: Codable, Hashable, Sendable {
    /// India: Permanent Account Number.
    public var pan: String?
    /// UK: Companies House number (Ltd companies).
    public var companyNumber: String?
    /// UK: registered office address, when it differs from the trading address.
    public var registeredOffice: String?
    /// India: Letter of Undertaking ARN, for exports without IGST.
    public var lutReference: String?
    public var lutValidUntil: LocalDate?

    public init(pan: String? = nil, companyNumber: String? = nil, registeredOffice: String? = nil,
                lutReference: String? = nil, lutValidUntil: LocalDate? = nil) {
        self.pan = pan
        self.companyNumber = companyNumber
        self.registeredOffice = registeredOffice
        self.lutReference = lutReference
        self.lutValidUntil = lutValidUntil
    }

    public var isEmpty: Bool {
        [pan, companyNumber, registeredOffice, lutReference].allSatisfy { $0 == nil } && lutValidUntil == nil
    }
}

public struct BankDetails: Codable, Hashable, Sendable {
    public var accountName: String?
    public var accountNumber: String?
    public var bankName: String?
    /// India.
    public var ifsc: String?
    /// UK, stored as `12-34-56`.
    public var sortCode: String?
    public var iban: String?
    public var swift: String?

    public init(accountName: String? = nil, accountNumber: String? = nil, bankName: String? = nil,
                ifsc: String? = nil, sortCode: String? = nil, iban: String? = nil, swift: String? = nil) {
        self.accountName = accountName
        self.accountNumber = accountNumber
        self.bankName = bankName
        self.ifsc = ifsc
        self.sortCode = sortCode
        self.iban = iban
        self.swift = swift
    }

    public var isEmpty: Bool {
        [accountName, accountNumber, bankName, ifsc, sortCode, iban, swift].allSatisfy { $0 == nil }
    }
}
