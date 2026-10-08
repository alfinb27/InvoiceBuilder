package app.invoicebuilder.core.domain.setup

import app.invoicebuilder.core.domain.decimal.DecimalInput
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.models.BankDetails
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.ExtraIDs
import app.invoicebuilder.core.domain.models.TemplateID
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.support.removingWhitespace
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.ProductCodeTier
import app.invoicebuilder.core.domain.tax.RatesSource
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.tax.TaxIDValidation
import app.invoicebuilder.core.domain.tax.TaxIDValidator
import app.invoicebuilder.core.domain.tax.TaxRegistration
import app.invoicebuilder.core.domain.validation.FieldRule
import java.time.LocalDate

/** The onboarding steps, in order (`spec/setup.md` §3). */
enum class OnboardingStep { country, registration, business, bank, images }

enum class BusinessField(val step: OnboardingStep?) {
    Country(OnboardingStep.country), HomeCurrency(OnboardingStep.country),
    Registration(OnboardingStep.registration), GenericTaxName(OnboardingStep.registration), GenericTaxPercent(OnboardingStep.registration),
    Name(OnboardingStep.business), TaxId(OnboardingStep.business), AddressLine1(OnboardingStep.business), Region(OnboardingStep.business),
    PostalCode(OnboardingStep.business), Email(OnboardingStep.business), Pan(OnboardingStep.business), CompanyNumber(OnboardingStep.business),
    Ifsc(OnboardingStep.bank), SortCode(OnboardingStep.bank), Iban(OnboardingStep.bank), Swift(OnboardingStep.bank), UpiVpa(OnboardingStep.bank),
    PaymentTermsDays(null), ReminderDaysAfterDue(null),
}

/** A business being set up or edited: plain text fields, normalised when saved. iOS: `BusinessDraft`. */
data class BusinessDraft(
    val countryCode: String? = null,
    /** GENERIC only; IN and GB use the config's currency. */
    val homeCurrency: CurrencyCode? = null,
    val taxRegistration: String? = null,
    /** Index into the config's `productCodes.tiers` (`spec/setup.md` §3.1). */
    val turnoverTier: Int = 0,
    /** GENERIC onboarding: the first custom rate (`spec/setup.md` §7). */
    val genericTaxName: String = "Tax",
    val genericTaxPercent: String = "",
    val name: String = "",
    val legalName: String = "",
    val taxId: String = "",
    val address: AddressDraft = AddressDraft(),
    val regionCode: String? = null,
    val email: String = "",
    val phone: String = "",
    val website: String = "",
    val pan: String = "",
    val companyNumber: String = "",
    val registeredOffice: String = "",
    val lutReference: String = "",
    val lutValidUntil: LocalDate? = null,
    val bankAccountName: String = "",
    val bankAccountNumber: String = "",
    val bankName: String = "",
    val ifsc: String = "",
    val sortCode: String = "",
    val iban: String = "",
    val swift: String = "",
    val upiVpa: String = "",
    val paymentTermsDays: Int = 15,
    val defaultNotes: String = "",
    val defaultTerms: String = "",
    val templateId: TemplateID = TemplateID.modern,
    val accentColor: String? = null,
    val reminderDaysAfterDue: Int? = null,
) {
    companion object {
        /** The draft for editing [business] in Settings. */
        fun of(business: Business, rules: BusinessRules) = BusinessDraft(
            countryCode = business.countryCode, homeCurrency = business.homeCurrency, taxRegistration = business.taxRegistration,
            turnoverTier = rules.turnoverTier(business.turnoverMinor), name = business.name, legalName = business.legalName ?: "",
            taxId = business.taxId ?: "", address = AddressDraft(business.address), regionCode = business.address?.regionCode,
            email = business.email ?: "", phone = business.phone ?: "", website = business.website ?: "",
            pan = business.extraIds?.pan ?: "", companyNumber = business.extraIds?.companyNumber ?: "",
            registeredOffice = business.extraIds?.registeredOffice ?: "", lutReference = business.extraIds?.lutReference ?: "",
            lutValidUntil = business.extraIds?.lutValidUntil, bankAccountName = business.bank?.accountName ?: "",
            bankAccountNumber = business.bank?.accountNumber ?: "", bankName = business.bank?.bankName ?: "",
            ifsc = business.bank?.ifsc ?: "", sortCode = business.bank?.sortCode ?: "", iban = business.bank?.iban ?: "",
            swift = business.bank?.swift ?: "", upiVpa = business.upiVpa ?: "", paymentTermsDays = business.paymentTermsDays,
            defaultNotes = business.defaultNotes ?: "", defaultTerms = business.defaultTerms ?: "", templateId = business.templateId,
            accentColor = business.accentColor, reminderDaysAfterDue = business.reminderDaysAfterDue,
        )
    }
}

