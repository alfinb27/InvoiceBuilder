package app.invoicebuilder.core.domain.setup

import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.tax.TaxIDValidation
import app.invoicebuilder.core.domain.tax.TaxIDValidator
import app.invoicebuilder.core.domain.validation.FieldRule

enum class ClientField { Name, Email, TaxId, Region, BillingLine1, BillingPostalCode, ShippingLine1, ShippingPostalCode }

/** A client being created or edited: plain text fields, normalised when saved. iOS: `ClientDraft`. */
data class ClientDraft(
    val countryCode: String,
    val name: String = "",
    val contactName: String = "",
    val email: String = "",
    val phone: String = "",
    val isBusiness: Boolean = false,
    val regionCode: String? = null,
    val taxId: String = "",
    val billing: AddressDraft = AddressDraft(),
    val hasShippingAddress: Boolean = false,
    val shipping: AddressDraft = AddressDraft(),
    val defaultCurrency: CurrencyCode? = null,
    val notes: String = "",
) {
    companion object {
        fun of(client: Client) = ClientDraft(
            countryCode = client.countryCode, name = client.name, contactName = client.contactName ?: "", email = client.email ?: "",
            phone = client.phone ?: "", isBusiness = client.isBusiness, regionCode = client.regionCode, taxId = client.taxId ?: "",
            billing = AddressDraft(client.billingAddress), hasShippingAddress = client.shippingAddress != null,
            shipping = AddressDraft(client.shippingAddress), defaultCurrency = client.defaultCurrency, notes = client.notes ?: "",
        )
    }
}

/** Which client fields apply and how they validate (`spec/setup.md` §5). iOS: `ClientRules`. */
class ClientRules(val config: TaxConfig, val businessCountry: String) {
    fun isDomestic(draft: ClientDraft): Boolean = draft.countryCode == businessCountry
    fun showsRegion(draft: ClientDraft): Boolean = isDomestic(draft) && config.regions.isNotEmpty()
    fun showsTaxID(draft: ClientDraft): Boolean = draft.isBusiness

    /** Domestic B2B tax IDs are checked with the config's format; foreign ones are free text. */
    fun validatesTaxID(draft: ClientDraft): Boolean = showsTaxID(draft) && isDomestic(draft) && config.taxIDFormat != null

    fun taxIDValidation(draft: ClientDraft): TaxIDValidation? {
        if (!validatesTaxID(draft) || draft.taxId.trimmedOrNull == null) return null
        return TaxIDValidator.validate(draft.taxId, config)
    }

    fun regionFromTaxID(draft: ClientDraft): String? =
        if (!showsRegion(draft)) null else taxIDValidation(draft)?.takeIf { it.valid }?.region

    fun region(draft: ClientDraft): String? = if (showsRegion(draft)) regionFromTaxID(draft) ?: draft.regionCode else null

    fun normalizedTaxID(draft: ClientDraft): String? {
        if (!showsTaxID(draft)) return null
        val text = draft.taxId.trimmedOrNull ?: return null
        return taxIDValidation(draft)?.normalized ?: text.uppercase()
    }

    fun issues(draft: ClientDraft): Map<ClientField, FieldIssue> {
        val issues = mutableMapOf<ClientField, FieldIssue>()
        if (draft.name.trimmedOrNull == null) issues[ClientField.Name] = FieldIssue.Required
        issues.check(ClientField.Email, draft.email, FieldRule.email)
        taxIDValidation(draft)?.error?.let { issues[ClientField.TaxId] = FieldIssue.InvalidTaxID(it) }
        val (billingLine, billingPostal) = draft.billing.issues(draft.countryCode, lineRequired = false)
        billingLine?.let { issues[ClientField.BillingLine1] = it }
        billingPostal?.let { issues[ClientField.BillingPostalCode] = it }
        if (draft.hasShippingAddress) {
            val (line, postal) = draft.shipping.issues(draft.countryCode, lineRequired = true)
            line?.let { issues[ClientField.ShippingLine1] = it }
            postal?.let { issues[ClientField.ShippingPostalCode] = it }
        }
        return issues
    }

    /** Another live client with the same normalised tax ID (a warning, never a block). */
    fun duplicate(draft: ClientDraft, editingID: String?, clients: List<Client>): Client? {
        val taxId = normalizedTaxID(draft) ?: return null
        return clients.firstOrNull { it.id != editingID && it.deletedAt == null && it.taxId == taxId }
    }

    fun makeClient(draft: ClientDraft, id: String, businessID: String, now: Long): Client =
        apply(draft, Client(id = id, createdAt = now, updatedAt = now, businessId = businessID, name = "", countryCode = draft.countryCode))

    fun updating(client: Client, draft: ClientDraft): Client = apply(draft, client)

    private fun apply(draft: ClientDraft, client: Client): Client {
        val region = region(draft)
        return client.copy(
            name = draft.name.trimmedOrNull ?: client.name, contactName = draft.contactName.trimmedOrNull,
            email = normalized(draft.email, FieldRule.email), phone = draft.phone.trimmedOrNull, isBusiness = draft.isBusiness,
            countryCode = draft.countryCode, regionCode = region, taxId = normalizedTaxID(draft),
            billingAddress = draft.billing.address(draft.countryCode, region),
            shippingAddress = if (draft.hasShippingAddress) draft.shipping.address(draft.countryCode, region) else null,
            defaultCurrency = draft.defaultCurrency, notes = draft.notes.trimmedOrNull,
        )
    }
}
