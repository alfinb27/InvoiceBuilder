package app.invoicebuilder.android.backup

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.invoicebuilder.android.app.AppContainer
import app.invoicebuilder.android.app.SampleData
import app.invoicebuilder.core.data.AppDatabase
import app.invoicebuilder.core.domain.backup.DriveSyncEntry
import app.invoicebuilder.core.domain.support.IDGenerator
import app.invoicebuilder.core.domain.support.TimeSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.LocalDate

/** Settings → Sync and Welcome → "Sync with Google Drive" (`spec/drive-sync.md`) with the in-memory Drive. iOS: `DriveSyncModelTests`. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DriveSyncModelTests {
    private val context: Application = ApplicationProvider.getApplicationContext()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)

    private fun phone(drive: DemoCloudBackup) = AppContainer.make(
        context, AppDatabase.inMemory(context), TimeSource.fixed(1_789_800_000_000, LocalDate.of(2026, 9, 19)), IDGenerator.random,
        cloudBackup = drive,
    )

    private fun model(container: AppContainer, deviceID: String, onMerged: suspend (Int) -> Unit = {}) =
        DriveSyncModel(container.driveSyncEngine(deviceID)!!, container.driveSyncStore, container.autoBackupRunner(deviceID),
            container.cloudBackupState, container.time, scope, onMerged)

    private suspend fun until(condition: () -> Boolean) = withTimeout(5_000) { while (!condition()) delay(10) }

    @Test
    fun connectingSyncsAndTurnsDriveBackupOn() = runBlocking {
        val drive = DemoCloudBackup()
        val container = phone(drive)
        val device = container.deviceState.loadOrCreate("test").id
        SampleData.seed(SampleData.Country.india, container, device)
        val model = model(container, device)
        assertEquals(DriveSyncText.OFF, model.statusText)
        model.connect()
        until { !model.isWorking && model.isOn }
        assertTrue(model.statusText, model.statusText.startsWith("Up to date · synced today at "))
        assertTrue(container.cloudBackupState.cloudBackupState().isConnected)
        val files = drive.syncEntries(drive.syncFolder(null))
        assertTrue(files.any { it.kind == DriveSyncEntry.Kind.Changes && it.deviceID == device && it.seq == 1 })
        model.disconnect()
        until { !model.isWorking && !model.isOn }
    }

    @Test
    fun aNewPhoneJoiningGetsTheBusiness() = runBlocking {
        val drive = DemoCloudBackup()
        val india = phone(drive)
        val indiaDevice = india.deviceState.loadOrCreate("Pixel").id
        val business = SampleData.seed(SampleData.Country.india, india, indiaDevice)
        india.driveSyncEngine(indiaDevice)!!.connect()

        val container = phone(drive)
        val device = container.deviceState.loadOrCreate("New phone").id
        var merged = 0
        val model = model(container, device) { merged += it }
        model.connect()
        until { !model.isWorking && model.isOn }
        assertTrue(merged > 0)
        assertEquals(listOf(business.name), container.businesses.fetchBusinesses().map { it.name })
    }
}
