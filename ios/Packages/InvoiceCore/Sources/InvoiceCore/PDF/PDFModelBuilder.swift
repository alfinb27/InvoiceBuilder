import Foundation

/// Builds the PDF view model from a stored document and its engine result (`spec/pdf/RENDERING.md` §1). Pure: no
/// clock, no locale, no I/O — the same document always produces the same strings, on both platforms.
public enum PDFModelBuilder {
    public static func build(document: Document, computed: ComputedDocument, config: TaxConfig, labels: PDFLabels,
                             reference: ReferenceData) -> PDFDocumentModel {
        Builder(document: document, computed: computed, config: config, labels: labels, reference: reference).build()
    }

    private struct Builder {
        let document: Document
        let computed: ComputedDocument
        let config: TaxConfig
        let labels: PDFLabels
        let reference: ReferenceData

        var formatter: SpecFormatter { SpecFormatter(currencies: reference.currencies) }
        var taxName: String { config.labels.taxName }
        var taxIDName: String { config.labels.taxIdName }
        var currency: CurrencyCode { document.currency }
        var homeCurrency: CurrencyCode { document.sellerSnapshot?.homeCurrency ?? document.currency }
        var isQuote: Bool { document.docType == .quote }
        var chargesTax: Bool { computed.chargesTax }
        var lineLevelTax: Bool { config.rounding.taxLevel == .line }

        func money(_ minor: Int64, currency: CurrencyCode? = nil) -> String {
            formatter.money(minor, currency: currency ?? self.currency, homeCurrency: homeCurrency)
        }

        func build() -> PDFDocumentModel {
            let columns = columns()
            return PDFDocumentModel(
                title: computed.title,
                isDraft: document.number == nil,
                draftLabel: document.number == nil ? labels.text("draft") : nil,
                number: document.number,
                numberLabel: labels.text(isQuote ? "quoteNumber" : "invoiceNumber"),
                meta: meta(),
                seller: sellerParty(),
                buyer: buyerParty(),
                shipTo: shipToParty(),
                columns: columns,
                rows: rows(columns: columns),
                totals: totalRows(),
                taxSummary: taxSummary(),
                amountInWords: amountInWords(),
                homeTotals: homeTotals(),
                reverseChargeNote: reverseChargeNote(),
                notes: notes(),
                payment: payment(),
                signature: signature(),
                footer: PDFDocumentModel.Footer(pageLabel: labels.text("page"),
                                                continued: labels.text("continued"))
            )
        }

        // MARK: Header

        func meta() -> [PDFDocumentModel.Field] {
            var fields = [field("issueDate", SpecFormatter.date(document.issueDate))]
            if let supplyDate = document.supplyDate {
                fields.append(field("supplyDate", SpecFormatter.date(supplyDate)))
            }
            if isQuote, let validUntil = document.validUntil {
                fields.append(field("validUntil", SpecFormatter.date(validUntil)))
            }
            if !isQuote, let dueDate = document.dueDate {
                fields.append(field("dueDate", SpecFormatter.date(dueDate)))
            }
            if let placeOfSupply = computed.placeOfSupply {
                fields.append(PDFDocumentModel.Field(
                    label: config.labels.placeOfSupply ?? labels.text("placeOfSupply"),
                    value: config.region(placeOfSupply)?.name ?? placeOfSupply
                ))
            }
            return fields
        }

        func field(_ key: String, _ value: String) -> PDFDocumentModel.Field {
            PDFDocumentModel.Field(label: labels.text(key), value: value)
        }

        // MARK: Parties

        func sellerParty() -> PDFDocumentModel.Party {
            guard let seller = document.sellerSnapshot else {
                return PDFDocumentModel.Party(heading: labels.text("from"), name: "")
            }
            var lines: [String] = []
            if let legalName = seller.legalName, legalName != seller.name { lines.append(legalName) }
            lines += addressLines(seller.postalAddress, fallback: seller.address, businessCountry: seller.country)
            lines += [seller.email, seller.phone, seller.website].compactMap { $0?.trimmedOrNil }

            var fields: [PDFDocumentModel.Field] = []
            if let taxId = seller.taxId?.trimmedOrNil {
                fields.append(PDFDocumentModel.Field(label: taxIDName, value: taxId))
            }
            let extras = seller.extraIds
            for (value, key) in [(extras?.pan, "pan"), (extras?.companyNumber, "companyNumber"),
                                 (extras?.registeredOffice, "registeredOffice"), (extras?.lutReference, "lutReference")] {
                if let value = value?.trimmedOrNil { fields.append(field(key, value)) }
            }
            return PDFDocumentModel.Party(heading: labels.text("from"), name: seller.name, lines: lines,
                                          fields: fields)
        }

