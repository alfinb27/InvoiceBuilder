package app.invoicebuilder.core.data

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.invoicebuilder.core.domain.backup.BackupCodec
import app.invoicebuilder.core.domain.backup.BackupCounts
import app.invoicebuilder.core.domain.backup.BackupFile
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.documents.Document
import app.invoicebuilder.core.domain.documents.DocumentRules
import app.invoicebuilder.core.domain.documents.LineItem
import app.invoicebuilder.core.domain.documents.PaymentMethod
import app.invoicebuilder.core.domain.models.Address
import app.invoicebuilder.core.domain.models.BankDetails
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.models.ExtraIDs
import app.invoicebuilder.core.domain.models.ImagePayload
import app.invoicebuilder.core.domain.models.ItemKind
import app.invoicebuilder.core.domain.models.TemplateID
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.setup.BusinessSetup
import app.invoicebuilder.core.domain.setup.CustomRates
import app.invoicebuilder.core.domain.tax.Discount
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.time.LocalDate
import java.util.Base64

/**
 * A backup moves between an Android phone and an iPhone (`spec/backup.md` §1): each app's tests restore a file the
 * other app exported. Both apps build the same business (`populateSample`; iOS: `CrossPlatformBackupTests.swift`)
 * and export it to `spec/samples/backup-v1-from-<platform>.invoicebackup.json`. `make backup-samples` writes the
 * files again when an export changes.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CrossPlatformBackupTests {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var store: DataTests.TestStore
    private val catalog by lazy { RoomCatalogRepository(store.db, store.time) }

    @Before fun setUp() { store = DataTests.TestStore(context) }
    @After fun tearDown() { store.db.close() }

    companion object {
        val app = BackupFile.AppInfo("android", "sample")
        const val raoTraders = "c0000000-0000-4000-8000-000000000001"
        const val mehtaExports = "c0000000-0000-4000-8000-000000000002"
        /** What `populateSample` leaves live, on either app. */
        val live = BackupCounts(businesses = 1, clients = 3, catalogItems = 2, numberingSeries = 2, documents = 6, payments = 2, assets = 2)

        /** iOS: `TestStore.fullBusiness`. */
        val fullBusiness = Business(
            id = "b0000000-0000-4000-8000-000000000001", name = "Bharat Web Studio", legalName = "Bharat Web Studio LLP",
            address = Address(line1 = "12 MG Road", city = "Bengaluru", regionCode = "29", postalCode = "560001", countryCode = "IN"),
            email = "hello@example.in", phone = "+91 80 5555 0100", website = "https://example.in", countryCode = "IN",
            taxConfig = "IN", taxRegistration = "regular", taxId = "29AAGCB7383J1Z4",
            extraIds = ExtraIDs(pan = "AAGCB7383J", lutReference = "AD2903260123456", lutValidUntil = LocalDate.of(2027, 3, 31)),
            homeCurrency = CurrencyCode.INR, turnoverMinor = 5_000_000_001,
            bank = BankDetails(accountName = "Bharat Web Studio LLP", accountNumber = "000123456789", ifsc = "EXMP0001234"),
            upiVpa = "bharatweb@examplebank", paymentTermsDays = 30, defaultNotes = "Thank you", defaultTerms = "Net 30",
            templateId = TemplateID.classic, accentColor = "#0F766E", reminderDaysAfterDue = 3,
            customRates = listOf(CustomRates.noTax),
        )

        /** 4×4 and 4×2 PNGs, the same bytes on iOS. */
        val logo = ImagePayload(ImagePayload.PNG, Base64.getDecoder().decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR42mM45KH1HxkzkC4AAKgYIzHyuLugAAAAAElFTkSuQmCC"))
        val signature = ImagePayload(ImagePayload.PNG, Base64.getDecoder().decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAAEUlEQVR42mOQElX4j4wZ0AUApqoKcQiRqlwAAAAASUVORK5CYII="))

        fun sample(from: String) = File(System.getProperty("spec.root"), "samples/backup-v1-from-$from.invoicebackup.json")
    }

    /**
     * The full business with a logo and a signature; three live clients (one in another state, one archived) and a
     * deleted one; two items (one archived, priced with tax); an invoice with line and document discounts, partly paid
     * (a live and a deleted payment); an inter-state invoice with shipping, sent and paid in full; a void invoice; a
     * quote converted into an invoice draft; a draft with a decimal quantity; a deleted draft.
     */
    private suspend fun populateSample(): String {
        val device = store.devices.loadOrCreate("Pixel")
        val series = BusinessSetup.defaultSeries(fullBusiness.id, store.configs.latest("IN")!!, device.id, 0, store.ids.make)
        val business = store.setup.createBusiness(fullBusiness, series, logo, signature, device.id)
        store.clients.save(Client(
            id = raoTraders, businessId = business.id, name = "Rao Traders", contactName = "Anil Rao",
            email = "accounts@raotraders.example", phone = "+91 80 5555 0199",
            billingAddress = Address(line1 = "5 Residency Road", city = "Bengaluru", regionCode = "29", postalCode = "560025", countryCode = "IN"),
            shippingAddress = Address(line1 = "Plot 7", line2 = "Peenya Industrial Area", city = "Bengaluru", regionCode = "29",
                postalCode = "560058", countryCode = "IN"),
            countryCode = "IN", regionCode = "29", taxId = "29AABCR1234C1ZU", isBusiness = true, notes = "Pays by UPI",
        ))
        store.clients.save(Client(
            id = mehtaExports, businessId = business.id, name = "Mehta Exports",
            billingAddress = Address(line1 = "21 Nariman Point", city = "Mumbai", regionCode = "27", postalCode = "400021", countryCode = "IN"),
            countryCode = "IN", regionCode = "27", taxId = "27AAECM5678F1Z6", isBusiness = true,
        ))
        store.clients.save(Client(id = "c0000000-0000-4000-8000-000000000003", businessId = business.id, name = "Old Client",
            countryCode = "IN", regionCode = "29", archivedAt = 1_500))
        store.clients.save(Client(id = "c0000000-0000-4000-8000-000000000004", businessId = business.id, name = "Gone Ltd",
            countryCode = "IN", regionCode = "29"))
        store.clients.delete("c0000000-0000-4000-8000-000000000004")

        val website = CatalogItem(id = "ca000000-0000-4000-8000-000000000001", businessId = business.id, name = "Website design",
            description = "Design and build, up to five pages", kind = ItemKind.service, unit = "JOB", unitPriceMinor = 5_000_000,
            currency = CurrencyCode.INR, rateId = "gst_18", productCode = "998314")
        catalog.save(website)
        catalog.save(CatalogItem(id = "ca000000-0000-4000-8000-000000000002", businessId = business.id, name = "Printed brochures",
            kind = ItemKind.goods, unit = "NOS", unitPriceMinor = 2_500, currency = CurrencyCode.INR, rateId = "gst_5",
            productCode = "4911", priceIncludesTax = true, archivedAt = 1_500))

        val partlyPaid = sampleDraft(business, id = "d0000000-0000-4000-8000-000000000001", client = raoTraders, lines = listOf(
            LineItem(id = "da000000-0000-4000-8000-000000000001", catalogItemId = website.id, description = "Website design",
                productCode = "998314", unit = "JOB", unitPriceMinor = 5_000_000, discount = Discount.Percent("10"), rateId = "gst_18"),
            LineItem(id = "da000000-0000-4000-8000-000000000002", description = "Hosting", productCode = "998315", unit = "MON",
                quantity = "12", unitPriceMinor = 120_000, rateId = "gst_18"),
        )) { it.copy(discount = Discount.Amount(50_000), notes = "Thank you for your business", terms = "Payment within 30 days") }
        store.documentService.issue(partlyPaid.id, device.id)
        store.paymentService.recordPayment(partlyPaid.id, 1_000_000, store.time.today(), PaymentMethod.upi, "UTR1", null)
        val wrong = store.paymentService.recordPayment(partlyPaid.id, 1, store.time.today(), PaymentMethod.cash, null, "Typed by mistake")
        store.payments.softDelete(wrong.id)

        val interState = sampleDraft(business, id = "d0000000-0000-4000-8000-000000000002", client = mehtaExports, lines = listOf(
            LineItem(id = "da000000-0000-4000-8000-000000000003", description = "Logo pack", productCode = "998391", unit = "JOB",
                unitPriceMinor = 1_500_000, rateId = "gst_18"),
        )) { it.copy(shippingMinor = 25_000) }
        val sent = store.documentService.issue(interState.id, device.id)
        store.documents.markSent(sent.id, store.time.now())
        store.paymentService.recordPayment(sent.id, sent.totals.totalMinor, store.time.today(), PaymentMethod.bank, "NEFT42", null)

        val mistake = sampleDraft(business, id = "d0000000-0000-4000-8000-000000000003", client = raoTraders, lines = listOf(
            LineItem(id = "da000000-0000-4000-8000-000000000004", description = "Mistake", unitPriceMinor = 1_000, rateId = "gst_18"),
        ))
        store.documentService.issue(mistake.id, device.id)
        store.documentService.voidDocument(mistake.id, "Raised twice")

        val quote = sampleDraft(business, DocumentType.quote, id = "d0000000-0000-4000-8000-000000000004", client = raoTraders, lines = listOf(
            LineItem(id = "da000000-0000-4000-8000-000000000005", description = "Security audit", unit = "HRS", quantity = "6",
                unitPriceMinor = 250_000, rateId = "gst_18"),
        ))
        store.documentService.issue(quote.id, device.id)
        store.documentService.convertQuote(quote.id)

        sampleDraft(business, id = "d0000000-0000-4000-8000-000000000005", client = mehtaExports, lines = listOf(
            LineItem(id = "da000000-0000-4000-8000-000000000006", description = "Consulting", unit = "HRS", quantity = "2.5",
                unitPriceMinor = 300_000, rateId = "gst_18"),
        ))
        val dropped = sampleDraft(business, id = "d0000000-0000-4000-8000-000000000006", client = raoTraders, lines = listOf(
            LineItem(id = "da000000-0000-4000-8000-000000000007", description = "Dropped", unitPriceMinor = 10_000, rateId = "gst_18"),
        ))
        store.documentService.deleteDraft(dropped.id)
        return device.id
    }

    private suspend fun sampleDraft(
        business: Business, docType: DocumentType = DocumentType.invoice, id: String, client: String, lines: List<LineItem>,
        edit: (Document) -> Document = { it },
    ): Document {
        val rules = DocumentRules(store.configs, business, store.reference.currencies)
        val buyer = store.clients.fetchClient(client)
        val document = edit(rules.newDocument(docType, id, store.time.today(), buyer, 0).copy(lines = lines))
        return store.documents.saveDraft(rules.preparedDraft(document, buyer))
    }

    private fun taxComponents(): List<String> =
        store.db.openHelper.readableDatabase.query("SELECT DISTINCT component FROM tax_line WHERE deleted_at IS NULL ORDER BY 1").use { c ->
            buildList { while (c.moveToNext()) add(c.getString(0)) }
        }

    @Test
    fun aBackupExportedOnAnIPhoneRestores() = runTest {
        val preview = (BackupCodec.validate(sample(from = "ios").readBytes(), SpecMigrations.VERSION) as Outcome.Success).value
        assertEquals("ios", preview.file.app.platform)
        assertEquals(live, preview.live)

        val device = store.devices.loadOrCreate("Pixel")
        store.backup.restore(preview.file, device.id)
        // Every record comes back as the iPhone wrote it; the one change is that this device takes over the series.
        val expected = preview.file.data.sorted().let { data ->
            data.copy(numberingSeries = data.numberingSeries.map { it.copy(ownerDeviceId = device.id, updatedAt = 0) })
        }
        val exported = store.backup.makeBackup(app).data.let { data ->
            data.copy(numberingSeries = data.numberingSeries.map { it.copy(updatedAt = 0) })
        }
        assertEquals(expected, exported)
        // The tax lines are rebuilt from the stored results: IGST for the other state, CGST and SGST at home.
        assertEquals(listOf("CGST", "IGST", "SGST"), taxComponents())

        // Numbering carries on from the last invoice issued on the iPhone.
        val next = sampleDraft(preview.file.data.businesses.first(), id = "d0000000-0000-4000-8000-0000000000ff", client = raoTraders,
            lines = listOf(LineItem(id = "da000000-0000-4000-8000-0000000000ff", description = "Next", unitPriceMinor = 10_000, rateId = "gst_18")))
        assertEquals("INV/26-27/0004", store.documentService.issue(next.id, device.id).number)
    }

    /**
     * The Android file in spec/samples is what this app exports today, so the iOS tests restore a current file.
     * `make backup-samples` (`-PbackupSamples=write`) writes it again.
     */
    @Test
    fun theAndroidSampleIsWhatThisAppExports() = runTest {
        populateSample()
        val file = store.backup.makeBackup(app)
        val sample = sample(from = "android")
        if (System.getProperty("backup.samples") == "write") sample.writeBytes(BackupCodec.encode(file))
        val committed = (BackupCodec.validate(sample.readBytes(), SpecMigrations.VERSION) as Outcome.Success).value
        assertEquals("the Android export changed: run `make backup-samples` and commit spec/samples", file, committed.file)
        assertEquals(live, committed.live)
    }
}
