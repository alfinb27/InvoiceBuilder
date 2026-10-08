package app.invoicebuilder.core.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.invoicebuilder.core.domain.decimal.InputError
import app.invoicebuilder.core.domain.numbering.NumberingError
import app.invoicebuilder.core.domain.numbering.NumberingPatternIssue
import app.invoicebuilder.core.domain.setup.FieldIssue
import app.invoicebuilder.core.domain.tax.TaxIDError
import app.invoicebuilder.core.domain.validation.FieldError
import app.invoicebuilder.core.domain.validation.FieldRule

/**
 * A form row: a labelled text field with its problem underneath (iOS: `FormTextField`). TalkBack reads the label,
 * the value and the problem together; `testTag` is the iOS accessibility identifier.
 */
@Composable
fun FormTextField(
    title: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    prompt: String? = null,
    issue: String? = null,
    keyboard: KeyboardType = KeyboardType.Text,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
    autocorrect: Boolean = true,
    multiline: Boolean = false,
    tag: String? = null,
    enabled: Boolean = true,
) {
    val decimal = keyboard == KeyboardType.Decimal
    OutlinedTextField(
        value = value,
        onValueChange = { onValueChange(if (decimal) DecimalPadText.normalized(it) else it) },
        modifier = modifier.fillMaxWidth().let { if (tag != null) it.testTag(tag) else it }
            .semantics { if (issue != null) error(issue) },
        label = { Text(title) },
        placeholder = prompt?.let { { Text(it) } },
        isError = issue != null,
        supportingText = issue?.let { { IssueText(it) } },
        singleLine = !multiline,
        minLines = 1,
        maxLines = if (multiline) 6 else 1,
        enabled = enabled,
        keyboardOptions = KeyboardOptions(
            capitalization = capitalization, autoCorrectEnabled = autocorrect, keyboardType = keyboard,
            imeAction = if (multiline) ImeAction.Default else ImeAction.Next,
        ),
    )
}

/** A red problem message under a field. */
@Composable
fun IssueText(message: String, modifier: Modifier = Modifier) {
    Row(modifier.semantics(mergeDescendants = true) { contentDescription = "Problem: $message" }, verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.Error, null, Modifier.size(14.dp), tint = Theme.colors.danger)
        Spacer(Modifier.size(Theme.Space.xs))
        Text(message, style = MaterialTheme.typography.bodySmall, color = Theme.colors.danger)
    }
}

/** A green confirmation under a field (e.g. a valid GSTIN and its state). */
@Composable
fun SuccessText(message: String, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.CheckCircle, null, Modifier.size(14.dp), tint = Theme.colors.success)
        Spacer(Modifier.size(Theme.Space.xs))
        Text(message, style = MaterialTheme.typography.bodySmall, color = Theme.colors.success)
    }
}

/** A small rounded tag such as "B2B" or "Archived". */
@Composable
fun Tag(text: String, color: Color = Theme.colors.info, modifier: Modifier = Modifier) {
    Text(
        text, modifier.background(color.copy(alpha = 0.12f), RoundedCornerShape(50)).padding(horizontal = Theme.Space.s, vertical = Theme.Space.xxs),
        style = MaterialTheme.typography.labelMedium, color = color,
    )
}

/** The large full-width button at the bottom of onboarding steps. */
@Composable
fun PrimaryButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, isBusy: Boolean = false, enabled: Boolean = true, tag: String? = null) {
    Button(onClick, modifier.fillMaxWidth().heightIn(min = Theme.Layout.minTouchTarget + 4.dp).let { if (tag != null) it.testTag(tag) else it }, enabled = enabled && !isBusy) {
        Box(contentAlignment = Alignment.Center) {
            if (isBusy) CircularProgressIndicator(Modifier.size(20.dp), color = Theme.colors.brandOn, strokeWidth = 2.dp)
            else Text(title, fontWeight = FontWeight.SemiBold)
        }
    }
}

/** Caps the width for readable forms on wide windows, centred (≈ `.readableWidth()`). */
fun Modifier.readableWidth(): Modifier = this.widthIn(max = Theme.Layout.maxReadableWidth)

