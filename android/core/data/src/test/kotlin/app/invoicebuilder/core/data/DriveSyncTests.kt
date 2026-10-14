package app.invoicebuilder.core.data

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.invoicebuilder.core.domain.backup.CloudBackupEntry
import app.invoicebuilder.core.domain.backup.CloudBackupError
import app.invoicebuilder.core.domain.backup.CloudBackupException
import app.invoicebuilder.core.domain.backup.CloudBackupTarget
import app.invoicebuilder.core.domain.backup.DriveSync
import app.invoicebuilder.core.domain.backup.DriveSyncDestination
import app.invoicebuilder.core.domain.backup.DriveSyncEngine
import app.invoicebuilder.core.domain.backup.DriveSyncEntry
import app.invoicebuilder.core.domain.backup.DriveSyncState
import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.models.DocumentType
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** An in-memory Drive sync folder shared by several test "devices". */
class FakeSyncDrive : DriveSyncDestination {
    data class File(val name: String, val properties: Map<String, String>, val data: ByteArray)

    val files = linkedMapOf<String, File>()
    private var next = 0

    override suspend fun connect() = "owner@example.com"
    override suspend fun disconnect() {}
    override suspend fun folder(knownID: String?) = "backup-folder"
    override suspend fun list(folderID: String) = emptyList<CloudBackupEntry>()
    override suspend fun syncFolder(knownID: String?) = "sync-folder"
    override suspend fun syncEntries(folderID: String) = files.map { (id, file) -> DriveSyncEntry.of(id, file.properties) }
    override suspend fun upload(data: ByteArray, name: String, properties: Map<String, String>, target: CloudBackupTarget, folderID: String): String {
        val id = when (target) {
            CloudBackupTarget.Create -> "file-${++next}"
            is CloudBackupTarget.Update -> target.id
        }
        files[id] = File(name, properties, data)
        return id
    }
    override suspend fun download(id: String) = files[id]?.data ?: throw CloudBackupException(CloudBackupError.Other)
    override suspend fun delete(id: String) { files.remove(id) }
}

/** Drive sync between Room databases through an in-memory Drive (`spec/drive-sync.md`). iOS: `DriveSyncTests`. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DriveSyncTests {
    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun DataTests.TestStore.engine(drive: FakeSyncDrive, deviceID: String) = DriveSyncEngine(drive, backup, time, deviceID)

    private suspend fun DataTests.TestStore.populated(): String {
        val (business, device) = setUp()
        draft(business, "d1", DocumentType.invoice, line("l1", 1_000_000), line("l2", 120_000))
        documentService.issue("d1", device)
        draft(business, "d2", DocumentType.invoice, line("l3", 5_000))
        return device
    }

    @Test
    fun aSecondDeviceReceivesEverything() = runTest {
        val drive = FakeSyncDrive()
        val a = DataTests.TestStore(context)
        val b = DataTests.TestStore(context)
        a.populated()
        a.engine(drive, "dev-a").connect()
        b.engine(drive, "dev-b").connect()

        val fromA = a.backup.allRecords()
        val onB = b.backup.allRecords()
        assertEquals(fromA.businesses, onB.businesses)
        assertEquals(fromA.clients, onB.clients)
        assertEquals(fromA.documents, onB.documents)
        assertEquals(fromA.numberingSeries, onB.numberingSeries)
        assertEquals(0, a.engine(drive, "dev-a").syncNow())
        assertEquals(mapOf("dev-b" to 1), a.backup.driveSyncState().seen)
    }

    @Test
    fun anEditTravelsBothWays() = runTest {
        val drive = FakeSyncDrive()
        val a = DataTests.TestStore(context)
        val b = DataTests.TestStore(context)
        a.populated()
        val engineA = a.engine(drive, "dev-a")
        val engineB = b.engine(drive, "dev-b")
        engineA.connect()
        engineB.connect()
        b.db.openHelper.writableDatabase.execSQL("UPDATE client SET name = 'Renamed on B', updated_at = 1000000 WHERE id = 'c1'")
        engineB.syncNow()
        assertEquals(1, engineA.syncNow())
        assertEquals("Renamed on B", a.backup.allRecords().clients.first { it.id == "c1" }.name)
    }

    @Test
    fun anIssueBeatsALaterDraftEditOnBothDevices() = runTest {
        val drive = FakeSyncDrive()
        val a = DataTests.TestStore(context)
        val b = DataTests.TestStore(context)
        val (business, device) = a.setUp()
        a.draft(business, "d1", DocumentType.invoice, a.line("l1", 100_000))
        val engineA = a.engine(drive, "dev-a")
        val engineB = b.engine(drive, "dev-b")
        engineA.connect()
        engineB.connect()
        a.documentService.issue("d1", device)
        b.db.openHelper.writableDatabase.execSQL("UPDATE document SET notes = 'edited on B', updated_at = 9000000 WHERE id = 'd1'")
        engineB.syncNow()
        engineA.syncNow()
        engineB.syncNow()
        for (store in listOf(a, b)) {
            val document = store.backup.allRecords().documents.first { it.id == "d1" }
            assertEquals(DocumentLifecycle.issued, document.lifecycle)
            assertNotNull(document.number)
        }
    }

    @Test
    fun aNewDeviceCatchesUpFromASnapshot() = runTest {
        val drive = FakeSyncDrive()
        val a = DataTests.TestStore(context)
        a.populated()
        val engineA = a.engine(drive, "dev-a")
        engineA.connect()
        for (index in 1..DriveSync.SNAPSHOT_AFTER) {
            a.db.openHelper.writableDatabase.execSQL("UPDATE client SET name = ?, updated_at = ? WHERE id = 'c1'",
                arrayOf<Any>("Name $index", 2_000_000 + index))
            engineA.syncNow()
        }
        assertEquals(DriveSync.SNAPSHOT_AFTER + 1, a.backup.driveSyncState().snapshotCovers)
        drive.files.entries.removeAll { it.value.properties[DriveSyncEntry.KEY_KIND] != "snapshot" }
        val c = DataTests.TestStore(context)
        c.engine(drive, "dev-c").connect()
        assertEquals("Name ${DriveSync.SNAPSHOT_AFTER}", c.backup.allRecords().clients.first { it.id == "c1" }.name)
        assertEquals(DriveSync.SNAPSHOT_AFTER + 1, c.backup.driveSyncState().seen["dev-a"])
    }

    @Test
    fun syncStateRoundTripsThroughAppState() = runTest {
        val store = DataTests.TestStore(context)
        val state = DriveSyncState("o@example.com", "f", 42, 7, mapOf("dev-b" to 3), "s", 5, 9, CloudBackupError.QuotaExceeded)
        store.backup.saveDriveSyncState(state)
        assertEquals(state, store.backup.driveSyncState())
        store.backup.saveDriveSyncState(DriveSyncState())
        assertEquals(DriveSyncState(), store.backup.driveSyncState())
    }
}