        func buyerParty() -> PDFDocumentModel.Party? {
            guard let buyer = document.buyerSnapshot else { return nil }
            var fields: [PDFDocumentModel.Field] = []
            if let taxId = buyer.taxId?.trimmedOrNil {
                let domestic = buyer.country == document.sellerSnapshot?.country
                fields.append(PDFDocumentModel.Field(label: domestic ? taxIDName : labels.text("foreignTaxId"),
                                                     value: taxId))
            }
            return PDFDocumentModel.Party(
                heading: labels.text("billTo"), name: buyer.name ?? "",
                lines: addressLines(buyer.billingAddress, fallback: buyer.address,
                                    businessCountry: document.sellerSnapshot?.country),
                fields: fields
            )
        }

        func shipToParty() -> PDFDocumentModel.Party? {
            guard let buyer = document.buyerSnapshot, let shipping = buyer.shippingAddress,
                  shipping != buyer.billingAddress else { return nil }
            return PDFDocumentModel.Party(
                heading: labels.text("shipTo"), name: buyer.name ?? "",
                lines: addressLines(shipping, fallback: nil, businessCountry: document.sellerSnapshot?.country)
            )
        }

        /// Address line 1, line 2, city with postcode, the region's name, then the country when it is not the
        /// business's own. Falls back to the one-line address the engine uses.
        func addressLines(_ address: Address?, fallback: String?, businessCountry: String?) -> [String] {
            guard let address else { return [fallback?.trimmedOrNil].compactMap { $0 } }
            var lines = [address.line1]
            if let line2 = address.line2?.trimmedOrNil { lines.append(line2) }
            let city = [address.city?.trimmedOrNil, address.postalCode?.trimmedOrNil]
                .compactMap { $0 }.joined(separator: " ")
            if !city.isEmpty { lines.append(city) }
            if let region = address.regionCode?.trimmedOrNil {
                lines.append(config.region(region)?.name ?? region)
            }
            if address.countryCode != businessCountry {
                lines.append(reference.country(code: address.countryCode)?.name ?? address.countryCode)
            }
            return lines
        }

        // MARK: Items table (§1.1)

        /// Component codes that appear on the lines, in order of first appearance.
        var componentCodes: [String] {
            guard chargesTax, lineLevelTax else { return [] }
            var codes: [String] = []
            for line in computed.lines {
                for tax in line.taxes ?? [] {
                    if let code = tax.component, !codes.contains(code) { codes.append(code) }
                }
            }
            return codes
        }

        func columns() -> [PDFDocumentModel.Column] {
            var columns = [PDFDocumentModel.Column(id: "index", label: labels.text("item"), align: .leading),
                           PDFDocumentModel.Column(id: "description", label: labels.text("description"),
                                                   align: .leading)]
            if document.lines.contains(where: { $0.productCode?.trimmedOrNil != nil }) {
                columns.append(PDFDocumentModel.Column(id: "productCode", label: config.labels.productCodeName,
                                                       align: .leading))
            }
            columns.append(PDFDocumentModel.Column(id: "quantity", label: labels.text("quantity"), align: .trailing))
            if document.lines.contains(where: { $0.unit?.trimmedOrNil != nil }) {
                columns.append(PDFDocumentModel.Column(id: "unit", label: labels.text("unit"), align: .leading))
            }
            let priceLabel = computed.inclusive ? labels.text("unitPriceInclusive", ["taxName": taxName])
                                                : labels.text("unitPrice")
            columns.append(PDFDocumentModel.Column(id: "unitPrice", label: priceLabel, align: .trailing))
            if document.lines.contains(where: { $0.discount != nil }) {
                columns.append(PDFDocumentModel.Column(id: "discount", label: labels.text("discount"),
                                                       align: .trailing))
            }
            if chargesTax {
                columns.append(PDFDocumentModel.Column(id: "taxable", label: labels.text("taxableValue"),
                                                       align: .trailing))
            }
            let codes = componentCodes
            if !codes.isEmpty, codes.count <= 2 {
                for code in codes {
                    let rates = Set(computed.lines.flatMap { $0.taxes ?? [] }
                        .filter { $0.component == code }.map(\.rate))
                    let label = rates.count == 1 ? "\(code) \(SpecFormatter.percent(rates.first ?? "0"))" : code
                    columns.append(PDFDocumentModel.Column(id: "tax:\(code)", label: label, align: .trailing))
                }
            }
            columns.append(PDFDocumentModel.Column(id: "amount", label: labels.text("amount"), align: .trailing))
            return columns
        }

