package app.invoicebuilder.core.domain.backup

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull

/** A file in the Drive sync folder (`spec/drive-sync.md` §3), from its `appProperties`. iOS: `DriveSyncEntry`. */
data class DriveSyncEntry(
    val id: String,
    val kind: Kind?,
    val deviceID: String?,
    /** Change files only. */
    val seq: Int? = null,
    val createdAt: Long? = null,
) {
    enum class Kind(val rawValue: String) {
        Changes("changes"), Snapshot("snapshot");
        companion object { fun of(raw: String?) = entries.firstOrNull { it.rawValue == raw } }
    }

    companion object {
        const val KEY_KIND = "ibKind"
        const val KEY_DEVICE_ID = "ibDeviceId"
        const val KEY_SEQ = "ibSeq"
        const val KEY_CREATED_AT = "ibCreatedAt"

        fun of(id: String, properties: Map<String, String>) = DriveSyncEntry(id, Kind.of(properties[KEY_KIND]),
            properties[KEY_DEVICE_ID], properties[KEY_SEQ]?.toIntOrNull(), properties[KEY_CREATED_AT]?.toLongOrNull())
    }
}

/** The pure rules of live sync through Google Drive (`spec/drive-sync.md`; fixtures kind `drivesync`). iOS: `DriveSync`. */
object DriveSync {
    /** §8: own change files older than this, and covered by the snapshot, may go. */
    const val PRUNE_AGE = 30L * 24 * 60 * 60 * 1000
    /** §8: a snapshot is written once a device has more change files than this. */
    const val SNAPSHOT_AFTER = 200

    // §5 merge

    /** §5: the incoming record replaces the local one. Records are backup-encoded JSON; [collection] is the backup key. */
    fun wins(local: JsonObject?, incoming: JsonObject, collection: String): Boolean {
        if (local == null) return true
        if (collection == "documents") {
            val (l, i) = lifecycleRank(local["lifecycle"]) to lifecycleRank(incoming["lifecycle"])
            if (l != i) return i > l
        }
        val (lu, iu) = (long(local["updatedAt"]) ?: 0) to (long(incoming["updatedAt"]) ?: 0)
        if (lu != iu) return iu > lu
        val (ld, id) = isSet(local["deletedAt"]) to isSet(incoming["deletedAt"])
        if (ld != id) return id
        return compareBytes(canonicalText(local).encodeToByteArray(), canonicalText(incoming).encodeToByteArray()) < 0
    }

    /** §5 step 4: sorted keys, nulls left out, no whitespace, minimal escaping. */
    fun canonicalText(value: JsonElement): String = StringBuilder().also { write(value, it) }.toString()

    private fun write(value: JsonElement, out: StringBuilder) {
        when (value) {
            is JsonObject -> {
                out.append('{')
                value.entries.filter { it.value !is JsonNull }
                    .sortedWith { a, b -> compareBytes(a.key.encodeToByteArray(), b.key.encodeToByteArray()) }
                    .forEachIndexed { index, (key, element) ->
                        if (index > 0) out.append(',')
                        writeString(key, out)
                        out.append(':')
                        write(element, out)
                    }
                out.append('}')
            }
            is JsonArray -> {
                out.append('[')
                value.forEachIndexed { index, element ->
                    if (index > 0) out.append(',')
                    write(element, out)
                }
                out.append(']')
            }
            is JsonNull -> out.append("null")
            is JsonPrimitive -> if (value.isString) writeString(value.content, out) else out.append(value.content)
        }
    }

    private fun writeString(string: String, out: StringBuilder) {
        out.append('"')
        for (char in string) {
            when {
                char == '"' -> out.append("\\\"")
                char == '\\' -> out.append("\\\\")
                char.code < 0x20 -> out.append("\\u%04x".format(char.code))
                else -> out.append(char)
            }
        }
        out.append('"')
    }

    /** Unsigned byte order, as UTF-8 compares. */
    private fun compareBytes(a: ByteArray, b: ByteArray): Int {
        for (index in 0 until minOf(a.size, b.size)) {
            val diff = (a[index].toInt() and 0xff) - (b[index].toInt() and 0xff)
            if (diff != 0) return diff
        }
        return a.size - b.size
    }

    private fun lifecycleRank(value: JsonElement?) = when ((value as? JsonPrimitive)?.contentOrNull) {
        "issued" -> 1
        "void" -> 2
        else -> 0
    }

    private fun long(value: JsonElement?) = (value as? JsonPrimitive)?.longOrNull
    private fun isSet(value: JsonElement?) = value != null && value !is JsonNull

    // §6 pull

    /** §6: the files a pull reads, in order — one catch-up snapshot alone, or the next change files. */
    fun toRead(entries: List<DriveSyncEntry>, seen: Map<String, Int>, thisDevice: String): List<String> {
        val others = entries.filter { it.kind != null && it.deviceID != null && it.deviceID != thisDevice }
        val devices = others.mapNotNull { it.deviceID }.toSortedSet()
        val changes = mutableMapOf<String, MutableMap<Int, String>>()
        val snapshots = mutableMapOf<String, String>()
        for (entry in others) {
            val device = entry.deviceID!!
            when (entry.kind) {
                DriveSyncEntry.Kind.Changes -> entry.seq?.let { changes.getOrPut(device) { mutableMapOf() }[it] = entry.id }
                DriveSyncEntry.Kind.Snapshot -> snapshots[device] = entry.id
                null -> {}
            }
        }
        for (device in devices) {
            val next = (seen[device] ?: 0) + 1
            val files = changes[device].orEmpty()
            val behind = if (files.isEmpty()) seen[device] == null else files[next] == null && files.keys.any { it > next }
            if (behind) snapshots[device]?.let { return listOf(it) }
        }
        val ids = mutableListOf<String>()
        for (device in devices) {
            var seq = (seen[device] ?: 0) + 1
            while (true) {
                ids += changes[device]?.get(seq) ?: break
                seq++
            }
        }
        return ids
    }

    // §8 compaction

    /** §8: this device's change files its snapshot covers and that are more than 30 days old. */
    fun filesToDelete(entries: List<DriveSyncEntry>, thisDevice: String, snapshotCovers: Int?, now: Long): List<String> {
        if (snapshotCovers == null) return emptyList()
        return entries.filter {
            it.kind == DriveSyncEntry.Kind.Changes && it.deviceID == thisDevice && (it.seq ?: Int.MAX_VALUE) <= snapshotCovers &&
                (it.createdAt?.let { created -> now - created > PRUNE_AGE } ?: false)
        }.sortedBy { it.seq ?: 0 }.map { it.id }
    }
}
