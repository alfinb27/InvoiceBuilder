import InvoiceCore
import SwiftUI

/// Totals and the tax breakdown of a computed document, exactly as `TaxEngine` returned them. Used as a form
/// section on iPhone, the side panel of the iPad builder and the issued document view.
struct TotalsView: View {
    let computed: ComputedDocument?
    let error: TaxEngineError?
    let currency: CurrencyCode
    let config: TaxConfig
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let computed {
                rows(computed)
            } else if let error {
                IssueText(message: DocumentText.message(error, config: config))
            } else {
                Text("Add a line to see the totals.").foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("totals")
    }

    @ViewBuilder
    private func rows(_ computed: ComputedDocument) -> some View {
        let totals = computed.totals
        amountRow("Subtotal", totals.subtotal)
        if totals.discount != 0 { amountRow("Discount", -totals.discount) }
        if totals.shipping != 0 { amountRow("Shipping", totals.shipping) }
        if computed.chargesTax, !computed.taxLines.isEmpty {
            if totals.taxable != totals.subtotal || computed.inclusive {
                amountRow(computed.inclusive ? "Taxable value (tax included in prices)" : "Taxable value",
                          totals.taxable)
            }
            ForEach(Array(computed.taxLines.enumerated()), id: \.offset) { _, line in
                taxRow(line)
            }
        }
        if totals.taxNotCharged != 0 {
            Text("\(config.labels.taxName) of \(money(totals.taxNotCharged)) is payable by the client under reverse charge.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        if totals.roundOff != 0 { amountRow(config.rounding.grandTotal?.label ?? "Round off", totals.roundOff) }
        Divider()
        AdaptiveRow {
            Text("Total").font(.headline)
        } value: {
            Text(money(totals.total))
                .font(.title3.weight(.semibold).monospacedDigit())
                .accessibilityIdentifier("totalAmount")
        }
        .accessibilityElement(children: .combine)
        if let home = computed.home {
            let rate = SpecFormatter.quantity(home.rate)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("In \(home.currency.rawValue) at \(rate) per \(currency.rawValue)")
                    .font(.footnote.weight(.semibold))
                homeRow("Taxable value", home.taxable, home.currency)
                if home.tax != 0 { homeRow(config.labels.taxName, home.tax, home.currency) }
                homeRow("Total", home.total, home.currency)
            }
            .foregroundStyle(Theme.textSecondary)
        }
        if config.amountInWords, currency == .inr {
            Text(AmountInWords.text(minor: totals.total, currency: currency,
                                    currencies: session.dependencies.reference.currencies))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func taxRow(_ line: ComputedTaxLine) -> some View {
        let name = line.component.map { "\($0) \(SpecFormatter.percent(line.rate))" }
            ?? DocumentText.category(line.category)
        let detail = "on \(money(line.taxable))" + (line.charged ? "" : " · not charged")
        return AdaptiveRow {
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        } value: {
            VStack(alignment: .trailing, spacing: 0) {
                Text(line.component == nil ? "—" : money(line.tax)).monospacedDigit()
                if let homeTax = line.homeTax, line.component != nil {
                    Text(session.money(homeTax, currency: session.business.homeCurrency))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func amountRow(_ title: String, _ minor: Int64) -> some View {
        AdaptiveRow {
            Text(title)
        } value: {
            Text(money(minor)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func homeRow(_ title: String, _ minor: Int64, _ homeCurrency: CurrencyCode) -> some View {
        AdaptiveRow {
            Text(title).font(.footnote)
        } value: {
            Text(session.money(minor, currency: homeCurrency)).font(.footnote.monospacedDigit())
        }
    }

    private func money(_ minor: Int64) -> String { session.money(minor, currency: currency) }
}

/// Problems and warnings above the builder: what blocks issuing in red, compliance warnings in amber.
struct DocumentBanner: View {
    let problems: [String]
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(problems, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(Theme.danger)
            }
            ForEach(warnings, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("documentBanner")
    }
}
