package app.invoicebuilder.android.common

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import app.invoicebuilder.core.designsystem.ChoiceRow
import app.invoicebuilder.core.designsystem.FormSection
import app.invoicebuilder.core.designsystem.FormTextField
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.designsystem.IssueText
import app.invoicebuilder.core.designsystem.LabeledValue
import app.invoicebuilder.core.designsystem.PickerField
import app.invoicebuilder.core.designsystem.SuccessText
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.setup.BusinessDraft
import app.invoicebuilder.core.domain.setup.BusinessField
import app.invoicebuilder.core.domain.setup.BusinessRules
import app.invoicebuilder.core.domain.setup.FieldIssue
import app.invoicebuilder.core.domain.tax.TaxRegion

// Business form sections shared by onboarding (steps 2–4) and Settings → Business profile. Which fields appear and
// how they validate comes from `BusinessRules` (`spec/setup.md` §3–4). iOS: `BusinessFormSections.swift`.

/** Live feedback for a typed tax ID. */
sealed interface TaxIDFeedback {
    /** Valid; for a GSTIN, the name of the state it belongs to. */
    data class Valid(val region: String?) : TaxIDFeedback
    data class Invalid(val message: String) : TaxIDFeedback
}

/** Registration type, India's turnover tier and (GENERIC onboarding) the first tax rate. */
@Composable
fun RegistrationSections(
    draft: BusinessDraft, onChange: (BusinessDraft) -> Unit, rules: BusinessRules, formatter: SpecFormatter,
    issue: (BusinessField) -> FieldIssue?, asksForFirstRate: Boolean = true,
) {
    val taxName = rules.config.labels.taxName
    FormSection("$taxName registration", "This decides whether your invoices charge $taxName and what they're called.") {
        for (registration in rules.config.registrations) {
            ChoiceRow(
                registration.label, draft.taxRegistration == registration.id, { onChange(draft.copy(taxRegistration = registration.id)) },
                subtitle = registrationHelp(rules.config.family, registration.id), tag = "registration-${registration.id}",
            )
        }
        issue(BusinessField.Registration)?.let { IssueText(IssueMessages.text(it, "registration type")) }
    }
    if (rules.showsTurnoverTier(draft)) {
        val tier = rules.turnoverTiers.getOrNull(draft.turnoverTier)
        val digits = tier?.let { if (it.b2bDigits == 0) "no HSN/SAC code" else "a ${it.b2bDigits}-digit HSN/SAC code" } ?: ""
        FormSection("Turnover in the previous financial year",
            "Your B2B invoices then need $digits on every line. We only store the band, never the amount.") {
            rules.turnoverTiers.indices.forEach { index ->
                ChoiceRow(tierLabel(rules, formatter, index), draft.turnoverTier == index, { onChange(draft.copy(turnoverTier = index)) })
            }
        }
    }
    if (asksForFirstRate && rules.asksForFirstTaxRate(draft)) {
        FormSection("Your tax", "You can add more rates, or a second tax, later in Settings.") {
            FormTextField("Tax name", draft.genericTaxName, { onChange(draft.copy(genericTaxName = it)) }, prompt = "Sales tax",
                issue = issue(BusinessField.GenericTaxName)?.let { IssueMessages.text(it, "tax name") }, capitalization = KeyboardCapitalization.Words)
            FormTextField("Rate (%)", draft.genericTaxPercent, { onChange(draft.copy(genericTaxPercent = it)) }, prompt = "8.875",
                issue = issue(BusinessField.GenericTaxPercent)?.let { IssueMessages.text(it, "rate") }, keyboard = KeyboardType.Decimal)
        }
    }
}

/** "Up to ₹5 crore" / "More than ₹5 crore", from the config's tier bounds (`spec/setup.md` §3.1). */
private fun tierLabel(rules: BusinessRules, formatter: SpecFormatter, index: Int): String {
    val tiers = rules.turnoverTiers
    val upper = tiers[index].maxTurnoverMinor
    val lower = if (index > 0) tiers[index - 1].maxTurnoverMinor else null
    fun amount(minor: Long): String {
        val currency = rules.config.currency ?: CurrencyCode("USD")
        if (currency == CurrencyCode.INR) {
            val symbol = formatter.currencies[CurrencyCode.INR]?.symbol ?: "₹"
            if (minor % 1_000_000_000L == 0L) return "$symbol${minor / 1_000_000_000L} crore"
            if (minor % 10_000_000L == 0L) return "$symbol${minor / 10_000_000L} lakh"
        }
        return formatter.money(minor, currency, currency)
    }
    return when {
        lower == null && upper != null -> "Up to ${amount(upper)}"
        lower != null && upper == null -> "More than ${amount(lower)}"
        lower != null && upper != null -> "${amount(lower)} to ${amount(upper)}"
        else -> "Any turnover"
    }
}

