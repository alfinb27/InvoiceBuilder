package app.invoicebuilder.core.data

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import app.invoicebuilder.core.domain.backup.BackupCodec
import app.invoicebuilder.core.domain.backup.BackupFile
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.documents.DocumentRules
import app.invoicebuilder.core.domain.documents.DocumentStatus
import app.invoicebuilder.core.domain.documents.LineItem
import app.invoicebuilder.core.domain.documents.PaymentMethod
import app.invoicebuilder.core.domain.models.Address
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.models.ImagePayload
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.reference.ReferenceData
import app.invoicebuilder.core.domain.repositories.DocumentServiceError
import app.invoicebuilder.core.domain.setup.BusinessSetup
import app.invoicebuilder.core.domain.support.IDGenerator
import app.invoicebuilder.core.domain.support.TimeSource
import app.invoicebuilder.core.domain.tax.TaxConfigStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.nio.file.Files
import java.time.LocalDate
import java.util.concurrent.atomic.AtomicLong
import app.invoicebuilder.core.domain.setup.DeviceMarker
import app.invoicebuilder.core.domain.setup.InMemoryDeviceMarkerStore

/** The data layer on the JVM (Robolectric's SQLite), like `swift test` for InvoiceData. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DataTests {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var store: TestStore

    class TestStore(context: Context, val db: AppDatabase = AppDatabase.inMemory(context)) {
        private val clock = AtomicLong(1_000)
        val time = TimeSource({ clock.incrementAndGet() }, { LocalDate.of(2026, 9, 19) })
        val ids = IDGenerator.sequential()
        val configs = TaxConfigStore.bundled()
        val reference = ReferenceData.bundled()
        val businesses = RoomBusinessRepository(db, time)
        val clients = RoomClientRepository(db, time)
        /** This "device"'s marker (ADR-0019). */
        val marker = InMemoryDeviceMarkerStore()
        val devices = RoomDeviceStateRepository(db, time, ids, marker)
        val setup = RoomBusinessSetupService(db, time, ids)
        val documents = RoomDocumentRepository(db, time)
        val documentService = RoomDocumentService(db, time, ids, configs, reference.currencies)
        val payments = RoomPaymentRepository(db, time)
        val paymentService = RoomPaymentService(db, time, ids)
        val snapshots = BackupSnapshotStore(Files.createTempDirectory("snapshots").toFile())
        val backup = RoomBackupService(db, time, ids, snapshots, "test")

        val business = Business(
            id = "b0000000-0000-4000-8000-000000000001", name = "Bharat Web Studio",
            address = Address(line1 = "12 MG Road", city = "Bengaluru", regionCode = "29", postalCode = "560001", countryCode = "IN"),
            countryCode = "IN", taxConfig = "IN", taxRegistration = "regular", taxId = "29AAGCB7383J1Z4",
            homeCurrency = CurrencyCode.INR, paymentTermsDays = 30, upiVpa = "bharatweb@examplebank",
        )

        suspend fun setUp(logo: ImagePayload? = null): Pair<Business, String> {
            val device = devices.loadOrCreate("Pixel")
            val config = configs.latest("IN")!!
            val series = BusinessSetup.defaultSeries(business.id, config, device.id, 0, ids.make)
            val created = setup.createBusiness(business, series, logo, null, device.id)
            clients.save(Client(id = "c1", businessId = created.id, name = "Rao Traders",
                billingAddress = Address(line1 = "5 Residency Road", city = "Bengaluru", regionCode = "29", countryCode = "IN"),
                countryCode = "IN", regionCode = "29", taxId = "29AABCR1234C1ZU", isBusiness = true))
            return created to device.id
        }

        suspend fun draft(business: Business, id: String, docType: DocumentType = DocumentType.invoice, vararg lines: LineItem) {
            val rules = DocumentRules(configs, business, reference.currencies)
            val client = clients.fetchClient("c1")
            val document = rules.newDocument(docType, id, time.today(), client, 0).copy(lines = lines.toList())
            documents.saveDraft(rules.preparedDraft(document, client))
        }

        fun line(id: String, price: Long, rate: String = "gst_18") =
            LineItem(id = id, description = "Work $id", productCode = "998314", quantity = "1", unitPriceMinor = price, rateId = rate)
    }

    @Before fun setUp() { store = TestStore(context) }
    @After fun tearDown() { store.db.close() }

    @Test
    fun theSpecMigrationsBuildWhatRoomExpectsAndMatchSchemaSql() {
        // Opening the database already ran Room's own check of every entity against the tables the SQL created.
        val sql = store.db.openHelper.writableDatabase
        val canonical = SQLiteDatabase.create(null)
        val schema = File(System.getProperty("spec.root"), "schema/db/schema.sql").readText()
        for (statement in SpecMigrations.statements(schema)) canonical.execSQL(statement)
        fun describe(query: (String) -> android.database.Cursor): Map<String, String> {
            val tables = mutableListOf<String>()
            query("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT IN ('room_master_table', 'android_metadata') ORDER BY name").use { c ->
                while (c.moveToNext()) tables += c.getString(0)
            }
            return tables.associateWith { table ->
                listOf("table_info", "foreign_key_list", "index_list").joinToString("\n") { pragma ->
                    query("PRAGMA $pragma($table)").use { c ->
                        buildList { while (c.moveToNext()) add((0 until c.columnCount).joinToString("|") { c.getString(it) ?: "∅" }) }.sorted().joinToString(";")
                    }
                }
            }
        }
        val migrated = describe { sql.query(it) }
        val expected = describe { canonical.rawQuery(it, null) }
        assertEquals(expected.keys, migrated.keys)
        for (table in expected.keys) assertEquals("table $table", expected[table], migrated[table])
        val files = File(System.getProperty("spec.root"), "schema/db/migrations").list()!!.filter { it.endsWith(".sql") }.sorted()
        assertEquals(files, SpecMigrations.files)
        assertEquals(files.size, SpecMigrations.VERSION)
    }

    @Test
    fun issuingNumbersFreezesAndCounts() = runTest {
        val (business, device) = store.setUp()
        store.draft(business, "d1", DocumentType.invoice, store.line("l1", 1_000_000))
        val issued = store.documentService.issue("d1", device)
        assertEquals("INV/26-27/0001", issued.number)
        assertEquals(1_180_000L, issued.totals.totalMinor)
        assertNotNull(issued.computed)
        store.draft(business, "d2", DocumentType.invoice, store.line("l2", 500))
        assertEquals("INV/26-27/0002", store.documentService.issue("d2", device).number)
        assertEquals(2, RoomFreeTierRepository(store.db).fetchCounts().local)
        try {
            store.documentService.issue("d1", device)
            fail("issued twice")
        } catch (expected: DocumentServiceError.NotADraft) {}
    }

    @Test
    fun paymentsDriveTheStatusAndTheDashboard() = runTest {
        val (business, device) = store.setUp()
        store.draft(business, "d1", DocumentType.invoice, store.line("l1", 1_000_000))
        val issued = store.documentService.issue("d1", device)
        store.paymentService.recordPayment(issued.id, 500_000, store.time.today(), PaymentMethod.upi, " REF ", null)
        val paid = store.payments.fetchPayments(issued.id).sumOf { it.amountMinor }
        assertEquals(DocumentStatus.partiallyPaid, issued.status(store.time.today(), paid))
        val dashboard = store.documents.observeDashboard(business.id, CurrencyCode.INR).first()
        assertEquals(680_000L, dashboard.outstandingMinor)
        assertEquals(500_000L, dashboard.paidThisMonthMinor)
        val summaries = store.documents.observeDocuments(business.id).first()
        assertEquals(500_000L, summaries.single().paidMinor)
    }

    @Test
    fun aBackupRoundTripIsLossless() = runTest {
        val (business, device) = store.setUp(ImagePayload(ImagePayload.PNG, byteArrayOf(1, 2, 3)))
        store.draft(business, "d1", DocumentType.invoice, store.line("l1", 1_000_000))
        store.documentService.issue("d1", device)
        store.paymentService.recordPayment("d1", 100, store.time.today(), PaymentMethod.cash, null, null)
        store.draft(business, "q1", DocumentType.quote, store.line("l2", 2_000))
        store.documentService.issue("q1", device)
        store.documentService.convertQuote("q1")
        store.clients.delete("c1")
        val file = store.backup.makeBackup(BackupFile.AppInfo("android", "test"))
        val bytes = BackupCodec.encode(file)
        val preview = (BackupCodec.validate(bytes, SpecMigrations.VERSION) as Outcome.Success).value

        val target = TestStore(context)
        try {
            target.db.openHelper.writableDatabase.execSQL(
                "INSERT INTO device_state (id, device_name, free_counter_mirror, preferences, created_at, updated_at) VALUES (?, 'Pixel', 0, '{}', 0, 0)",
                arrayOf(device),
            )
            target.backup.restore(preview.file, device)
            val again = target.backup.makeBackup(BackupFile.AppInfo("android", "test"))
            assertEquals(file.data, again.data)
        } finally {
            target.db.close()
        }
    }

    @Test
    fun theIosSampleBackupRestores() = runTest {
        val bytes = File(System.getProperty("spec.root"), "samples/backup-v1-sample.invoicebackup.json").readBytes()
        val preview = (BackupCodec.validate(bytes, SpecMigrations.VERSION) as Outcome.Success).value
        val device = store.devices.loadOrCreate("Pixel")
        store.backup.restore(preview.file, device.id)
        val exported = store.backup.makeBackup(BackupFile.AppInfo("android", "test")).data
        assertEquals(preview.file.data.sorted().documents, exported.documents)
        assertTrue(exported.numberingSeries.all { it.ownerDeviceId == device.id })
        assertEquals(1, store.snapshots.snapshots().size)
    }

    @Test
    fun aFailedRestoreChangesNothing() = runTest {
        val (business, device) = store.setUp()
        store.draft(business, "d1", DocumentType.invoice, store.line("l1", 1_000_000))
        store.documentService.issue("d1", device)
        store.paymentService.recordPayment("d1", 100, store.time.today(), PaymentMethod.cash, null, null)
        val before = store.backup.makeBackup(BackupFile.AppInfo("android", "test"))
        val broken = before.copy(data = before.data.copy(payments = before.data.payments.map { it.copy(amountMinor = 0) }))
        try {
            store.backup.restore(broken, device)
            fail("restored a payment of 0")
        } catch (expected: Exception) {}
        assertEquals(before.data, store.backup.makeBackup(BackupFile.AppInfo("android", "test")).data)
    }

    /** ADR-0019: a database restored onto a new phone by Auto Backup arrives without that phone's marker. */
    @Test
    fun aDatabaseCopiedToAnotherDeviceTakesANewID() = runTest {
        val original = store.devices.loadOrCreate("Old Pixel")
        assertEquals(DeviceMarker.Found(original.id), store.marker.read())
        store.devices.setActiveBusiness("b1")

        store.marker.set(DeviceMarker.Missing) // the new phone's noBackupFilesDir is empty
        val copied = store.devices.loadOrCreate("New Pixel")
        assertNotEquals(original.id, copied.id)
        assertEquals("b1", copied.preferences.activeBusinessId) // everything else stays
        assertEquals(original.deviceName, copied.deviceName)
        assertEquals(DeviceMarker.Found(copied.id), store.marker.read())
        assertEquals(copied.id, store.devices.loadOrCreate("New Pixel").id) // stable from now on

        store.marker.set(DeviceMarker.Unreadable) // an I/O error never changes the id
        assertEquals(copied.id, store.devices.loadOrCreate("New Pixel").id)
    }

    @Test
    fun theMarkerFileSurvivesAndReportsWhatIsThere() {
        val directory = Files.createTempDirectory("no-backup").toFile()
        val marker = FileDeviceMarkerStore(directory)
        assertEquals(DeviceMarker.Missing, marker.read())
        marker.write("d1")
        assertEquals(DeviceMarker.Found("d1"), FileDeviceMarkerStore(directory).read())
        marker.write("d2")
        assertEquals(DeviceMarker.Found("d2"), marker.read())
        java.io.File(directory, "device-id").writeText("")
        assertEquals(DeviceMarker.Missing, marker.read()) // a write cut short
    }
}
