package app.invoicebuilder.core.domain.backup

import app.invoicebuilder.core.domain.support.SpecJson
import app.invoicebuilder.core.domain.support.TimeSource
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** A change file (`spec/drive-sync.md` §3): one push's records, written once by one device. iOS: `DriveSyncChanges`. */
@Serializable
data class DriveSyncChanges(
    val formatVersion: Int = FORMAT_VERSION,
    val deviceId: String,
    val seq: Int,
    val createdAt: Long,
    val data: BackupData,
) {
    companion object {
        const val FORMAT_VERSION = 1
        fun fileName(deviceID: String, seq: Int) = "changes-$deviceID-${seq.toString().padStart(8, '0')}.json"
    }
}

/** A device's snapshot (§8): all records, plus the change files they include. iOS: `DriveSyncSnapshot`. */
@Serializable
data class DriveSyncSnapshot(
    val formatVersion: Int = DriveSyncChanges.FORMAT_VERSION,
    val deviceId: String,
    val createdAt: Long,
    /** The highest `seq` per device this snapshot includes (this device's own among them). */
    val covers: Map<String, Int>,
    val data: BackupData,
) {
    companion object {
        fun fileName(deviceID: String) = "snapshot-$deviceID.json"
    }
}

/** The Drive sync state in `app_state` (`spec/drive-sync.md` §4, §6, §9). iOS: `DriveSyncState`. */
data class DriveSyncState(
    val accountEmail: String? = null,
    val folderID: String? = null,
    /** §4: records with `updatedAt` at or after this are pushed next (epoch ms; 0 = everything). */
    val pushedAt: Long = 0,
    val nextSeq: Int = 1,
    /** §6: the highest `seq` merged per other device. */
    val seen: Map<String, Int> = emptyMap(),
    val snapshotID: String? = null,
    val snapshotCovers: Int? = null,
    val lastSyncAt: Long? = null,
    val lastError: CloudBackupError? = null,
) {
    val isConnected: Boolean get() = accountEmail != null

    /** The `app_state` rows (null = delete the row). */
    val rows: Map<String, String?>
        get() = mapOf(
            ACCOUNT to accountEmail, FOLDER to folderID, PUSHED_AT to pushedAt.toString(), NEXT_SEQ to nextSeq.toString(),
            SEEN to if (seen.isEmpty()) null else Json.encodeToString(seenSerializer, seen.toSortedMap()),
            SNAPSHOT_ID to snapshotID, SNAPSHOT_COVERS to snapshotCovers?.toString(),
            LAST_SYNC to lastSyncAt?.toString(), LAST_ERROR to lastError?.rawValue,
        )

    companion object {
        const val ACCOUNT = "drive_sync_account_email"
        const val FOLDER = "drive_sync_folder_id"
        const val PUSHED_AT = "drive_sync_pushed_at"
        const val NEXT_SEQ = "drive_sync_next_seq"
        const val SEEN = "drive_sync_seen"
        const val SNAPSHOT_ID = "drive_sync_snapshot_id"
        const val SNAPSHOT_COVERS = "drive_sync_snapshot_covers"
        const val LAST_SYNC = "drive_sync_last_sync_at"
        const val LAST_ERROR = "drive_sync_last_error"
        val ROW_KEYS = listOf(ACCOUNT, FOLDER, PUSHED_AT, NEXT_SEQ, SEEN, SNAPSHOT_ID, SNAPSHOT_COVERS, LAST_SYNC, LAST_ERROR)
        private val seenSerializer = MapSerializer(String.serializer(), Int.serializer())

        fun fromRows(rows: Map<String, String>) = DriveSyncState(
            accountEmail = rows[ACCOUNT], folderID = rows[FOLDER], pushedAt = rows[PUSHED_AT]?.toLongOrNull() ?: 0,
            nextSeq = rows[NEXT_SEQ]?.toIntOrNull() ?: 1,
            seen = rows[SEEN]?.let { text -> runCatching { Json.decodeFromString(seenSerializer, text) }.getOrNull() } ?: emptyMap(),
            snapshotID = rows[SNAPSHOT_ID], snapshotCovers = rows[SNAPSHOT_COVERS]?.toIntOrNull(),
            lastSyncAt = rows[LAST_SYNC]?.toLongOrNull(), lastError = CloudBackupError.of(rows[LAST_ERROR]),
        )
    }
}

