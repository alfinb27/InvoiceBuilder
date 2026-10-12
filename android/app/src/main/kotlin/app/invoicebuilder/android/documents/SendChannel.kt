package app.invoicebuilder.android.documents

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.Print
import androidx.compose.ui.graphics.vector.ImageVector
import app.invoicebuilder.core.domain.models.DocumentType

/**
 * How Review & send hands the PDF over (`spec/documents.md` §8). Android can open WhatsApp itself with the PDF; iOS
 * uses the share sheet for it. iOS: `SendChannel`.
 */
enum class SendChannel(val label: String, val icon: ImageVector) {
    whatsApp("WhatsApp", Icons.AutoMirrored.Outlined.Chat),
    email("Email", Icons.Outlined.Email),
    print("Print", Icons.Outlined.Print),
    savePDF("Save PDF", Icons.Outlined.Download);

    /** The Review & send button for this channel. */
    fun buttonTitle(docType: DocumentType): String = when (this) {
        whatsApp -> "Send on WhatsApp"
        email -> "Send by email"
        print -> "Print ${DocumentText.noun(docType)}"
        savePDF -> "Save as PDF"
    }
}