/**
 * Which business fields apply, how they validate and what they derive, for one tax config (`spec/setup.md` §3–4).
 * iOS: `BusinessRules`.
 */
class BusinessRules(val config: TaxConfig) {
    companion object {
        val paymentTermsRange = 0..365
        val reminderDaysRange = 0..60
    }

    fun registration(draft: BusinessDraft): TaxRegistration? = draft.taxRegistration?.let(config::registration)
    fun chargesTax(draft: BusinessDraft): Boolean = registration(draft)?.chargesTax ?: false

    /** GENERIC asks for the home currency; IN and GB use the config's. */
    val asksForHomeCurrency: Boolean get() = config.currency == null
    fun homeCurrency(draft: BusinessDraft): CurrencyCode? = config.currency ?: draft.homeCurrency

    val turnoverTiers: List<ProductCodeTier> get() = config.productCodes?.tiers ?: emptyList()

    /** IN regular and composition dealers pick a turnover tier (it sets the HSN digits they need). */
    fun showsTurnoverTier(draft: BusinessDraft): Boolean = turnoverTiers.size > 1 && registration(draft)?.requiresTaxId == true

    /** Tier 0 → null; tier k > 0 → the previous tier's bound + 1 (`spec/setup.md` §3.1). */
    fun turnoverMinor(tier: Int): Long? {
        if (tier <= 0 || tier >= turnoverTiers.size) return null
        return turnoverTiers[tier - 1].maxTurnoverMinor?.plus(1)
    }

    fun turnoverTier(turnoverMinor: Long?): Int {
        turnoverMinor ?: return 0
        val index = turnoverTiers.indexOfFirst { tier -> tier.maxTurnoverMinor?.let { turnoverMinor <= it } ?: true }
        return if (index < 0) 0 else index
    }

    /** GENERIC businesses that charge tax name their first rate during onboarding. */
    fun asksForFirstTaxRate(draft: BusinessDraft): Boolean = config.ratesFrom == RatesSource.business && chargesTax(draft)

    /** The config's tax ID when the registration requires one; a free-text tax ID for GENERIC charging registrations. */
    fun showsTaxID(draft: BusinessDraft): Boolean {
        val registration = registration(draft) ?: return false
        return if (config.taxIDFormat != null) registration.requiresTaxId else registration.chargesTax
    }

    fun requiresTaxID(draft: BusinessDraft): Boolean = config.taxIDFormat != null && registration(draft)?.requiresTaxId == true

    /** Live validation of a typed GSTIN / VAT number; null when blank or when the config has no format. */
    fun taxIDValidation(draft: BusinessDraft): TaxIDValidation? {
        if (!showsTaxID(draft) || draft.taxId.trimmedOrNull == null) return null
        return TaxIDValidator.validate(draft.taxId, config)
    }

    /** The state a valid GSTIN names; the region picker is then read-only. */
    fun regionFromTaxID(draft: BusinessDraft): String? = taxIDValidation(draft)?.takeIf { it.valid }?.region

