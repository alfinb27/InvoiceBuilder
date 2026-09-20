import InvoiceCore
import SwiftUI

/// An issued invoice or quote, read-only: what was frozen at issue (snapshots, lines, the stored engine result).
/// Duplicating starts a new draft; an issued quote can be converted to an invoice.
struct IssuedDocumentView: View {
    let model: DocumentViewModel
    let session: Session

    private var document: InvoiceCore.Document { model.state.document }
    private var config: TaxConfig { model.config }

    var body: some View {
        Form {
            header
            if let buyer = document.buyerSnapshot { clientSection(buyer) }
            datesSection
            Section("Items") {
                ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                    LineRow(line: line, computed: document.computed?.lines[safe: index], currency: document.currency,
                            chargesTax: document.computed?.chargesTax ?? false, session: session)
                }
            }
            Section("Totals") {
                TotalsView(computed: document.computed, error: nil, currency: document.currency, config: config,
                           session: session)
            }
            if let notes = document.notes { Section("Notes") { Text(notes) } }
            if let terms = document.terms { Section("Terms") { Text(terms) } }
            if let computed = document.computed, !computed.notes.isEmpty {
                Section("Printed notes") {
                    ForEach(computed.notes, id: \.id) { note in Text(note.text).font(.footnote) }
                }
            }
        }
        .navigationTitle(document.number ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Duplicate", systemImage: "plus.square.on.square") { Task { await model.duplicate() } }
                    if model.canConvert {
                        Button("Convert to invoice", systemImage: "arrow.right.doc.on.clipboard") {
                            Task { await model.convertToInvoice() }
                        }
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("documentActions")
            }
        }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(document.computed?.title ?? DocumentText.noun(document.docType).capitalized)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(document.number ?? "").font(.title2.weight(.semibold)).textSelection(.enabled)
                    Spacer()
                    StatusTag(status: document.status(today: session.today))
                }
                Text(session.money(document.totals.totalMinor, currency: document.currency))
                    .font(.title3.monospacedDigit())
                    .accessibilityIdentifier("issuedTotal")
            }
            .padding(.vertical, Theme.Space.xs)
            .accessibilityElement(children: .combine)
        }
    }

    private func clientSection(_ buyer: BuyerSnapshot) -> some View {
        Section("Client") {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(buyer.name ?? "").font(.body.weight(.medium))
                if let address = buyer.address { Text(address) }
                if let taxId = buyer.taxId {
                    Text(buyer.country == session.business.countryCode ? "\(config.labels.taxIdName) \(taxId)" : taxId)
                        .font(.subheadline.monospaced())
                }
            }
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
        }
    }

    private var datesSection: some View {
        Section("Dates") {
            LabeledContent("Issued", value: document.issueDate.displayText)
            if let supplyDate = document.supplyDate {
                LabeledContent("Supply date", value: supplyDate.displayText)
            }
            if let dueDate = document.dueDate { LabeledContent("Due", value: dueDate.displayText) }
            if let validUntil = document.validUntil { LabeledContent("Valid until", value: validUntil.displayText) }
            if let placeOfSupply = document.computed?.placeOfSupply {
                LabeledContent(config.labels.placeOfSupply ?? "Place of supply",
                               value: config.region(placeOfSupply)?.name ?? placeOfSupply)
            }
        }
    }
}
