import InvoiceCore
import SwiftUI

/// An issued invoice or quote, read-only: what was frozen at issue (snapshots, lines, the stored engine result).
/// Duplicating starts a new draft; an issued quote can be converted to an invoice.
struct IssuedDocumentView: View {
    let model: DocumentViewModel
    let session: Session
    @State private var showingVoidAlert = false
    @State private var voidReasonText = ""
    @State private var showingPaymentSheet = false

    private var document: InvoiceCore.Document { model.state.document }
    private var config: TaxConfig { model.config }

    var body: some View {
        ThemedForm {
            header
            if document.lifecycle == .void { voidSection }
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
            if !model.state.payments.isEmpty { paymentsSection }
            if let notes = document.notes { Section("Notes") { Text(notes) } }
            if let terms = document.terms { Section("Terms") { Text(terms) } }
            if let computed = document.computed, !computed.notes.isEmpty {
                Section("Printed notes") {
                    ForEach(computed.notes, id: \.id) { note in Text(note.text).font(Theme.Fonts.footnote) }
                }
            }
        }
        .navigationTitle(document.number ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Share", systemImage: "square.and.arrow.up") { Task { await model.openPreview() } }
                    .disabled(!model.canPreview)
                    .accessibilityIdentifier("previewButton")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Duplicate", systemImage: "plus.square.on.square") { Task { await model.duplicate() } }
                    if model.canConvert {
                        Button("Convert to invoice", systemImage: "arrow.right.doc.on.clipboard") {
                            Task { await model.convertToInvoice() }
                        }
                    }
                    if model.canRecordPayment {
                        Button("Record payment", systemImage: "banknote") { showingPaymentSheet = true }
                            .accessibilityIdentifier("recordPayment")
                    }
                    if model.canSendReminder {
                        Button("Send reminder", systemImage: "bell") { Task { await model.sendReminder() } }
                            .accessibilityIdentifier("sendReminder")
                    }
                    if model.canRespondToQuote {
                        Button("Mark accepted", systemImage: "checkmark.circle") { Task { await model.acceptQuote() } }
                        Button("Mark declined", systemImage: "xmark.circle") { Task { await model.declineQuote() } }
                    }
                    if model.canVoid {
                        Button("Void", systemImage: "nosign", role: .destructive) {
                            voidReasonText = ""
                            showingVoidAlert = true
                        }
                        .accessibilityIdentifier("voidDocument")
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("documentActions")
            }
        }
        .task(id: session.router.documents.pendingAction) { runPendingAction() }
        .sensoryFeedback(.success, trigger: model.state.paymentsRecorded)
        .alert("Void this \(DocumentText.noun(document.docType))?", isPresented: $showingVoidAlert) {
            TextField("Reason", text: $voidReasonText)
                .accessibilityIdentifier("voidReasonField")
            Button("Cancel", role: .cancel) {}
            Button("Void", role: .destructive) { Task { await model.voidDocument(reason: voidReasonText) } }
        } message: {
            Text("Its number is kept and cannot be reused. This cannot be undone.")
        }
        .sheet(isPresented: $showingPaymentSheet) {
            PaymentEditorView(session: session, documentID: document.id, currency: document.currency) { payment in
                model.recordedPayment(payment)
            }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.state.errorMessage ?? "")
        }
    }

    /// A row context-menu action chosen in the list (iPad), once this document is on screen.
    private func runPendingAction() {
        switch session.router.documents.takeAction(for: document.id) {
        case .share?:
            Task { await model.openPreview() }
        case .recordPayment? where model.canRecordPayment:
            showingPaymentSheet = true
        case .void? where model.canVoid:
            voidReasonText = ""
            showingVoidAlert = true
        default:
            break
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.state.errorMessage != nil }, set: { if !$0 { model.dismissError() } })
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(document.computed?.title ?? DocumentText.noun(document.docType).capitalized)
                    .font(Theme.Fonts.subhead)
                    .foregroundStyle(Theme.textSecondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(document.number ?? "").font(Theme.Fonts.title3.weight(.semibold)).textSelection(.enabled)
                    Spacer()
                    StatusTag(status: document.status(today: session.today, paid: model.paidMinor))
                }
                Text(session.money(document.totals.totalMinor, currency: document.currency))
                    .font(Theme.Fonts.title3.monospacedDigit())
                    .accessibilityIdentifier("issuedTotal")
                if document.docType == .invoice, model.paidMinor > 0 {
                    let outstanding = max(document.totals.totalMinor - model.paidMinor, 0)
                    Text("\(session.money(model.paidMinor, currency: document.currency)) paid · "
                         + "\(session.money(outstanding, currency: document.currency)) outstanding")
                        .font(Theme.Fonts.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, Theme.Space.xs)
            .accessibilityElement(children: .combine)
        }
    }

    private var voidSection: some View {
        Section("Void") {
            if let reason = document.voidReason { LabeledContent("Reason", value: reason) }
            if let voidedAt = document.voidedAt {
                LabeledContent("Voided", value: LocalDate(epochMs: voidedAt).displayText)
            }
        }
    }

    private var paymentsSection: some View {
        Section("Payments") {
            ForEach(model.state.payments, id: \.id) { payment in
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(PaymentMethodText.label(payment.method))
                        Text(payment.date.displayText).font(Theme.Fonts.caption.weight(.regular)).foregroundStyle(.secondary)
                        if let reference = payment.reference {
                            Text(reference).font(Theme.Fonts.caption.weight(.regular)).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Text(session.money(payment.amountMinor, currency: document.currency)).monospacedDigit()
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await model.deletePayment(payment) }
                    }
                }
            }
        }
    }

    private func clientSection(_ buyer: BuyerSnapshot) -> some View {
        Section("Client") {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(buyer.name ?? "").font(Theme.Fonts.body.weight(.medium))
                if let address = buyer.address { Text(address) }
                if let taxId = buyer.taxId {
                    Text(buyer.country == session.business.countryCode ? "\(config.labels.taxIdName) \(taxId)" : taxId)
                        .font(Theme.Fonts.subhead.monospaced())
                }
            }
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
        }
    }

    private var datesSection: some View {
        Section("Dates") {
            LabeledContent("\(DocumentText.noun(document.docType).capitalized) date", value: document.issueDate.displayText)
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