    val showsRegion: Boolean get() = config.regions.isNotEmpty()
    fun region(draft: BusinessDraft): String? = if (showsRegion) regionFromTaxID(draft) ?: draft.regionCode else null

    val isIndia: Boolean get() = config.family == "IN"
    val isUK: Boolean get() = config.family == "GB"

    /** Exports under LUT (IN regular dealers only). */
    fun showsLUT(draft: BusinessDraft): Boolean = isIndia && registration(draft)?.chargesTax == true

    /** Fills fields that follow from others: an empty PAN from a valid GSTIN (characters 3–12). */
    fun applyDerivations(draft: BusinessDraft): BusinessDraft {
        if (!isIndia || draft.pan.trimmedOrNull != null) return draft
        val validation = taxIDValidation(draft) ?: return draft
        if (!validation.valid || validation.normalized.length != 15) return draft
        return draft.copy(pan = validation.normalized.substring(2, 12))
    }

    /** Issues for the fields of [steps] (every field, including profile-only ones, when null). */
    fun issues(draft: BusinessDraft, steps: Set<OnboardingStep>? = null): Map<BusinessField, FieldIssue> {
        val issues = mutableMapOf<BusinessField, FieldIssue>()
        fun includes(step: OnboardingStep) = steps?.contains(step) ?: true
        if (includes(OnboardingStep.country)) {
            if (draft.countryCode == null) issues[BusinessField.Country] = FieldIssue.Required
            if (asksForHomeCurrency && draft.homeCurrency == null) issues[BusinessField.HomeCurrency] = FieldIssue.Required
        }
        if (includes(OnboardingStep.registration)) {
            if (registration(draft) == null) issues[BusinessField.Registration] = FieldIssue.Required
            if (asksForFirstTaxRate(draft)) {
                if (draft.genericTaxName.trimmedOrNull == null) issues[BusinessField.GenericTaxName] = FieldIssue.Required
                CustomRates.percentIssue(draft.genericTaxPercent)?.let { issues[BusinessField.GenericTaxPercent] = it }
            }
        }
        if (includes(OnboardingStep.business)) {
            if (draft.name.trimmedOrNull == null) issues[BusinessField.Name] = FieldIssue.Required
            if (showsTaxID(draft)) {
                val validation = taxIDValidation(draft)
                if (validation != null) validation.error?.let { issues[BusinessField.TaxId] = FieldIssue.InvalidTaxID(it) }
                else if (requiresTaxID(draft)) issues[BusinessField.TaxId] = FieldIssue.Required
            }
            val (line1, postal) = draft.address.issues(draft.countryCode ?: "", lineRequired = true)
            line1?.let { issues[BusinessField.AddressLine1] = it }
            postal?.let { issues[BusinessField.PostalCode] = it }
            if (showsRegion && region(draft) == null) issues[BusinessField.Region] = FieldIssue.Required
            issues.check(BusinessField.Email, draft.email, FieldRule.email)
            if (isIndia) issues.check(BusinessField.Pan, draft.pan, FieldRule.pan)
            if (isUK) issues.check(BusinessField.CompanyNumber, draft.companyNumber, FieldRule.companyNumberGB)
        }
        if (includes(OnboardingStep.bank)) {
            if (isIndia) {
                issues.check(BusinessField.Ifsc, draft.ifsc, FieldRule.ifsc)
                issues.check(BusinessField.UpiVpa, draft.upiVpa, FieldRule.upiVpa)
            }
            if (isUK) issues.check(BusinessField.SortCode, draft.sortCode, FieldRule.sortCode)
            issues.check(BusinessField.Iban, draft.iban, FieldRule.iban)
            issues.check(BusinessField.Swift, draft.swift, FieldRule.bic)
        }
        if (steps == null) {
            if (draft.paymentTermsDays !in paymentTermsRange) issues[BusinessField.PaymentTermsDays] = FieldIssue.OutOfRange(paymentTermsRange)
            draft.reminderDaysAfterDue?.let { if (it !in reminderDaysRange) issues[BusinessField.ReminderDaysAfterDue] = FieldIssue.OutOfRange(reminderDaysRange) }
        }
        return issues
    }