/** The sync folder in the user's Drive (`spec/drive-sync.md` §3), beside the backup calls. iOS: `DriveSyncDestination`. */
interface DriveSyncDestination : CloudBackupDestination {
    /** "InvoiceBuilder sync": [knownID] when it is still there, otherwise found or created. */
    suspend fun syncFolder(knownID: String?): String
    suspend fun syncEntries(folderID: String): List<DriveSyncEntry>
}

/** The database side of Drive sync (`RoomBackupService` implements it). iOS: `DriveSyncStore`. */
interface DriveSyncStore {
    suspend fun driveSyncState(): DriveSyncState
    suspend fun saveDriveSyncState(state: DriveSyncState)
    fun observeDriveSyncState(): Flow<DriveSyncState>
    /** §4: every record with `updatedAt >= since`, tombstones included (a document with its live lines). */
    suspend fun changes(since: Long): BackupData
    /** Every record, for a snapshot. */
    suspend fun allRecords(): BackupData
    /** §5: merges [data] record by record in one transaction and saves [state] in it. Returns how many records changed. */
    suspend fun merge(data: BackupData, state: DriveSyncState): Int
}

/** Runs live sync through Google Drive (`spec/drive-sync.md`): connect, pull, push, compaction. iOS: `DriveSyncEngine`. */
class DriveSyncEngine(
    private val destination: DriveSyncDestination,
    private val store: DriveSyncStore,
    private val time: TimeSource,
    private val deviceID: String,
) {
    private val running = Mutex()
    private val json = Json(from = SpecJson) { prettyPrint = false }

    /** §7: sign in, find or create the folder, then a full sync from scratch (`seen = {}`, everything pushed). */
    suspend fun connect() {
        val email = destination.connect()
        val folder = destination.syncFolder(null)
        store.saveDriveSyncState(DriveSyncState(accountEmail = email, folderID = folder))
        syncNow()
    }

    /** §7: turn sync off and forget the state; the files stay. */
    suspend fun disconnect() = store.saveDriveSyncState(DriveSyncState())

    /** Pull, then push (§4, §6). Returns how many records the pull changed (the app then runs `sync.md` §5). */
    suspend fun syncNow(): Int = running.withLock { perform() }

    private suspend fun perform(): Int {
        var state = store.driveSyncState()
        if (!state.isConnected) throw CloudBackupException(CloudBackupError.SignedOut)
        try {
            val folder = destination.syncFolder(state.folderID)
            if (folder != state.folderID) {
                // A new folder (the old one was trashed): start over in it.
                state = DriveSyncState(accountEmail = state.accountEmail, folderID = folder)
                store.saveDriveSyncState(state)
            }
            val changed = pull(folder)
            push(folder)
            store.saveDriveSyncState(store.driveSyncState().copy(lastSyncAt = time.now(), lastError = null))
            return changed
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            val reason = (error as? CloudBackupException)?.error ?: CloudBackupError.Other
            runCatching { store.saveDriveSyncState(store.driveSyncState().copy(lastError = reason)) }
            throw CloudBackupException(reason)
        }
    }

    // §6 pull

    private suspend fun pull(folder: String): Int {
        var changed = 0
        // A snapshot read changes `seen`, so list again until only change files (or nothing) remain.
        repeat(16) {
            val entries = destination.syncEntries(folder)
            var state = store.driveSyncState()
            val ids = DriveSync.toRead(entries, state.seen, deviceID)
            if (ids.isEmpty()) return changed
            val byID = entries.associateBy { it.id }
            var readSnapshot = false
            for (id in ids) {
                val text = destination.download(id).toString(Charsets.UTF_8)
                checkFormat(text)
                if (byID[id]?.kind == DriveSyncEntry.Kind.Snapshot) {
                    val snapshot = decode { json.decodeFromString(DriveSyncSnapshot.serializer(), text) }
                    val seen = state.seen.toMutableMap()
                    for ((device, seq) in snapshot.covers) if (device != deviceID) seen[device] = maxOf(seen[device] ?: 0, seq)
                    state = state.copy(seen = seen)
                    changed += store.merge(snapshot.data, state)
                    readSnapshot = true
                } else {
                    val file = decode { json.decodeFromString(DriveSyncChanges.serializer(), text) }
                    state = state.copy(seen = state.seen + (file.deviceId to maxOf(state.seen[file.deviceId] ?: 0, file.seq)))
                    changed += store.merge(file.data, state)
                }
            }
            if (!readSnapshot) return changed
        }
        return changed
    }

    /** §9: a newer format stops the pull at that file. */
    private fun checkFormat(text: String) {
        val version = runCatching { Json.parseToJsonElement(text).jsonObject["formatVersion"]?.jsonPrimitive?.int }.getOrNull()
        if (version != null && version > DriveSyncChanges.FORMAT_VERSION) throw CloudBackupException(CloudBackupError.Other)
    }

    private inline fun <T> decode(block: () -> T): T =
        try { block() } catch (_: Exception) { throw CloudBackupException(CloudBackupError.Other) }

    // §4 push

    private suspend fun push(folder: String) {
        val state = store.driveSyncState()
        val start = time.now()
        val data = store.changes(state.pushedAt)
        if (data.counts == BackupData().counts) return
        val seq = state.nextSeq
        val file = DriveSyncChanges(deviceId = deviceID, seq = seq, createdAt = start, data = data)
        destination.upload(
            json.encodeToString(DriveSyncChanges.serializer(), file).toByteArray(Charsets.UTF_8),
            DriveSyncChanges.fileName(deviceID, seq),
            mapOf(
                DriveSyncEntry.KEY_KIND to DriveSyncEntry.Kind.Changes.rawValue, DriveSyncEntry.KEY_DEVICE_ID to deviceID,
                DriveSyncEntry.KEY_SEQ to seq.toString(), DriveSyncEntry.KEY_CREATED_AT to start.toString(),
            ),
            CloudBackupTarget.Create, folder,
        )
        store.saveDriveSyncState(state.copy(pushedAt = start, nextSeq = seq + 1))
        runCatching { compact(folder) }
    }

    // §8 compaction

    private suspend fun compact(folder: String) {
        var state = store.driveSyncState()
        val entries = destination.syncEntries(folder)
        val own = entries.filter { it.kind == DriveSyncEntry.Kind.Changes && it.deviceID == deviceID }
        if (own.size > DriveSync.SNAPSHOT_AFTER) {
            val covered = state.nextSeq - 1
            val snapshot = DriveSyncSnapshot(deviceId = deviceID, createdAt = time.now(),
                covers = state.seen + (deviceID to covered), data = store.allRecords())
            val existing = entries.firstOrNull { it.kind == DriveSyncEntry.Kind.Snapshot && it.deviceID == deviceID }?.id ?: state.snapshotID
            val id = destination.upload(
                json.encodeToString(DriveSyncSnapshot.serializer(), snapshot).toByteArray(Charsets.UTF_8),
                DriveSyncSnapshot.fileName(deviceID),
                mapOf(
                    DriveSyncEntry.KEY_KIND to DriveSyncEntry.Kind.Snapshot.rawValue, DriveSyncEntry.KEY_DEVICE_ID to deviceID,
                    DriveSyncEntry.KEY_CREATED_AT to snapshot.createdAt.toString(),
                ),
                existing?.let { CloudBackupTarget.Update(it) } ?: CloudBackupTarget.Create, folder,
            )
            state = state.copy(snapshotID = id, snapshotCovers = covered)
            store.saveDriveSyncState(state)
        }
        for (id in DriveSync.filesToDelete(entries, deviceID, state.snapshotCovers, time.now())) {
            runCatching { destination.delete(id) }
        }
    }
}