        func rows(columns: [PDFDocumentModel.Column]) -> [[String]] {
            zip(document.lines.indices, zip(document.lines, computed.lines)).map { index, pair in
                let (line, result) = pair
                let taxes = Dictionary((result.taxes ?? []).compactMap { tax in
                    tax.component.map { ($0, tax.amount) }
                }, uniquingKeysWith: +)
                let isNonTax = (result.taxes ?? []).contains { $0.component == nil }
                let lineTax = taxes.values.reduce(0, +)
                return columns.map { column in
                    switch column.id {
                    case "index": String(index + 1)
                    case "description": line.description
                    case "productCode": line.productCode ?? ""
                    case "quantity": SpecFormatter.quantity(line.quantity)
                    case "unit": line.unit ?? ""
                    case "unitPrice": money(line.unitPriceMinor)
                    case "discount": discountText(line.discount)
                    case "taxable": money(result.taxable)
                    case "amount": money(chargesTax && lineLevelTax ? result.taxable + lineTax : result.taxable)
                    default:
                        if column.id.hasPrefix("tax:") {
                            isNonTax ? categoryLabel(result.category)
                                     : money(taxes[String(column.id.dropFirst(4))] ?? 0)
                        } else {
                            ""
                        }
                    }
                }
            }
        }

        func discountText(_ discount: Discount?) -> String {
            switch discount {
            case .percent(let value)?: SpecFormatter.percent(value)
            case .amount(let minor)?: money(minor)
            case nil: ""
            }
        }

        func categoryLabel(_ category: TaxCategory) -> String {
            switch category {
            case .exempt: labels.text("exempt")
            case .nilRated: labels.text("nilRated")
            case .zero: labels.text("zeroRated")
            case .outsideScope: labels.text("outsideScope")
            default: category.rawValue
            }
        }

        // MARK: Totals (§1.2)

        func totalRows() -> [PDFDocumentModel.TotalRow] {
            let totals = computed.totals
            var rows = [PDFDocumentModel.TotalRow(label: labels.text("subtotal"), value: money(totals.subtotal))]
            if totals.discount != 0 {
                rows.append(PDFDocumentModel.TotalRow(label: labels.text("invoiceDiscount"),
                                                      value: money(-totals.discount)))
            }
            if totals.shipping != 0 {
                rows.append(PDFDocumentModel.TotalRow(label: labels.text("shipping"), value: money(totals.shipping)))
            }
            if chargesTax {
                rows.append(PDFDocumentModel.TotalRow(label: labels.text("taxableValue"),
                                                      value: money(totals.taxable)))
            }
            // One row per component code, summing its tax lines; the per-rate split stays in the tax summary.
            var components: [(code: String, tax: Int64, rates: Set<String>)] = []
            for taxLine in computed.taxLines {
                guard taxLine.charged, let code = taxLine.component else { continue }
                if let index = components.firstIndex(where: { $0.code == code }) {
                    components[index].tax += taxLine.tax
                    components[index].rates.insert(taxLine.rate)
                } else {
                    components.append((code, taxLine.tax, [taxLine.rate]))
                }
            }
            for component in components {
                let label = component.rates.count == 1
                    ? "\(component.code) \(SpecFormatter.percent(component.rates.first ?? "0"))"
                    : component.code
                rows.append(PDFDocumentModel.TotalRow(label: label, value: money(component.tax)))
            }
            if totals.roundOff != 0 {
                rows.append(PDFDocumentModel.TotalRow(label: config.rounding.grandTotal?.label
                                                          ?? labels.text("roundOff"),
                                                      value: money(totals.roundOff)))
            }
            rows.append(PDFDocumentModel.TotalRow(label: labels.text("total"), value: money(totals.total),
                                                  emphasis: .strong))
            return rows
        }

