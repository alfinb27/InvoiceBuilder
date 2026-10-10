package app.invoicebuilder.core.domain.setup

import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.documents.DocumentSummary
import app.invoicebuilder.core.domain.models.DocumentType

/**
 * Home's "Get ready to send your first invoice" checklist (`spec/setup.md` §3.2). Shown until the business has issued
 * an invoice; issued invoices are never deleted, so it never comes back. iOS: `FirstRunChecklist`.
 */
data class FirstRunChecklist(
    val hasClient: Boolean = false,
    val hasItem: Boolean = false,
    val hasIssuedInvoice: Boolean = false,
) {
    enum class Item { setUpBusiness, addClient, saveItem, sendInvoice }

    fun isDone(item: Item): Boolean = when (item) {
        Item.setUpBusiness -> true
        Item.addClient -> hasClient
        Item.saveItem -> hasItem
        Item.sendInvoice -> hasIssuedInvoice
    }

    val doneCount: Int get() = Item.entries.count(::isDone)
    val isShown: Boolean get() = !hasIssuedInvoice

    companion object {
        /** From the business's live clients, items and documents. */
        fun of(clientCount: Int, itemCount: Int, documents: List<DocumentSummary>) = FirstRunChecklist(
            hasClient = clientCount > 0, hasItem = itemCount > 0,
            hasIssuedInvoice = documents.any { it.docType == DocumentType.invoice && it.lifecycle != DocumentLifecycle.draft },
        )
    }
}
