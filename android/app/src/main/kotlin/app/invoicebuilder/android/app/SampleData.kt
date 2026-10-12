package app.invoicebuilder.android.app

import app.invoicebuilder.core.domain.documents.DocumentRules
import app.invoicebuilder.core.domain.documents.PaymentMethod
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.models.ItemKind
import app.invoicebuilder.core.domain.setup.AddressDraft
import app.invoicebuilder.core.domain.setup.BusinessDraft
import app.invoicebuilder.core.domain.setup.BusinessRules
import app.invoicebuilder.core.domain.setup.BusinessSetup
import app.invoicebuilder.core.domain.setup.CatalogItemDraft
import app.invoicebuilder.core.domain.setup.CatalogItemRules
import app.invoicebuilder.core.domain.setup.ClientDraft
import app.invoicebuilder.core.domain.setup.ClientRules
import app.invoicebuilder.core.domain.support.SpecLoadingError
import kotlinx.coroutines.flow.first

/** Sample businesses, clients and items for the demo, UI tests and screenshots. iOS: `SampleData`. */
object SampleData {
    enum class Country(val rawValue: String) {
        india("IN"), uk("GB");

        companion object { fun of(raw: String?) = entries.firstOrNull { it.rawValue == raw } }
    }

    /** Onboards a sample business on this device and fills its client list and catalogue. */
    suspend fun seed(country: Country, container: AppContainer, deviceID: String): Business {
        val config = container.taxConfigs.latest(country.rawValue) ?: throw SpecLoadingError("tax/${country.rawValue}.json", "missing")
        val rules = BusinessRules(config)
        val today = container.time.today()
        var draft = when (country) {
            Country.india -> BusinessDraft(
                countryCode = "IN", taxRegistration = "regular", name = "Bharat Web Studio", legalName = "Bharat Web Studio LLP",
                taxId = "29AAGCB7383J1Z4", address = AddressDraft("12 MG Road", "", "Bengaluru", "560001"),
                email = "hello@bharatweb.example", phone = "+91 80 5555 0100", bankAccountName = "Bharat Web Studio LLP",
                bankAccountNumber = "000123456789", bankName = "Example Bank", ifsc = "EXMP0001234", upiVpa = "bharatweb@examplebank",
            )
            Country.uk -> BusinessDraft(
                countryCode = "GB", taxRegistration = "vatRegistered", name = "Thames Design Ltd", taxId = "GB980780684",
                address = AddressDraft("1 Bridge Street", "", "London", "SE1 9DA"), email = "studio@thamesdesign.example",
                companyNumber = "01234567", bankAccountName = "Thames Design Ltd", bankAccountNumber = "12345678", sortCode = "12-34-56",
            )
        }
        draft = rules.applyDerivations(draft)
        val business = rules.makeBusiness(draft, container.ids.make(), container.time.now(), today, container.ids.make)
        val series = BusinessSetup.defaultSeries(business.id, config, deviceID, container.time.now(), container.ids.make)
        val created = container.setup.createBusiness(business, series, null, null, deviceID)

        val clientRules = ClientRules(config, country.rawValue)
        for (sample in clients(country)) {
            container.clients.save(clientRules.makeClient(sample, container.ids.make(), created.id, container.time.now()))
        }
        val itemRules = CatalogItemRules(config, created, container.reference.currencies, container.reference.units, today)
        for (sample in items(country)) container.catalog.save(itemRules.makeItem(sample, container.ids.make(), container.time.now()))
        return created
    }