    /** A new business from a complete onboarding draft (`spec/setup.md` §3, Finish). */
    fun makeBusiness(draft: BusinessDraft, id: String, now: Long, today: LocalDate, newID: () -> String): Business {
        var business = Business(
            id = id, createdAt = now, updatedAt = now, name = "", countryCode = draft.countryCode ?: config.country,
            taxConfig = config.family, taxRegistration = draft.taxRegistration ?: config.registrations[0].id,
            homeCurrency = homeCurrency(draft) ?: CurrencyCode("USD"),
        )
        business = apply(draft, business)
        if (config.ratesFrom == RatesSource.business) {
            val percent = (DecimalInput.parse(draft.genericTaxPercent) as? Outcome.Success)?.value ?: "0"
            business = business.copy(customRates = CustomRates.initialRates(chargesTax(draft), draft.genericTaxName, percent, today, newID))
        }
        return business
    }

    /** [business] with every editable field taken from [draft] (Settings → Business profile). */
    fun updating(business: Business, draft: BusinessDraft): Business = apply(draft, business)

    private fun apply(draft: BusinessDraft, business: Business): Business {
        val country = business.countryCode
        val lut = showsLUT(draft)
        val extra = (business.extraIds ?: ExtraIDs()).copy(
            pan = if (isIndia) normalized(draft.pan, FieldRule.pan) else null,
            companyNumber = if (isUK) normalized(draft.companyNumber, FieldRule.companyNumberGB) else null,
            registeredOffice = if (isUK) draft.registeredOffice.trimmedOrNull else null,
            lutReference = if (lut) draft.lutReference.trimmedOrNull?.uppercase() else null,
            lutValidUntil = if (lut) draft.lutValidUntil else null,
        )
        val bank = BankDetails(
            accountName = draft.bankAccountName.trimmedOrNull,
            accountNumber = draft.bankAccountNumber.removingWhitespace.trimmedOrNull,
            bankName = draft.bankName.trimmedOrNull,
            ifsc = if (isIndia) normalized(draft.ifsc, FieldRule.ifsc) else null,
            sortCode = if (isUK) normalized(draft.sortCode, FieldRule.sortCode) else null,
            iban = normalized(draft.iban, FieldRule.iban),
            swift = normalized(draft.swift, FieldRule.bic),
        )
        return business.copy(
            taxRegistration = draft.taxRegistration ?: business.taxRegistration,
            name = draft.name.trimmedOrNull ?: business.name,
            legalName = draft.legalName.trimmedOrNull,
            address = draft.address.address(country, region(draft)),
            email = normalized(draft.email, FieldRule.email),
            phone = draft.phone.trimmedOrNull,
            website = draft.website.trimmedOrNull,
            taxId = if (showsTaxID(draft)) taxIDValidation(draft)?.normalized ?: draft.taxId.trimmedOrNull else null,
            extraIds = extra.takeUnless { it.isEmpty },
            turnoverMinor = if (showsTurnoverTier(draft)) turnoverMinor(draft.turnoverTier) else null,
            bank = bank.takeUnless { it.isEmpty },
            upiVpa = if (isIndia) normalized(draft.upiVpa, FieldRule.upiVpa) else null,
            paymentTermsDays = draft.paymentTermsDays,
            defaultNotes = draft.defaultNotes.trimmedOrNull,
            defaultTerms = draft.defaultTerms.trimmedOrNull,
            templateId = draft.templateId,
            accentColor = draft.accentColor,
            reminderDaysAfterDue = draft.reminderDaysAfterDue,
        )
    }
}
