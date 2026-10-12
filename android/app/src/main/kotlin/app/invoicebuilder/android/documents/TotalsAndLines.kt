package app.invoicebuilder.android.documents

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.common.EditorSheet
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.FormTextField
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.designsystem.IssueText
import app.invoicebuilder.core.designsystem.PickerField
import app.invoicebuilder.core.designsystem.SegmentedChoice
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.domain.documents.AmountInWords
import app.invoicebuilder.core.domain.documents.LineItemField
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.tax.ComputedDocument
import app.invoicebuilder.core.domain.tax.ComputedTaxLine
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.tax.TaxEngineError

/** Totals and the tax breakdown exactly as `TaxEngine` returned them. iOS: `TotalsView`. */
@Composable
fun TotalsView(computed: ComputedDocument?, error: TaxEngineError?, currency: CurrencyCode, config: TaxConfig, session: Session) {
    fun money(minor: Long) = session.money(minor, currency)
    Column(Modifier.fillMaxWidth().testTag("totals"), verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
        when {
            computed != null -> {
                val totals = computed.totals
                AmountRow("Subtotal", money(totals.subtotal))
                if (totals.discount != 0L) AmountRow("Discount", money(-totals.discount))
                if (totals.shipping != 0L) AmountRow("Shipping", money(totals.shipping))
                if (computed.chargesTax && computed.taxLines.isNotEmpty()) {
                    if (totals.taxable != totals.subtotal || computed.inclusive) {
                        AmountRow(if (computed.inclusive) "Taxable value (tax included in prices)" else "Taxable value", money(totals.taxable))
                    }
                    for (line in computed.taxLines) TaxRow(line, ::money, session)
                }
                if (totals.taxNotCharged != 0L) {
                    Text("${config.labels.taxName} of ${money(totals.taxNotCharged)} is payable by the client under reverse charge.",
                        style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
                }
                if (totals.roundOff != 0L) AmountRow(config.rounding.grandTotal?.label ?: "Round off", money(totals.roundOff))
                HorizontalDivider(color = Theme.colors.border)
                // The tag sits on the merged row (a child's tag is hidden inside a merged node); its text is "Total, ₹…".
                Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}.testTag("totalAmount"), verticalAlignment = Alignment.CenterVertically) {
                    Text("Total", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    Text(money(totals.total), style = MaterialTheme.typography.titleLarge)
                }
                computed.home?.let { home ->
                    Column {
                        Text("In ${home.currency.rawValue} at ${SpecFormatter.quantity(home.rate)} per ${currency.rawValue}",
                            style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, color = Theme.colors.textSecondary)
                        AmountRow("Taxable value", session.money(home.taxable, home.currency), small = true)
                        if (home.tax != 0L) AmountRow(config.labels.taxName, session.money(home.tax, home.currency), small = true)
                        AmountRow("Total", session.money(home.total, home.currency), small = true)
                    }
                }
                if (config.amountInWords && currency == CurrencyCode.INR) {
                    Text(AmountInWords.text(totals.total, currency, session.container.reference.currencies),
                        style = MaterialTheme.typography.bodySmall, color = Theme.colors.textSecondary)
                }
            }
            error != null -> IssueText(DocumentText.message(error, config))
            else -> Text("Add a line to see the totals.", color = Theme.colors.textSecondary)
        }
    }
}

@Composable
private fun TaxRow(line: ComputedTaxLine, money: (Long) -> String, session: Session) {
    val name = line.component?.let { "$it ${SpecFormatter.percent(line.rate)}" } ?: DocumentText.category(line.category)
    val detail = "on ${money(line.taxable)}" + if (line.charged) "" else " · not charged"
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}) {
        Column(Modifier.weight(1f)) {
            Text(name)
            Text(detail, style = MaterialTheme.typography.labelSmall, color = Theme.colors.textSecondary)
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(if (line.component == null) "—" else money(line.tax))
            if (line.homeTax != null && line.component != null) {
                Text(session.money(line.homeTax!!, session.business.homeCurrency), style = MaterialTheme.typography.labelSmall, color = Theme.colors.textSecondary)
            }
        }
    }
}

@Composable
private fun AmountRow(title: String, value: String, small: Boolean = false) {
    val style = if (small) MaterialTheme.typography.bodySmall else MaterialTheme.typography.bodyLarge
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}) {
        Text(title, Modifier.weight(1f), style = style, color = if (small) Theme.colors.textSecondary else Theme.colors.textPrimary)
        Text(value, style = style, color = if (small) Theme.colors.textSecondary else Theme.colors.textPrimary)
    }
}

/** What blocks issuing in red, compliance warnings in amber. iOS: `DocumentBanner`. */
@Composable
fun DocumentBanner(problems: List<String>, warnings: List<String>) {
    Column(Modifier.fillMaxWidth().testTag("documentBanner"), verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) {
        for (message in problems) Row {
            Icon(Icons.Filled.Error, null, tint = Theme.colors.danger)
            Text("  $message", color = Theme.colors.danger)
        }
        for (message in warnings) Row {
            Icon(Icons.Filled.Warning, null, tint = Theme.colors.warning)
            Text("  $message", color = Theme.colors.warning)
        }
    }
}