    /** The demo's documents: a paid invoice, an overdue one, a partly paid one and an open quote. */
    suspend fun addDemoDocuments(business: Business, container: AppContainer, deviceID: String) {
        val rules = DocumentRules(container.taxConfigs, business, container.reference.currencies)
        val today = container.time.today()
        val clients = container.clients.observeClients(business.id).first().sortedBy { it.name }
        val catalog = container.catalog.observeItems(business.id).first()
        if (clients.isEmpty() || catalog.isEmpty()) return

        suspend fun make(docType: DocumentType, client: Client, items: List<CatalogItem>, issuedDaysAgo: Long) =
            rules.newDocument(docType, container.ids.make(), today.minusDays(issuedDaysAgo), client, container.time.now()).let { start ->
                var document = start
                for (item in items) document = document.copy(lines = document.lines + rules.line(item, document, container.ids.make()).first)
                val saved = container.documents.saveDraft(rules.preparedDraft(document, client))
                container.documentService.issue(saved.id, deviceID)
            }

        val second = clients[if (clients.size > 1) 1 else 0]
        val paid = make(DocumentType.invoice, clients[0], catalog.take(1), 20)
        container.paymentService.recordPayment(
            paid.id, paid.totals.totalMinor, today.minusDays(5),
            if (business.countryCode == "IN") PaymentMethod.upi else PaymentMethod.bank, null, null,
        )
        make(DocumentType.invoice, second, catalog.take(2), 45)
        val partly = make(DocumentType.invoice, clients[0], catalog.takeLast(1), 3)
        container.paymentService.recordPayment(partly.id, partly.totals.totalMinor / 2, today, PaymentMethod.cash, null, null)
        make(DocumentType.quote, second, catalog.take(3), 1)
    }

    fun clients(country: Country): List<ClientDraft> {
        fun client(name: String, country: String, business: Boolean = false, taxId: String = "", region: String? = null,
                   line1: String = "", city: String = "", postal: String = "", email: String = "") =
            ClientDraft(countryCode = country, name = name, isBusiness = business, taxId = taxId, regionCode = region,
                billing = AddressDraft(line1, "", city, postal), email = email)
        return when (country) {
            Country.india -> listOf(
                client("Rao Traders", "IN", true, "29AABCR1234C1ZU", line1 = "5 Residency Road", city = "Bengaluru", postal = "560025"),
                client("Umesh Foods", "IN", true, "27AAPFU0939F1ZV", line1 = "8 Link Road", city = "Mumbai", postal = "400053",
                    email = "accounts@umeshfoods.example"),
                client("Anita Sharma", "IN", region = "29", line1 = "44 Indiranagar", city = "Bengaluru", postal = "560038"),
                client("Acme Inc.", "US", true, "EIN 12-3456789", line1 = "200 Main St", city = "Springfield"),
            )
            Country.uk -> listOf(
                client("Blackfriars Café", "GB", true, "GB999999973", line1 = "3 Blackfriars Lane", city = "London", postal = "EC4V 6ER"),
                client("Anna Clarke", "GB", line1 = "17 Mill Road", city = "Cambridge", postal = "CB1 2AD"),
                client("Müller GmbH", "DE", true, "DE123456789", line1 = "Hauptstraße 5", city = "Berlin", postal = "10115"),
            )
        }
    }

    fun items(country: Country): List<CatalogItemDraft> {
        fun item(name: String, kind: ItemKind, unit: String, price: String, rate: String, code: String = "", inclusive: Boolean = false) =
            CatalogItemDraft(name = name, kind = kind, unit = unit, priceText = price, rateId = rate, productCode = code, priceIncludesTax = inclusive)
        return when (country) {
            Country.india -> listOf(
                item("Website development", ItemKind.service, "JOB", "5000", "gst_18", "998314"),
                item("SEO audit", ItemKind.service, "JOB", "4000", "gst_18", "998365"),
                item("Tea leaves", ItemKind.goods, "KGS", "240", "gst_5", "0902"),
                item("Fresh milk", ItemKind.goods, "LTR", "56", "exempt", "0401"),
            )
            Country.uk -> listOf(
                item("Logo design", ItemKind.service, "JOB", "450", "standard"),
                item("Consulting", ItemKind.service, "HRS", "85", "standard"),
                item("Printed children's books", ItemKind.goods, "PCS", "12.99", "zero", inclusive = true),
            )
        }
    }
}