fun registrationHelp(family: String, registration: String): String = when ("$family.$registration") {
    "IN.regular" -> "You charge GST and issue tax invoices."
    "IN.composition" -> "You pay tax under the composition scheme and issue bills of supply, without GST."
    "IN.unregistered" -> "You're not registered for GST, so your invoices show no GST."
    "GB.vatRegistered" -> "You charge VAT and issue VAT invoices."
    "GB.notRegistered" -> "You're not VAT registered, so your invoices show no VAT."
    "GENERIC.registered" -> "You add tax to your invoices."
    "GENERIC.notRegistered" -> "Your invoices show no tax."
    else -> ""
}

/** Name, tax ID, address, contact and other identifiers. */
@Composable
fun BusinessDetailsSections(
    draft: BusinessDraft, onChange: (BusinessDraft) -> Unit, rules: BusinessRules, issue: (BusinessField) -> FieldIssue?,
    taxIDFeedback: TaxIDFeedback?,
) {
    val labels = rules.config.labels
    fun message(field: BusinessField, name: String) = issue(field)?.let { IssueMessages.text(it, name) }
    FormSection("Business") {
        FormTextField("Business name", draft.name, { onChange(draft.copy(name = it)) }, prompt = "As shown on your invoices",
            issue = message(BusinessField.Name, "business name"), capitalization = KeyboardCapitalization.Words, tag = "businessName")
        FormTextField("Legal name (optional)", draft.legalName, { onChange(draft.copy(legalName = it)) },
            prompt = "If different from the business name", capitalization = KeyboardCapitalization.Words)
    }
    if (rules.showsTaxID(draft)) {
        val taxIDIssue = issue(BusinessField.TaxId)?.let { IssueMessages.text(it, labels.taxIdName, labels.taxIdName) }
        FormSection(footer = if (rules.isIndia) "Your state is read from the first two digits." else null) {
            Column {
                FormTextField(
                    if (rules.requiresTaxID(draft)) labels.taxIdName else "${labels.taxIdName} (optional)",
                    draft.taxId, { onChange(draft.copy(taxId = it)) },
                    prompt = when (rules.config.family) { "IN" -> "29ABCDE1234F1Z5"; "GB" -> "GB123456789"; else -> "Your tax registration number" },
                    issue = taxIDIssue, capitalization = KeyboardCapitalization.Characters, autocorrect = false, tag = "businessTaxId",
                )
                when (taxIDFeedback) {
                    is TaxIDFeedback.Valid -> SuccessText(taxIDFeedback.region?.let { "Valid · $it" } ?: "Valid")
                    is TaxIDFeedback.Invalid -> if (taxIDIssue == null) IssueText(taxIDFeedback.message)
                    null -> {}
                }
            }
        }
    }
    FormSection("Address") {
        val address = draft.address
        FormTextField("Address line 1", address.line1, { onChange(draft.copy(address = address.copy(line1 = it))) }, prompt = "Building, street",
            issue = message(BusinessField.AddressLine1, "address"), capitalization = KeyboardCapitalization.Words, tag = "businessAddress1")
        FormTextField("Address line 2 (optional)", address.line2, { onChange(draft.copy(address = address.copy(line2 = it))) },
            capitalization = KeyboardCapitalization.Words)
        FormTextField(if (rules.isIndia) "City or town" else "Town or city", address.city, { onChange(draft.copy(address = address.copy(city = it))) },
            capitalization = KeyboardCapitalization.Words)
        FormTextField(if (rules.isIndia) "PIN code" else "Postcode", address.postalCode, { onChange(draft.copy(address = address.copy(postalCode = it))) },
            issue = message(BusinessField.PostalCode, "postcode"), keyboard = if (rules.isIndia) KeyboardType.Number else KeyboardType.Text,
            capitalization = KeyboardCapitalization.Characters, autocorrect = false)
        if (rules.showsRegion) {
            RegionPicker(labels.regionName ?: "State", draft.regionCode, { onChange(draft.copy(regionCode = it)) }, rules.config.activeRegionsByName,
                rules.regionFromTaxID(draft), "From your ${labels.taxIdName}", message(BusinessField.Region, labels.regionName ?: "state"))
        }
    }
    FormSection("Contact (optional)") {
        FormTextField("Email", draft.email, { onChange(draft.copy(email = it)) }, prompt = "billing@example.com",
            issue = message(BusinessField.Email, "email"), keyboard = KeyboardType.Email, capitalization = KeyboardCapitalization.None, autocorrect = false)
        FormTextField("Phone", draft.phone, { onChange(draft.copy(phone = it)) }, keyboard = KeyboardType.Phone)
        FormTextField("Website", draft.website, { onChange(draft.copy(website = it)) }, keyboard = KeyboardType.Uri,
            capitalization = KeyboardCapitalization.None, autocorrect = false)
    }
    if (rules.isIndia) {
        FormSection("Other IDs", "Filled in from your GSTIN when possible.") {
            FormTextField("PAN (optional)", draft.pan, { onChange(draft.copy(pan = it)) }, prompt = "ABCDE1234F",
                issue = message(BusinessField.Pan, "PAN"), capitalization = KeyboardCapitalization.Characters, autocorrect = false)
        }
    }
    if (rules.isUK) {
        FormSection("Limited company", "Limited companies show their company number and registered office on invoices.") {
            FormTextField("Company number (optional)", draft.companyNumber, { onChange(draft.copy(companyNumber = it)) }, prompt = "01234567",
                issue = message(BusinessField.CompanyNumber, "company number"), capitalization = KeyboardCapitalization.Characters, autocorrect = false)
            FormTextField("Registered office (optional)", draft.registeredOffice, { onChange(draft.copy(registeredOffice = it)) },
                prompt = "If different from the address above", capitalization = KeyboardCapitalization.Words, multiline = true)
        }
    }
}

