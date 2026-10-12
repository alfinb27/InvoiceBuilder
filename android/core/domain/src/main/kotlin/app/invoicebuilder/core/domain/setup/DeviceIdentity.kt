package app.invoicebuilder.core.domain.setup

/** What a device knows about its own id outside the database (`spec/setup.md` §2, ADR-0019). iOS: `DeviceMarker`. */
sealed interface DeviceMarker {
    data class Found(val id: String) : DeviceMarker
    /** Nothing stored: a first launch, or a database copied from another device by an OS backup. */
    data object Missing : DeviceMarker
    /** It could not be read right now (an I/O error): never a reason to change the id. */
    data object Unreadable : DeviceMarker
}

/**
 * Where the marker lives: somewhere an OS backup never carries to another device (Android: a file in
 * `noBackupFilesDir`; iOS: a Keychain item, this device only).
 */
interface DeviceMarkerStore {
    fun read(): DeviceMarker
    /**
     * False when it could not be stored: the caller then keeps the id it has, rather than replacing it on every launch
     * because the marker never sticks.
     */
    fun write(id: String): Boolean
}

/** Whether this database's `device_state` row belongs to this device (`spec/setup.md` §2). iOS: `DeviceIdentity`. */
object DeviceIdentity {
    enum class Action {
        /** No row yet: create it, then write the marker. */
        create,
        /** The row is this device's (or the marker can't be read right now). */
        keep,
        /** The database was copied from another device: the row takes a new id, then the marker is written. */
        replace,
    }

    fun check(rowID: String?, marker: DeviceMarker): Action = when {
        rowID == null -> Action.create
        marker is DeviceMarker.Found -> if (marker.id == rowID) Action.keep else Action.replace
        marker is DeviceMarker.Missing -> Action.replace
        else -> Action.keep
    }
}

/** A marker that lives as long as the process (tests, in-memory databases). [writesSucceed] false = a store that refuses. */
class InMemoryDeviceMarkerStore(
    @Volatile private var marker: DeviceMarker = DeviceMarker.Missing,
    private val writesSucceed: Boolean = true,
) : DeviceMarkerStore {
    override fun read(): DeviceMarker = marker
    override fun write(id: String): Boolean {
        if (!writesSucceed) return false
        marker = DeviceMarker.Found(id)
        return true
    }
    /** Tests: what the next read returns (`Missing` = a database restored onto another device). */
    fun set(value: DeviceMarker) { marker = value }
}
