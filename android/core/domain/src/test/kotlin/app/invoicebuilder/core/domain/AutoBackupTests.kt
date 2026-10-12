package app.invoicebuilder.core.domain

import app.invoicebuilder.core.domain.backup.AutoBackupRules
import app.invoicebuilder.core.domain.backup.AutoBackupRunner
import app.invoicebuilder.core.domain.backup.BackupData
import app.invoicebuilder.core.domain.backup.BackupFile
import app.invoicebuilder.core.domain.backup.BackupStatus
import app.invoicebuilder.core.domain.backup.CloudBackupDestination
import app.invoicebuilder.core.domain.backup.CloudBackupEntry
import app.invoicebuilder.core.domain.backup.CloudBackupError
import app.invoicebuilder.core.domain.backup.CloudBackupException
import app.invoicebuilder.core.domain.backup.CloudBackupState
import app.invoicebuilder.core.domain.backup.CloudBackupStateStore
import app.invoicebuilder.core.domain.backup.CloudBackupTarget
import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.documents.DocumentRules
import app.invoicebuilder.core.domain.models.Address
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.repositories.BackupService
import app.invoicebuilder.core.domain.support.TimeSource
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.time.LocalDate

/** [AutoBackupRunner] against an in-memory cloud (`spec/backup.md` §7). The pure rules run as fixtures. iOS: `AutoBackupTests`. */
class AutoBackupTests {
    companion object {
        const val DAY = 86_400_000L
        const val START = 1_791_600_000_000L
    }

    class Clock {
        var now = START
        var today: LocalDate = LocalDate.parse("2026-10-10")
        val time = TimeSource({ now }, { today })
    }

    private fun runner(clock: Clock, cloud: FakeCloud = FakeCloud(), state: FakeState = FakeState(), deviceID: String = "dev-me") =
        Triple(AutoBackupRunner(cloud, FakeBackups(clock.time), state, clock.time,
            AutoBackupRunner.Device(deviceID, "Pixel 8", BackupFile.AppInfo("android", "1.0"))), cloud, state)

    @Test
    fun connectingSignsInAndBacksUpAtOnce() = runBlocking {
        val clock = Clock()
        val (runner, cloud, state) = runner(clock)
        runner.connect()
        val saved = state.cloudBackupState()
        assertEquals("owner@example.com", saved.accountEmail)
        assertEquals(clock.now, saved.lastBackupAt)
        val file = cloud.files.values.single()
        assertEquals("InvoiceBackup-2026-10-10.invoicebackup", file.name)
        assertEquals("dev-me", file.properties["ibDeviceId"])
        assertEquals("android", file.properties["ibPlatform"])
        assertEquals("Bharat Web Studio", file.properties["ibBusinesses"])
        assertEquals("1", file.properties["ibInvoices"])
    }

    @Test
    fun aNewPhoneConnectingToRestoreWritesNoEmptyBackup() = runBlocking {
        val clock = Clock()
        val state = FakeState().apply { latest = null }
        val (runner, cloud, _) = runner(clock, state = state)
        runner.connect()
        assertTrue(state.cloudBackupState().isConnected)
        assertTrue(cloud.files.isEmpty())
    }

    @Test
    fun aSecondBackupTheSameDayReplacesTodaysFile() = runBlocking {
        val clock = Clock()
        val (runner, cloud, _) = runner(clock)
        runner.connect()
        clock.now += 60_000
        runner.backUpNow()
        assertEquals(1, cloud.files.size)
        assertEquals(1, cloud.updates)
    }

    @Test
    fun anotherDevicesFileIsNeverOverwritten() = runBlocking {
        val clock = Clock()
        val cloud = FakeCloud()
        runner(clock, cloud, deviceID = "dev-other").first.connect()
        runner(clock, cloud, deviceID = "dev-me").first.connect()
        assertEquals(setOf("dev-other", "dev-me"), cloud.files.values.map { it.properties["ibDeviceId"] }.toSet())
    }

    @Test
    fun onlyTheTenNewestOfThisDeviceStay() = runBlocking {
        val clock = Clock()
        val (runner, cloud, _) = runner(clock)
        runner.connect()
        repeat(12) {
            clock.now += DAY
            clock.today = clock.today.plusDays(1)
            runner.backUpNow()
        }
        val names = cloud.files.values.map { it.name }.sorted()
        assertEquals(AutoBackupRules.KEEP, names.size)
        assertEquals("InvoiceBackup-2026-10-13.invoicebackup", names.first())
        assertEquals("InvoiceBackup-2026-10-22.invoicebackup", names.last())
    }

    @Test
    fun automaticBackupsFollowTheRule() = runBlocking {
        val clock = Clock()
        val state = FakeState()
        val (runner, cloud, _) = runner(clock, state = state)
        runner.connect()
        state.latest = clock.now - 1
        assertFalse(runner.backUpIfDue()) // nothing changed since the backup
        clock.now += 60_000
        state.latest = clock.now
        assertFalse(runner.backUpIfDue()) // an attempt a minute ago
        clock.now += AutoBackupRules.MINIMUM_INTERVAL
        assertTrue(runner.backUpIfDue())
        assertEquals(1, cloud.updates)
    }

    @Test
    fun aFailureIsRecordedAndSignedOutStopsAutomaticAttempts() = runBlocking {
        val clock = Clock()
        val cloud = FakeCloud()
        val state = FakeState()
        val (runner, _, _) = runner(clock, cloud, state)
        runner.connect()
        cloud.failure = CloudBackupError.QuotaExceeded
        clock.now += DAY
        val quota = assertThrows<CloudBackupException> { runBlocking { runner.backUpNow() } }
        assertEquals(CloudBackupError.QuotaExceeded, quota.error)
        assertEquals(CloudBackupError.QuotaExceeded, state.cloudBackupState().lastError)

        cloud.failure = CloudBackupError.SignedOut
        clock.now += DAY
        state.latest = clock.now
        assertThrows<CloudBackupException> { runBlocking { runner.backUpNow() } }
        clock.now += DAY
        state.latest = clock.now
        assertFalse(runner.backUpIfDue()) // waits for the user to reconnect
    }