/** Bank account, international details and UPI (all optional). */
@Composable
fun BankSections(draft: BusinessDraft, onChange: (BusinessDraft) -> Unit, rules: BusinessRules, issue: (BusinessField) -> FieldIssue?) {
    fun message(field: BusinessField) = issue(field)?.let { IssueMessages.text(it, "") }
    FormSection("Bank account", "Printed on your invoices so clients know where to pay. Everything here is optional.") {
        FormTextField("Account name", draft.bankAccountName, { onChange(draft.copy(bankAccountName = it)) }, capitalization = KeyboardCapitalization.Words)
        FormTextField("Account number", draft.bankAccountNumber, { onChange(draft.copy(bankAccountNumber = it)) }, keyboard = KeyboardType.Number, autocorrect = false)
        FormTextField("Bank name", draft.bankName, { onChange(draft.copy(bankName = it)) }, capitalization = KeyboardCapitalization.Words)
        if (rules.isIndia) {
            FormTextField("IFSC", draft.ifsc, { onChange(draft.copy(ifsc = it)) }, prompt = "SBIN0001234", issue = message(BusinessField.Ifsc),
                capitalization = KeyboardCapitalization.Characters, autocorrect = false)
        }
        if (rules.isUK) {
            FormTextField("Sort code", draft.sortCode, { onChange(draft.copy(sortCode = it)) }, prompt = "12-34-56", issue = message(BusinessField.SortCode),
                keyboard = KeyboardType.Phone, autocorrect = false)
        }
    }
    if (rules.isIndia) {
        FormSection("UPI", "Adds a scan-to-pay UPI QR code to your invoices.") {
            FormTextField("UPI ID", draft.upiVpa, { onChange(draft.copy(upiVpa = it)) }, prompt = "yourname@bank", issue = message(BusinessField.UpiVpa),
                keyboard = KeyboardType.Email, capitalization = KeyboardCapitalization.None, autocorrect = false)
        }
    }
    FormSection("International payments (optional)") {
        FormTextField("IBAN", draft.iban, { onChange(draft.copy(iban = it)) }, issue = message(BusinessField.Iban),
            capitalization = KeyboardCapitalization.Characters, autocorrect = false)
        FormTextField("SWIFT / BIC", draft.swift, { onChange(draft.copy(swift = it)) }, issue = message(BusinessField.Swift),
            capitalization = KeyboardCapitalization.Characters, autocorrect = false)
    }
}

/** A state picker; read-only when a valid GSTIN already names the state. */
@Composable
fun RegionPicker(
    title: String, selection: String?, onSelect: (String?) -> Unit, regions: List<TaxRegion>,
    lockedTo: String? = null, lockedReason: String? = null, issue: String? = null,
) {
    if (lockedTo != null) {
        LabeledValue(title, (regions.firstOrNull { it.code == lockedTo }?.name ?: lockedTo) + (lockedReason?.let { "\n$it" } ?: ""))
    } else {
        PickerField(title, selection, regions.map { it.code to it.name }, onSelect, none = "Choose", issue = issue, searchable = true)
    }
}
