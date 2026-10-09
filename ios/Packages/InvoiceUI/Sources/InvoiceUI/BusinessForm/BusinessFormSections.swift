import InvoiceCore
import SwiftUI

// Business form sections shared by onboarding (steps 2–4) and Settings → Business profile. Which fields appear and
// how they validate comes from `BusinessRules` (`spec/setup.md` §3–4).

/// Registration type, India's turnover tier and (GENERIC onboarding) the first tax rate.
struct RegistrationSections: View {
    @Binding var draft: BusinessDraft
    let rules: BusinessRules
    let formatter: SpecFormatter
    let issue: (BusinessField) -> FieldIssue?
    /// Onboarding only: GENERIC businesses name their first rate here; later they edit rates in Settings.
    var asksForFirstRate = true

    var body: some View {
        Section {
            ForEach(rules.config.registrations) { registration in
                Button {
                    draft.taxRegistration = registration.id
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(registration.label).foregroundStyle(Theme.textPrimary)
                            Text(Self.help(family: rules.config.family, registration: registration.id))
                                .font(Theme.Fonts.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if draft.taxRegistration == registration.id {
                            Image(systemName: "checkmark").foregroundStyle(Theme.brand).fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(draft.taxRegistration == registration.id ? .isSelected : [])
            }
            if let issue = issue(.registration) {
                IssueText(message: IssueMessages.text(issue, field: "registration type"))
            }
        } header: {
            Text("\(rules.config.labels.taxName) registration")
        } footer: {
            Text("This decides whether your invoices charge \(rules.config.labels.taxName) and what they're called.")
        }

        if rules.showsTurnoverTier(draft) {
            Section {
                Picker("Turnover", selection: $draft.turnoverTier) {
                    ForEach(rules.turnoverTiers.indices, id: \.self) { index in
                        Text(tierLabel(index)).tag(index)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Turnover in the previous financial year")
            } footer: {
                Text(tierFooter)
            }
        }

        if asksForFirstRate, rules.asksForFirstTaxRate(draft) {
            Section {
                FormTextField(title: "Tax name", text: $draft.genericTaxName, prompt: "Sales tax",
                              issue: message(.genericTaxName, "tax name"), capitalization: .words)
                FormTextField(title: "Rate (%)", text: $draft.genericTaxPercent, prompt: "8.875",
                              issue: message(.genericTaxPercent, "rate"), keyboard: .decimalPad)
            } header: {
                Text("Your tax")
            } footer: {
                Text("You can add more rates, or a second tax, later in Settings.")
            }
        }
    }

    private func message(_ field: BusinessField, _ name: String) -> String? {
        issue(field).map { IssueMessages.text($0, field: name) }
    }

    private var tierFooter: String { TurnoverText(rules: rules, formatter: formatter).footer(tier: draft.turnoverTier) }

    private func tierLabel(_ index: Int) -> String { TurnoverText(rules: rules, formatter: formatter).label(index) }

    static func help(family: String, registration: String) -> String {
        switch "\(family).\(registration)" {
        case "IN.regular": "You charge GST and issue tax invoices."
        case "IN.composition": "You pay tax under the composition scheme and issue bills of supply, without GST."
        case "IN.unregistered": "You're not registered for GST, so your invoices show no GST."
        case "GB.vatRegistered": "You charge VAT and issue VAT invoices."
        case "GB.notRegistered": "You're not VAT registered, so your invoices show no VAT."
        case "GENERIC.registered": "You add tax to your invoices."
        case "GENERIC.notRegistered": "Your invoices show no tax."
        default: ""
        }
    }
}

/// India's turnover bands, worded from the config's tier bounds (`spec/setup.md` §3.1).
struct TurnoverText {
    let rules: BusinessRules
    let formatter: SpecFormatter

    /// "Up to ₹5 crore" / "More than ₹5 crore".
    func label(_ index: Int) -> String {
        let tiers = rules.turnoverTiers
        let upper = tiers[index].maxTurnoverMinor
        let lower = index > 0 ? tiers[index - 1].maxTurnoverMinor : nil
        switch (lower, upper) {
        case (nil, let upper?): return "Up to \(amount(upper))"
        case (let lower?, nil): return "More than \(amount(lower))"
        case (let lower?, let upper?): return "\(amount(lower)) to \(amount(upper))"
        case (nil, nil): return "Any turnover"
        }
    }

    func footer(tier: Int) -> String {
        let digits = rules.turnoverTiers[safe: tier].map { tier in
            tier.b2bDigits == 0 ? "no HSN/SAC code" : "a \(tier.b2bDigits)-digit HSN/SAC code"
        } ?? ""
        return "Your B2B invoices then need \(digits) on every line. We only store the band, never the amount."
    }

    private func amount(_ minor: Int64) -> String {
        let currency = rules.config.currency ?? "USD"
        if currency == .inr {
            let symbol = formatter.currencies[.inr]?.symbol ?? "₹"
            if minor % 1_000_000_000 == 0 { return "\(symbol)\(minor / 1_000_000_000) crore" }
            if minor % 10_000_000 == 0 { return "\(symbol)\(minor / 10_000_000) lakh" }
        }
        return formatter.money(minor, currency: currency, homeCurrency: currency)
    }
}

/// Name, tax ID, address, contact and other identifiers.
struct BusinessDetailsSections: View {
    @Binding var draft: BusinessDraft
    let rules: BusinessRules
    let issue: (BusinessField) -> FieldIssue?
    let taxIDFeedback: TaxIDFeedback?

    private var labels: TaxLabels { rules.config.labels }

    var body: some View {
        Section("Business") {
            FormTextField(title: "Business name", text: $draft.name, prompt: "As shown on your invoices",
                          issue: message(.name, "business name"), capitalization: .words,
                          contentType: .organizationName)
            FormTextField(title: "Legal name (optional)", text: $draft.legalName,
                          prompt: "If different from the business name", capitalization: .words)
        }

        if rules.showsTaxID(draft) {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    FormTextField(title: taxIDTitle, text: $draft.taxId, prompt: taxIDPrompt,
                                  issue: taxIDIssue, capitalization: .characters, autocorrect: false)
                    if case .valid(let region) = taxIDFeedback {
                        SuccessText(message: region.map { "Valid · \($0)" } ?? "Valid")
                    } else if case .invalid(let problem) = taxIDFeedback, taxIDIssue == nil {
                        IssueText(message: problem)
                    }
                }
            } footer: {
                if rules.isIndia { Text("Your state is read from the first two digits.") }
            }
        }

        Section("Address") {
            FormTextField(title: "Address line 1", text: $draft.address.line1, prompt: "Building, street",
                          issue: message(.addressLine1, "address"), capitalization: .words,
                          contentType: .streetAddressLine1)
            FormTextField(title: "Address line 2 (optional)", text: $draft.address.line2, capitalization: .words,
                          contentType: .streetAddressLine2)
            FormTextField(title: rules.isIndia ? "City or town" : "Town or city", text: $draft.address.city,
                          capitalization: .words, contentType: .addressCity)
            FormTextField(title: rules.isIndia ? "PIN code" : "Postcode", text: $draft.address.postalCode,
                          issue: message(.postalCode, "postcode"),
                          keyboard: rules.isIndia ? .numberPad : .default,
                          capitalization: .characters, contentType: .postalCode, autocorrect: false)
            if rules.showsRegion {
                RegionPicker(title: labels.regionName ?? "State", selection: $draft.regionCode,
                             regions: rules.config.activeRegionsByName,
                             lockedTo: rules.regionFromTaxID(draft), lockedReason: "From your \(labels.taxIdName)",
                             issue: message(.region, labels.regionName ?? "state"))
            }
        }

        Section("Contact (optional)") {
            FormTextField(title: "Email", text: $draft.email, prompt: "billing@example.com",
                          issue: message(.email, "email"), keyboard: .emailAddress, capitalization: .never,
                          contentType: .emailAddress, autocorrect: false)
            FormTextField(title: "Phone", text: $draft.phone, keyboard: .phonePad, contentType: .telephoneNumber)
            FormTextField(title: "Website", text: $draft.website, keyboard: .URL, capitalization: .never,
                          contentType: .URL, autocorrect: false)
        }

        if rules.isIndia {
            Section {
                FormTextField(title: "PAN (optional)", text: $draft.pan, prompt: "ABCDE1234F",
                              issue: message(.pan, "PAN"), capitalization: .characters, autocorrect: false)
            } header: {
                Text("Other IDs")
            } footer: {
                Text("Filled in from your GSTIN when possible.")
            }
        }

        if rules.isUK {
            Section {
                FormTextField(title: "Company number (optional)", text: $draft.companyNumber, prompt: "01234567",
                              issue: message(.companyNumber, "company number"), capitalization: .characters,
                              autocorrect: false)
                FormTextField(title: "Registered office (optional)", text: $draft.registeredOffice,
                              prompt: "If different from the address above", capitalization: .words, axis: .vertical)
            } header: {
                Text("Limited company")
            } footer: {
                Text("Limited companies show their company number and registered office on invoices.")
            }
        }
    }

    private var taxIDTitle: String { rules.requiresTaxID(draft) ? labels.taxIdName : "\(labels.taxIdName) (optional)" }

    private var taxIDPrompt: String {
        switch rules.config.family {
        case "IN": "29ABCDE1234F1Z5"
        case "GB": "GB123456789"
        default: "Your tax registration number"
        }
    }

    private var taxIDIssue: String? {
        issue(.taxId).map { IssueMessages.text($0, field: labels.taxIdName, taxIDName: labels.taxIdName) }
    }

    private func message(_ field: BusinessField, _ name: String) -> String? {
        issue(field).map { IssueMessages.text($0, field: name) }
    }
}

/// Bank account, international details and UPI (all optional).
struct BankSections: View {
    @Binding var draft: BusinessDraft
    let rules: BusinessRules
    let issue: (BusinessField) -> FieldIssue?

    var body: some View {
        Section {
            FormTextField(title: "Account name", text: $draft.bankAccountName, capitalization: .words)
            FormTextField(title: "Account number", text: $draft.bankAccountNumber, keyboard: .numberPad,
                          autocorrect: false)
            FormTextField(title: "Bank name", text: $draft.bankName, capitalization: .words)
            if rules.isIndia {
                FormTextField(title: "IFSC", text: $draft.ifsc, prompt: "SBIN0001234", issue: message(.ifsc),
                              capitalization: .characters, autocorrect: false)
            }
            if rules.isUK {
                FormTextField(title: "Sort code", text: $draft.sortCode, prompt: "12-34-56", issue: message(.sortCode),
                              keyboard: .numbersAndPunctuation, autocorrect: false)
            }
        } header: {
            Text("Bank account")
        } footer: {
            Text("Printed on your invoices so clients know where to pay. Everything here is optional.")
        }

        if rules.isIndia {
            Section {
                FormTextField(title: "UPI ID", text: $draft.upiVpa, prompt: "yourname@bank", issue: message(.upiVpa),
                              keyboard: .emailAddress, capitalization: .never, autocorrect: false)
            } header: {
                Text("UPI")
            } footer: {
                Text("Adds a scan-to-pay UPI QR code to your invoices.")
            }
        }

        Section("International payments (optional)") {
            FormTextField(title: "IBAN", text: $draft.iban, issue: message(.iban), capitalization: .characters,
                          autocorrect: false)
            FormTextField(title: "SWIFT / BIC", text: $draft.swift, issue: message(.swift),
                          capitalization: .characters, autocorrect: false)
        }
    }

    private func message(_ field: BusinessField) -> String? {
        issue(field).map { IssueMessages.text($0, field: "") }
    }
}

/// A state picker; read-only when a valid GSTIN already names the state.
struct RegionPicker: View {
    let title: String
    @Binding var selection: String?
    let regions: [TaxRegion]
    var lockedTo: String?
    var lockedReason: String?
    var issue: String?

    var body: some View {
        if let lockedTo {
            LabeledContent(title) {
                VStack(alignment: .trailing) {
                    Text(regions.first { $0.code == lockedTo }?.name ?? lockedTo)
                    if let lockedReason {
                        Text(lockedReason).font(Theme.Fonts.caption.weight(.regular)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Picker(title, selection: $selection) {
                    Text("Choose").tag(String?.none)
                    ForEach(regions) { region in
                        Text(region.name).tag(Optional(region.code))
                    }
                }
                if let issue { IssueText(message: issue) }
            }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