    @Test
    fun aTrashedFolderIsFoundOrCreatedAgain() = runBlocking {
        val clock = Clock()
        val (runner, cloud, state) = runner(clock)
        runner.connect()
        val first = state.cloudBackupState().folderID!!
        cloud.folders.remove(first)
        clock.now += 60_000
        runner.backUpNow()
        assertNotEquals(first, state.cloudBackupState().folderID)
    }

    @Test
    fun theRestoreListIsNewestFirstAndDownloads() = runBlocking {
        val clock = Clock()
        val (runner, _, _) = runner(clock)
        runner.connect()
        clock.now += DAY
        clock.today = clock.today.plusDays(1)
        runner.backUpNow()
        val list = runner.list()
        assertEquals(listOf("InvoiceBackup-2026-10-11.invoicebackup", "InvoiceBackup-2026-10-10.invoicebackup"), list.map { it.name })
        assertEquals(1, list.first().invoiceCount)
        val file = app.invoicebuilder.core.domain.support.SpecJson.decodeFromString(
            BackupFile.serializer(), runner.download(list.first()).toString(Charsets.UTF_8))
        assertEquals(listOf("Bharat Web Studio"), file.data.businesses.map { it.name })
    }

    @Test
    fun disconnectingForgetsTheAccountAndKeepsTheFiles() = runBlocking {
        val clock = Clock()
        val (runner, cloud, state) = runner(clock)
        runner.connect()
        runner.disconnect()
        assertEquals(CloudBackupState(), state.cloudBackupState())
        assertEquals(1, cloud.files.size)
        assertFalse(cloud.connected)
    }

    @Test
    fun longPropertiesAreCutToDrivesLimit() {
        val cut = AutoBackupRules.fit("Ä".repeat(100), "ibBusinesses")
        assertTrue(cut.endsWith("…"))
        assertTrue("ibBusinesses".toByteArray().size + cut.toByteArray().size <= 124)
        assertEquals("Rao Traders", AutoBackupRules.fit("Rao Traders", "ibBusinesses"))
    }

    // Fakes

    class FakeCloud : CloudBackupDestination {
        data class File(val name: String, val properties: Map<String, String>, val data: ByteArray, val folder: String)

        val files = linkedMapOf<String, File>()
        val folders = mutableListOf<String>()
        var updates = 0
        var connected = false
        var failure: CloudBackupError? = null
        private var next = 0

        override suspend fun connect(): String { connected = true; return "owner@example.com" }
        override suspend fun disconnect() { connected = false }
        override suspend fun folder(knownID: String?): String {
            if (knownID != null && knownID in folders) return knownID
            folders.firstOrNull()?.let { return it }
            return id("folder").also { folders += it }
        }
        override suspend fun list(folderID: String) =
            files.filter { it.value.folder == folderID }.map { CloudBackupEntry.of(it.key, it.value.name, it.value.properties) }
        override suspend fun upload(data: ByteArray, name: String, properties: Map<String, String>, target: CloudBackupTarget, folderID: String): String {
            failure?.let { throw CloudBackupException(it) }
            val id = when (target) {
                CloudBackupTarget.Create -> id("file")
                is CloudBackupTarget.Update -> target.id.also { updates++ }
            }
            files[id] = File(name, properties, data, folderID)
            return id
        }
        override suspend fun download(id: String) = files[id]?.data ?: throw CloudBackupException(CloudBackupError.Other)
        override suspend fun delete(id: String) { files.remove(id) }
        private fun id(prefix: String) = "$prefix-${"%03d".format(++next)}"
    }

    class FakeState : CloudBackupStateStore {
        var state = CloudBackupState()
        var latest: Long? = START - 1
        override suspend fun cloudBackupState() = state
        override suspend fun saveCloudBackupState(state: CloudBackupState) { this.state = state }
        override fun observeCloudBackupState(): Flow<CloudBackupState> = emptyFlow()
        override suspend fun latestChangeAt() = latest
    }

    /** One business with one issued invoice; `createdAt` is the clock's now. */
    class FakeBackups(private val time: TimeSource) : BackupService {
        override val schemaVersion = 4
        private val business = Business(
            id = "b-in", name = "Bharat Web Studio", address = Address(line1 = "12 MG Road", city = "Bengaluru", regionCode = "29",
                postalCode = "560001", countryCode = "IN"),
            countryCode = "IN", taxConfig = "IN", taxRegistration = "regular", taxId = "29AAGCB7383J1Z4", homeCurrency = CurrencyCode.INR,
        )
        override suspend fun makeBackup(app: BackupFile.AppInfo): BackupFile {
            val invoice = DocumentRules(FixtureTests.configs, business, FixtureTests.currencies)
                .newDocument(DocumentType.invoice, "d1", time.today(), now = 1).copy(lifecycle = DocumentLifecycle.issued)
            return BackupFile.of(time.now(), app, 4, BackupData(businesses = listOf(business), documents = listOf(invoice)))
        }
        override suspend fun writeSafetySnapshot() {}
        override suspend fun restore(file: BackupFile, deviceID: String) {}
        override suspend fun recordBackup(timestamp: Long) {}
        override fun observeStatus(): Flow<BackupStatus> = emptyFlow()
    }
}
