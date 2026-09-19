public enum ClientField: Hashable, Sendable {
    case name, email, taxId, region, billingLine1, billingPostalCode, shippingLine1, shippingPostalCode
}

/// A client being created or edited: plain text fields, normalised when saved.
public struct ClientDraft: Equatable, Sendable {
    public var name = ""
    public var contactName = ""
    public var email = ""
    public var phone = ""
    public var isBusiness = false
    public var countryCode: String
    public var regionCode: String?
    public var taxId = ""
    public var billing = AddressDraft()
    public var hasShippingAddress = false
    public var shipping = AddressDraft()
    public var defaultCurrency: CurrencyCode?
    public var notes = ""

    /// A new client in the business's country.
    public init(countryCode: String) {
        self.countryCode = countryCode
    }

    public init(client: Client) {
        name = client.name
        contactName = client.contactName ?? ""
        email = client.email ?? ""
        phone = client.phone ?? ""
        isBusiness = client.isBusiness
        countryCode = client.countryCode
        regionCode = client.regionCode
        taxId = client.taxId ?? ""
        billing = AddressDraft(client.billingAddress)
        hasShippingAddress = client.shippingAddress != nil
        shipping = AddressDraft(client.shippingAddress)
        defaultCurrency = client.defaultCurrency
        notes = client.notes ?? ""
    }
}

/// Which client fields apply and how they validate (`spec/setup.md` §5).
public struct ClientRules: Sendable {
    public let config: TaxConfig
    public let businessCountry: String

    public init(config: TaxConfig, businessCountry: String) {
        self.config = config
        self.businessCountry = businessCountry
    }

    /// A client in the business's own country.
    public func isDomestic(_ draft: ClientDraft) -> Bool { draft.countryCode == businessCountry }

    /// Domestic clients pick a state when the config has regions (India).
    public func showsRegion(_ draft: ClientDraft) -> Bool { isDomestic(draft) && !config.regions.isEmpty }

    public func showsTaxID(_ draft: ClientDraft) -> Bool { draft.isBusiness }

    /// Domestic B2B tax IDs are checked with the config's format; foreign ones are free text.
    public func validatesTaxID(_ draft: ClientDraft) -> Bool {
        showsTaxID(draft) && isDomestic(draft) && config.taxIDFormat != nil
    }

    public func taxIDValidation(_ draft: ClientDraft) -> TaxIDValidation? {
        guard validatesTaxID(draft), draft.taxId.trimmedOrNil != nil else { return nil }
        return TaxIDValidator.validate(draft.taxId, config: config)
    }

    /// The state a valid domestic GSTIN names; the region picker is then read-only.
    public func regionFromTaxID(_ draft: ClientDraft) -> String? {
        guard showsRegion(draft), let validation = taxIDValidation(draft), validation.valid else { return nil }
        return validation.region
    }

    public func region(_ draft: ClientDraft) -> String? {
        showsRegion(draft) ? regionFromTaxID(draft) ?? draft.regionCode : nil
    }

    public func normalizedTaxID(_ draft: ClientDraft) -> String? {
        guard showsTaxID(draft), let text = draft.taxId.trimmedOrNil else { return nil }
        return taxIDValidation(draft)?.normalized ?? text.uppercased()
    }

    public func issues(_ draft: ClientDraft) -> [ClientField: FieldIssue] {
        var issues: [ClientField: FieldIssue] = [:]
        if draft.name.trimmedOrNil == nil { issues[.name] = .required }
        issues.check(.email, draft.email, rule: .email)
        if let error = taxIDValidation(draft)?.error { issues[.taxId] = .invalidTaxID(error) }
        let billing = draft.billing.issues(countryCode: draft.countryCode, lineRequired: false)
        if let issue = billing.line1 { issues[.billingLine1] = issue }
        if let issue = billing.postalCode { issues[.billingPostalCode] = issue }
        if draft.hasShippingAddress {
            let shipping = draft.shipping.issues(countryCode: draft.countryCode, lineRequired: true)
            if let issue = shipping.line1 { issues[.shippingLine1] = issue }
            if let issue = shipping.postalCode { issues[.shippingPostalCode] = issue }
        }
        return issues
    }

    /// Another live client with the same normalised tax ID (a warning, never a block).
    public func duplicate(of draft: ClientDraft, editingID: String?, among clients: [Client]) -> Client? {
        guard let taxId = normalizedTaxID(draft) else { return nil }
        return clients.first { $0.id != editingID && $0.deletedAt == nil && $0.taxId == taxId }
    }

    public func makeClient(from draft: ClientDraft, id: String, businessID: String, now: Int64) -> Client {
        var client = Client(id: id, createdAt: now, updatedAt: now, businessId: businessID, name: "",
                            countryCode: draft.countryCode)
        apply(draft, to: &client)
        return client
    }

    public func updating(_ client: Client, from draft: ClientDraft) -> Client {
        var updated = client
        apply(draft, to: &updated)
        return updated
    }

    private func apply(_ draft: ClientDraft, to client: inout Client) {
        let region = region(draft)
        client.name = draft.name.trimmedOrNil ?? client.name
        client.contactName = draft.contactName.trimmedOrNil
        client.email = normalized(draft.email, rule: .email)
        client.phone = draft.phone.trimmedOrNil
        client.isBusiness = draft.isBusiness
        client.countryCode = draft.countryCode
        client.regionCode = region
        client.taxId = normalizedTaxID(draft)
        client.billingAddress = draft.billing.address(countryCode: draft.countryCode, regionCode: region)
        client.shippingAddress = draft.hasShippingAddress
            ? draft.shipping.address(countryCode: draft.countryCode, regionCode: region) : nil
        client.defaultCurrency = draft.defaultCurrency
        client.notes = draft.notes.trimmedOrNil
    }
}
