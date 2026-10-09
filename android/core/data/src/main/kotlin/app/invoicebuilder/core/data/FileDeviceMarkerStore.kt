package app.invoicebuilder.core.data

import app.invoicebuilder.core.domain.setup.DeviceMarker
import app.invoicebuilder.core.domain.setup.DeviceMarkerStore
import java.io.File
import java.io.IOException

/**
 * The device marker as a file in `noBackupFilesDir` (`spec/setup.md` §2, ADR-0019): Auto Backup and device-to-device
 * transfer never copy that folder, so a database restored onto a new phone arrives without it. iOS:
 * `KeychainDeviceMarkerStore`.
 */
class FileDeviceMarkerStore(private val directory: File) : DeviceMarkerStore {
    private val file get() = File(directory, NAME)

    override fun read(): DeviceMarker = try {
        // An empty file is a write cut short: as good as none (the id is then replaced once, harmlessly).
        if (!file.exists()) DeviceMarker.Missing else file.readText().trim().ifEmpty { null }?.let(DeviceMarker::Found) ?: DeviceMarker.Missing
    } catch (error: IOException) {
        DeviceMarker.Unreadable
    }

    /** Written to a temporary file, then renamed over the old one, so a crash never leaves half an id. */
    override fun write(id: String) {
        runCatching {
            directory.mkdirs()
            val temporary = File(directory, "$NAME.tmp")
            temporary.writeText(id)
            if (!temporary.renameTo(file)) {
                file.delete()
                temporary.renameTo(file)
            }
        }
    }

    private companion object {
        const val NAME = "device-id"
    }
}
