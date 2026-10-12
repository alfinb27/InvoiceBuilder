package app.invoicebuilder.core.domain.setup

import app.invoicebuilder.core.domain.decimal.InputError
import app.invoicebuilder.core.domain.decimal.MoneyInput
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.ItemKind
import app.invoicebuilder.core.domain.money.CurrencyCatalog
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.reference.QuantityUnit
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.tax.TaxRate
import app.invoicebuilder.core.domain.validation.FieldRule
import java.time.LocalDate

enum class CatalogItemField { Name, Unit, Price, Rate, ProductCode }

/** A catalogue item being created or edited: plain text fields, normalised when saved. iOS: `CatalogItemDraft`. */
data class CatalogItemDraft(
    val name: String = "",
    val description: String = "",
    val kind: ItemKind = ItemKind.service,
    val unit: String = ItemKind.service.defaultUnit,
    /** Typed price in the business home currency (`spec/setup.md` §11). */
    val priceText: String = "",
    val rateId: String? = null,
    val productCode: String = "",
    val priceIncludesTax: Boolean = false,
) {
    /** Switching kind moves the unit to the new kind's default if the unit was still the old default. */
    fun settingKind(newKind: ItemKind): CatalogItemDraft =
        copy(kind = newKind, unit = if (unit == kind.defaultUnit) newKind.defaultUnit else unit)

    companion object {
        fun of(item: CatalogItem, exponent: Int) = CatalogItemDraft(
            name = item.name, description = item.description ?: "", kind = item.kind, unit = item.unit,
            priceText = MoneyInput.editingText(item.unitPriceMinor, exponent), rateId = item.rateId,
            productCode = item.productCode ?: "", priceIncludesTax = item.priceIncludesTax,
        )
    }
}

/** Which item fields apply and how they validate for a business (`spec/setup.md` §10). iOS: `CatalogItemRules`. */
class CatalogItemRules(
    val config: TaxConfig,
    val business: Business,
    val currencies: CurrencyCatalog,
    val units: List<QuantityUnit>,
    val today: LocalDate,
) {
    val currency: CurrencyCode get() = business.homeCurrency
    val exponent: Int get() = currencies.exponent(currency)
    val chargesTax: Boolean get() = config.registration(business.taxRegistration)?.chargesTax ?: false

    /** Rates in force today, plus the item's saved rate when it no longer is (so it stays visible). */
    fun rateChoices(selected: String?): List<TaxRate> {
        val choices = config.ratesInForce(today, business.customRates).toMutableList()
        if (selected != null && choices.none { it.id == selected }) config.rate(selected, business.customRates)?.let { choices += it }
        return choices
    }

    /** False when the saved rate exists but is not in force today (the editor shows a warning). */
    fun isInForce(rateID: String): Boolean = config.rate(rateID, business.customRates)?.isInForce(today) ?: false

    val showsInclusivePrice: Boolean get() = chargesTax

    /** India: HSN/SAC digits only. */
    val productCodeRule: FieldRule? get() = if (config.family == "IN") FieldRule.hsnSac else null

    /** Digits the business must print on B2B / B2C invoices (the turnover tier, `ENGINE.md` Step 12). */
    val requiredProductCodeDigits: Pair<Int, Int>?
        get() {
            val tiers = config.productCodes?.tiers?.takeIf { it.isNotEmpty() } ?: return null
            val tier = business.turnoverMinor?.let { turnover -> tiers.firstOrNull { t -> t.maxTurnoverMinor?.let { turnover <= it } ?: true } } ?: tiers[0]
            return tier.b2bDigits to tier.b2cDigits
        }

    fun issues(draft: CatalogItemDraft): Map<CatalogItemField, FieldIssue> {
        val issues = mutableMapOf<CatalogItemField, FieldIssue>()
        if (draft.name.trimmedOrNull == null) issues[CatalogItemField.Name] = FieldIssue.Required
        if (units.none { it.id == draft.unit }) issues[CatalogItemField.Unit] = FieldIssue.Required
        (MoneyInput.parse(draft.priceText, exponent) as? Outcome.Failure)?.let {
            issues[CatalogItemField.Price] = if (it.error == InputError.Empty) FieldIssue.Required else FieldIssue.InvalidNumber(it.error)
        }
        if (draft.rateId?.let { config.rate(it, business.customRates) } == null) issues[CatalogItemField.Rate] = FieldIssue.Required
        productCodeRule?.let { issues.check(CatalogItemField.ProductCode, draft.productCode, it) }
        return issues
    }

    fun makeItem(draft: CatalogItemDraft, id: String, now: Long): CatalogItem = apply(
        draft,
        CatalogItem(id = id, createdAt = now, updatedAt = now, businessId = business.id, name = "", unit = draft.unit,
            unitPriceMinor = 0, currency = currency, rateId = ""),
    )

    fun updating(item: CatalogItem, draft: CatalogItemDraft): CatalogItem = apply(draft, item)

    private fun apply(draft: CatalogItemDraft, item: CatalogItem): CatalogItem = item.copy(
        name = draft.name.trimmedOrNull ?: item.name, description = draft.description.trimmedOrNull, kind = draft.kind, unit = draft.unit,
        unitPriceMinor = (MoneyInput.parse(draft.priceText, exponent) as? Outcome.Success)?.value ?: item.unitPriceMinor,
        currency = currency, rateId = draft.rateId ?: item.rateId,
        productCode = productCodeRule?.let { normalized(draft.productCode, it) } ?: draft.productCode.trimmedOrNull,
        priceIncludesTax = showsInclusivePrice && draft.priceIncludesTax,
    )
}