/** A centred column at readable width. */
@Composable
fun ReadableColumn(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.readableWidth().fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Theme.Space.s)) { content() }
    }
}

/** A label and a value side by side (iOS: `AdaptiveRow`). */
@Composable
fun AdaptiveRow(label: @Composable () -> Unit, value: @Composable () -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) { label() }
        Spacer(Modifier.size(Theme.Space.s))
        value()
    }
}

/**
 * The decimal keyboard types the device locale's decimal separator, while the spec parsers (`spec/setup.md` §11)
 * read `.` as the decimal point and drop `,` as grouping. On comma-decimal locales a typed `,` becomes `.`.
 */
object DecimalPadText {
    fun normalized(text: String, locale: java.util.Locale = java.util.Locale.getDefault()): String =
        if (java.text.DecimalFormatSymbols.getInstance(locale).decimalSeparator == ',') text.replace(',', '.') else text
}

/** Human text for `FieldIssue`s; [field] is the field's name as shown on screen. iOS: `IssueMessages`. */
object IssueMessages {
    fun text(issue: FieldIssue, field: String, taxIDName: String = "tax ID", maxLength: Int? = null): String = when (issue) {
        FieldIssue.Required -> "Enter the ${field.lowercase()}"
        is FieldIssue.Invalid -> issue.rule.message(issue.error)
        is FieldIssue.InvalidTaxID -> when (issue.error) {
            TaxIDError.Format -> "This doesn't look like a $taxIDName. Check for missing or extra characters."
            TaxIDError.Checksum -> "This $taxIDName has a typo: its last character doesn't match."
            TaxIDError.UnknownRegion -> "The first two digits of this $taxIDName aren't a state code."
        }
        is FieldIssue.InvalidNumber -> when (issue.error) {
            InputError.TooManyDecimals -> "Too many decimal places"
            InputError.TooLarge -> "That number is too large"
            else -> "Enter a number, like 1250.50"
        }
        is FieldIssue.OutOfRange -> "Enter a number from ${issue.range.first} to ${issue.range.last}"
        is FieldIssue.InvalidPattern -> issue.issues.firstOrNull()?.let(::patternMessage) ?: "Check the pattern"
        is FieldIssue.InvalidNumbering -> when (issue.error) {
            NumberingError.NumberTooLong -> "Numbers made with this pattern would be longer than ${maxLength ?: "allowed"} characters"
            NumberingError.NumberInvalidChars -> "Numbers can only use letters, digits, / and -"
        }
        is FieldIssue.AlreadyIssued -> "Number ${issue.highest} has already been issued. Start at ${issue.highest + 1} or later."
        FieldIssue.ExceedsLineAmount -> "The discount is more than the line amount"
    }

    fun patternMessage(issue: NumberingPatternIssue): String = when (issue) {
        NumberingPatternIssue.MissingSequence -> "Add {seq:4} so every number is different"
        NumberingPatternIssue.MultipleSequences -> "Use {seq:N} only once"
        is NumberingPatternIssue.UnknownToken -> "${issue.raw} isn't a pattern token"
        is NumberingPatternIssue.InvalidSequenceWidth -> "${issue.raw}: use a width from 1 to 9, like {seq:4}"
    }
}

fun FieldRule.message(error: FieldError): String = when (this) {
    FieldRule.email -> "Enter an email address like name@example.com"
    FieldRule.ifsc -> "An IFSC has 11 characters, like SBIN0001234"
    FieldRule.upiVpa -> "A UPI ID looks like name@bank"
    FieldRule.sortCode -> "A sort code has 6 digits, like 12-34-56"
    FieldRule.iban -> if (error == FieldError.Checksum) "This IBAN has a typo: its check digits don't match" else "Check the IBAN"
    FieldRule.bic -> "A SWIFT/BIC code has 8 or 11 characters"
    FieldRule.pan -> "A PAN has 10 characters, like ABCDE1234F"
    FieldRule.postalCodeIN -> "A PIN code has 6 digits"
    FieldRule.postalCodeGB -> "Enter a UK postcode, like SW1A 1AA"
    FieldRule.companyNumberGB -> "A company number has 8 characters, like 01234567 or SC123456"
    FieldRule.hsnSac -> "HSN and SAC codes have 2 to 8 digits"
}