        func taxSummary() -> PDFDocumentModel.Table? {
            guard chargesTax, computed.taxLines.count > 1 || !lineLevelTax else { return nil }
            let showsHome = config.foreignCurrency.taxInHomeCurrency && computed.home != nil
            var columns = [
                PDFDocumentModel.Column(id: "rate", label: labels.text("taxRate", ["taxName": taxName]),
                                        align: .leading),
                PDFDocumentModel.Column(id: "taxable", label: labels.text("taxableValue"), align: .trailing),
                PDFDocumentModel.Column(id: "tax", label: labels.text("taxAmount", ["taxName": taxName]),
                                        align: .trailing),
            ]
            if showsHome {
                columns.append(PDFDocumentModel.Column(
                    id: "homeTax",
                    label: labels.text("taxAmountInCurrency",
                                       ["taxName": taxName, "currency": homeCurrency.rawValue]),
                    align: .trailing
                ))
            }
            var rows: [[String]] = computed.taxLines.map { taxLine in
                let name = taxLine.component.map { "\($0) \(SpecFormatter.percent(taxLine.rate))" }
                    ?? categoryLabel(taxLine.category)
                var row = [name, money(taxLine.taxable),
                           taxLine.component == nil ? "" : money(taxLine.tax)]
                if showsHome {
                    row.append(taxLine.component == nil ? ""
                               : money(taxLine.homeTax ?? 0, currency: homeCurrency))
                }
                return row
            }
            let totals = computed.totals
            var totalRow = [labels.text("totalTax", ["taxName": taxName]), money(totals.taxable),
                            money(totals.tax != 0 ? totals.tax : totals.taxNotCharged)]
            if showsHome { totalRow.append(money(computed.home?.tax ?? 0, currency: homeCurrency)) }
            rows.append(totalRow)
            return PDFDocumentModel.Table(columns: columns, rows: rows)
        }

        func amountInWords() -> String? {
            guard config.amountInWords else { return nil }
            return AmountInWords.text(minor: computed.totals.total, currency: currency,
                                      currencies: reference.currencies)
        }

        func homeTotals() -> String? {
            guard let home = computed.home else { return nil }
            let prefix = labels.text("homeCurrencyEquivalent",
                                     ["currency": home.currency.rawValue,
                                      "rate": SpecFormatter.quantity(home.rate)])
            return prefix + ": " + money(home.total, currency: home.currency)
        }

        func reverseChargeNote() -> String? {
            guard computed.totals.taxNotCharged != 0 else { return nil }
            return labels.text("taxNotChargedRecipient",
                               ["taxName": taxName, "amount": money(computed.totals.taxNotCharged)])
        }

        // MARK: Notes, payment, signature (§1.3)

        func notes() -> [PDFDocumentModel.Note] {
            var notes = computed.notes.filter { $0.placement == "top" }
                .map { PDFDocumentModel.Note(text: $0.text, placement: "top") }
            if let text = document.notes?.trimmedOrNil {
                notes.append(PDFDocumentModel.Note(label: labels.text("notes"), text: text, placement: "bottom"))
            }
            if let text = document.terms?.trimmedOrNil {
                notes.append(PDFDocumentModel.Note(label: labels.text("terms"), text: text, placement: "bottom"))
            }
            notes += computed.notes.filter { $0.placement != "top" }
                .map { PDFDocumentModel.Note(text: $0.text, placement: "bottom") }
            return notes
        }

        func payment() -> PDFDocumentModel.Payment {
            guard let seller = document.sellerSnapshot else { return PDFDocumentModel.Payment() }
            let bank = seller.bank
            let entries: [(String?, String)] = [(bank?.accountName, "accountName"),
                                                (bank?.accountNumber, "accountNumber"), (bank?.bankName, "bankName"),
                                                (bank?.ifsc, "ifsc"), (bank?.sortCode, "sortCode"),
                                                (bank?.iban, "iban"), (bank?.swift, "swift")]
            let fields = entries.compactMap { value, key in
                value?.trimmedOrNil.map { field(key, $0) }
            }
            var payment = PDFDocumentModel.Payment(bank: fields)
            let outstanding = computed.totals.total
            if UPIPaymentLink.applies(currency: currency, vpa: seller.upiVpa, outstandingMinor: outstanding),
               let vpa = seller.upiVpa?.trimmedOrNil {
                payment.upi = PDFDocumentModel.Payment.UPI(
                    id: vpa,
                    caption: labels.text("upiScanToPay"),
                    payload: UPIPaymentLink.url(vpa: vpa, payeeName: seller.name, amountMinor: outstanding,
                                                invoiceNumber: document.number ?? "")
                )
            }
            return payment
        }

        func signature() -> PDFDocumentModel.Signature {
            let name = document.sellerSnapshot?.name ?? ""
            return PDFDocumentModel.Signature(
                imageAssetId: document.sellerSnapshot?.signatureAssetId,
                forBusiness: labels.text("forBusiness", ["businessName": name]),
                authorisedSignatory: labels.text("authorisedSignatory")
            )
        }
    }
}
