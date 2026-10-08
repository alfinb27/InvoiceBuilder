package app.invoicebuilder.android.common

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.print.PrintAttributes
import android.print.PrintManager
import androidx.core.content.FileProvider
import java.io.File

/**
 * The system sheets (iOS: `SystemSheets`, `ShareLink`, `UIPrintInteractionController`). A file leaves the app as a
 * `content://` Uri from the FileProvider declared in the manifest, with read permission granted to the receiver.
 */
object SystemSheets {
    fun uri(context: Context, file: File) = FileProvider.getUriForFile(context, "${context.packageName}.files", file)

    fun shareFile(context: Context, file: File, mime: String, subject: String? = null, text: String? = null) {
        val uri = uri(context, file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            subject?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
            text?.let { putExtra(Intent.EXTRA_TEXT, it) }
            clipData = ClipData.newRawUri(file.name, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    fun shareText(context: Context, text: String) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Prints a PDF file with the system print dialog (≈ `UIPrintInteractionController`). */
    fun print(context: Context, file: File, jobName: String, paperSize: String) {
        val manager = context.getSystemService(Context.PRINT_SERVICE) as PrintManager
        val media = if (paperSize.equals("Letter", true)) PrintAttributes.MediaSize.NA_LETTER else PrintAttributes.MediaSize.ISO_A4
        manager.print(jobName, PdfPrintAdapter(file, jobName), PrintAttributes.Builder().setMediaSize(media).build())
    }
}

/** Hands an already-rendered PDF to the print framework page for page. */
private class PdfPrintAdapter(private val file: File, private val name: String) : android.print.PrintDocumentAdapter() {
    override fun onLayout(
        oldAttributes: PrintAttributes?, newAttributes: PrintAttributes?, cancellationSignal: android.os.CancellationSignal?,
        callback: LayoutResultCallback, extras: android.os.Bundle?,
    ) {
        if (cancellationSignal?.isCanceled == true) return callback.onLayoutCancelled()
        val info = android.print.PrintDocumentInfo.Builder(name).setContentType(android.print.PrintDocumentInfo.CONTENT_TYPE_DOCUMENT).build()
        callback.onLayoutFinished(info, oldAttributes != newAttributes)
    }

    override fun onWrite(
        pages: Array<out android.print.PageRange>?, destination: android.os.ParcelFileDescriptor,
        cancellationSignal: android.os.CancellationSignal?, callback: WriteResultCallback,
    ) {
        runCatching {
            file.inputStream().use { input -> java.io.FileOutputStream(destination.fileDescriptor).use { input.copyTo(it) } }
        }.onSuccess { callback.onWriteFinished(arrayOf(android.print.PageRange.ALL_PAGES)) }
            .onFailure { callback.onWriteFailed(it.message) }
    }
}
