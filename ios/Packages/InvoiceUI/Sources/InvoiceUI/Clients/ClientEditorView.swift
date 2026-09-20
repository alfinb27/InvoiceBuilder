import InvoiceCore
import SwiftUI

/// New / edit client sheet (`spec/setup.md` §5).
struct ClientEditorView: View {
    let session: Session
    /// Quick add from the document builder: receives the saved client.
    var onSaved: ((Client) -> Void)?
    @State private var model: ClientEditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(session: Session, route: EditorRoute, onSaved: ((Client) -> Void)? = nil) {
        self.session = session
        self.onSaved = onSaved
        _model = State(initialValue: ClientEditorViewModel(session: session, route: route))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.state.isLoaded {
                    ClientForm(model: model, session: session)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(model.isNew ? "New client" : "Edit client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if let saved = await model.save() {
                                onSaved?(saved)
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.state.isSaving || !model.state.isLoaded)
                }
            }
            .task { await model.load() }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.state.errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(model.state.isSaving)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.state.errorMessage != nil }, set: { if !$0 { model.state.errorMessage = nil } })
    }
}

private struct ClientForm: View {
    @Bindable var model: ClientEditorViewModel
    let session: Session

    private var rules: ClientRules { model.rules }
    private var taxIDName: String { session.config.labels.taxIdName }

    var body: some View {
        Form {
            if model.state.attemptedSave, !model.issues.isEmpty {
                Section { IssueText(message: "Check the highlighted fields.") }
            }
            Section {
                FormTextField(title: "Name", text: $model.state.draft.name, prompt: "Client or company name",
                              issue: message(.name, "name"), capitalization: .words, contentType: .organizationName)
                FormTextField(title: "Contact person (optional)", text: $model.state.draft.contactName,
                              capitalization: .words, contentType: .name)
                Toggle("Business client (B2B)", isOn: $model.state.draft.isBusiness)
            } footer: {
                Text("Business clients can have a \(taxIDName) printed on their invoices.")
            }

            Section("Location and tax") {
                CountryPickerLink(title: "Country", selection: $model.state.draft.countryCode,
                                  countries: session.dependencies.reference.countriesByName)
                if rules.showsRegion(model.state.draft) {
                    RegionPicker(title: session.config.labels.regionName ?? "State",
                                 selection: $model.state.draft.regionCode,
                                 regions: session.config.activeRegionsByName,
                                 lockedTo: rules.regionFromTaxID(model.state.draft),
                                 lockedReason: "From their \(taxIDName)")
                }
                if rules.showsTaxID(model.state.draft) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        FormTextField(title: rules.validatesTaxID(model.state.draft) ? "\(taxIDName) (optional)"
                                        : "Tax ID (optional)",
                                      text: $model.state.draft.taxId,
                                      prompt: rules.validatesTaxID(model.state.draft) ? "As on their registration" : "Their tax or VAT number",
                                      issue: message(.taxId, taxIDName), capitalization: .characters, autocorrect: false)
                        if case .valid(let region) = model.taxIDFeedback {
                            SuccessText(message: region.map { "Valid · \($0)" } ?? "Valid")
                        } else if case .invalid(let problem) = model.taxIDFeedback, model.visibleIssue(.taxId) == nil {
                            IssueText(message: problem)
                        }
                        if let duplicate = model.duplicate {
                            Label("\(duplicate.name) already has this \(taxIDName).", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(Theme.warning)
                        }
                    }
                }
            }

            Section("Contact (optional)") {
                FormTextField(title: "Email", text: $model.state.draft.email, prompt: "accounts@example.com",
                              issue: message(.email, "email"), keyboard: .emailAddress, capitalization: .never,
                              contentType: .emailAddress, autocorrect: false)
                FormTextField(title: "Phone", text: $model.state.draft.phone, keyboard: .phonePad,
                              contentType: .telephoneNumber)
            }

            Section("Billing address (optional)") {
                AddressFields(address: $model.state.draft.billing, countryCode: model.state.draft.countryCode,
                              line1Issue: message(.billingLine1, "address"),
                              postalIssue: message(.billingPostalCode, "postcode"))
            }

            Section("Shipping address") {
                Toggle("Ship to a different address", isOn: $model.state.draft.hasShippingAddress)
                if model.state.draft.hasShippingAddress {
                    AddressFields(address: $model.state.draft.shipping, countryCode: model.state.draft.countryCode,
                                  line1Issue: message(.shippingLine1, "address"),
                                  postalIssue: message(.shippingPostalCode, "postcode"))
                }
            }

            Section("More") {
                Picker("Invoice currency", selection: $model.state.draft.defaultCurrency) {
                    Text("\(session.business.homeCurrency.rawValue) (your currency)").tag(CurrencyCode?.none)
                    ForEach(currencies) { currency in
                        Text("\(currency.code.rawValue) · \(currency.name)").tag(Optional(currency.code))
                    }
                }
                .pickerStyle(.navigationLink)
                FormTextField(title: "Notes (optional)", text: $model.state.draft.notes, axis: .vertical)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var currencies: [Currency] {
        session.dependencies.reference.currencies.all
            .filter { $0.code != session.business.homeCurrency }
            .sorted { $0.code < $1.code }
    }

    private func message(_ field: ClientField, _ name: String) -> String? {
        model.visibleIssue(field).map { IssueMessages.text($0, field: name, taxIDName: taxIDName) }
    }
}

/// Address lines, city and postcode for a draft address.
struct AddressFields: View {
    @Binding var address: AddressDraft
    let countryCode: String
    var line1Issue: String?
    var postalIssue: String?

    var body: some View {
        FormTextField(title: "Address line 1", text: $address.line1, prompt: "Building, street", issue: line1Issue,
                      capitalization: .words, contentType: .streetAddressLine1)
        FormTextField(title: "Address line 2", text: $address.line2, capitalization: .words,
                      contentType: .streetAddressLine2)
        FormTextField(title: "City", text: $address.city, capitalization: .words, contentType: .addressCity)
        FormTextField(title: countryCode == "IN" ? "PIN code" : "Postcode", text: $address.postalCode,
                      issue: postalIssue, keyboard: countryCode == "IN" ? .numberPad : .default,
                      capitalization: .characters, contentType: .postalCode, autocorrect: false)
    }
}

/// A country row that opens a searchable list.
struct CountryPickerLink: View {
    let title: String
    @Binding var selection: String
    let countries: [Country]

    var body: some View {
        NavigationLink {
            CountryList(selection: $selection, countries: countries)
                .navigationTitle(title)
        } label: {
            LabeledContent(title, value: countries.first { $0.code == selection }?.name ?? selection)
        }
    }
}

private struct CountryList: View {
    @Binding var selection: String
    let countries: [Country]
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(filtered) { country in
            Button {
                selection = country.code
                dismiss()
            } label: {
                HStack {
                    Text(country.name).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if country.code == selection {
                        Image(systemName: "checkmark").foregroundStyle(Theme.brand)
                    }
                }
            }
            .accessibilityAddTraits(country.code == selection ? .isSelected : [])
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
    }

    private var filtered: [Country] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? countries : countries.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }
}
