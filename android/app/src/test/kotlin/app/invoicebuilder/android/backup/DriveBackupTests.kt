package app.invoicebuilder.android.backup

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.invoicebuilder.android.app.AppContainer
import app.invoicebuilder.android.app.SampleData
import app.invoicebuilder.core.data.AppDatabase
import app.invoicebuilder.core.domain.backup.CloudBackupEntry
import app.invoicebuilder.core.domain.backup.CloudBackupError
import app.invoicebuilder.core.domain.support.IDGenerator
import app.invoicebuilder.core.domain.support.TimeSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.LocalDate

/** Settings → Backup → Google Drive and the restore list (`spec/backup.md` §7) with the in-memory Drive. iOS: `DriveBackupTests`. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DriveBackupTests {
    private val context: Application = ApplicationProvider.getApplicationContext()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)

    /** One "phone": its own database and device id, backing up to [drive]. */
    private fun phone(drive: DemoCloudBackup) = AppContainer.make(
        context, AppDatabase.inMemory(context), TimeSource.fixed(1_789_800_000_000, LocalDate.of(2026, 9, 19)), IDGenerator.random,
        cloudBackup = drive,
    )

    private fun model(container: AppContainer, deviceID: String) =
        DriveBackupModel(container.autoBackupRunner(deviceID)!!, container.cloudBackupState, container.time, scope)

    private suspend fun until(condition: () -> Boolean) = withTimeout(5_000) { while (!condition()) delay(10) }

    @Test
    fun connectingBacksUpAtOnceAndShowsTheAccount() = runBlocking {
        val container = phone(DemoCloudBackup())
        val device = container.deviceState.loadOrCreate("test").id
        SampleData.seed(SampleData.Country.india, container, device)
        val model = model(container, device)
        assertEquals(DriveBackupText.NOT_CONNECTED, model.statusText)
        model.connect()
        until { !model.isWorking && model.isConnected }
        assertEquals("you@example.com", model.cloud.accountEmail)
        assertTrue(model.statusText.startsWith("Last backup to Google Drive: today at "))
        // §7.5: a Drive backup counts for the 30-day nudge too.
        assertEquals(1_789_800_000_000, container.backup.observeStatus().first().lastBackupAt)
    }

    @Test
    fun aBackupFromAnotherPhoneRestoresHere() = runBlocking {
        val drive = DemoCloudBackup()
        val uk = phone(drive)
        val ukDevice = uk.deviceState.loadOrCreate("iPhone").id
        SampleData.seed(SampleData.Country.uk, uk, ukDevice)
        uk.autoBackupRunner(ukDevice)!!.connect()

        // A new phone, still on the Welcome screen.
        val container = phone(drive)
        val device = container.deviceState.loadOrCreate("Pixel").id
        val model = model(container, device)
        var reloads = 0
        val backup = BackupViewModel(container, device, scope, "test") { reloads++ }
        model.showBackups()
        until { !model.isWorking && model.backups != null }
        val entries = model.backups!!
        assertEquals(1, entries.size)
        assertTrue(DriveBackupText.detail(entries[0]).startsWith("Thames Design Ltd"))

        model.restore(entries[0], backup)
        until { backup.pendingRestore != null }
        backup.confirmRestore()
        until { reloads == 1 }
        assertEquals(listOf("Thames Design Ltd"), container.businesses.fetchBusinesses().map { it.name })
        assertTrue(model.isConnected) // automatic backups stay on for this phone (§7.6)
    }

    @Test
    fun stoppingKeepsTheFilesInDrive() = runBlocking {
        val container = phone(DemoCloudBackup())
        val device = container.deviceState.loadOrCreate("test").id
        SampleData.seed(SampleData.Country.india, container, device)
        val model = model(container, device)
        model.connect()
        until { !model.isWorking && model.isConnected }
        model.disconnect()
        until { !model.isWorking && !model.isConnected }
        model.showBackups()
        until { !model.isWorking && model.backups != null }
        assertEquals(1, model.backups!!.size)
    }

    @Test
    fun theWordsArePlain() {
        assertEquals("Couldn't back up to Google Drive: your Google Drive is full.", DriveBackupText.failed(CloudBackupError.QuotaExceeded))
        val now = 1_789_800_000_000
        val entry = CloudBackupEntry("f", "n", "d", "iPhone", "ios", now - 86_400_000, "Rao Traders", 12, 1)
        assertTrue(DriveBackupText.title(entry, now).startsWith("Yesterday at "))
        assertTrue(DriveBackupText.title(entry, now).endsWith(" · iPhone (iOS)"))
        assertEquals("Rao Traders · 12 invoices · 1 client", DriveBackupText.detail(entry))
        assertFalse(DriveBackupText.lastBackup(null, now).contains("today"))
    }
}
