package app.invoicebuilder.android.documents

import app.invoicebuilder.core.domain.documents.Document
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.TemplateID
import app.invoicebuilder.core.domain.pdf.PDFLabels
import app.invoicebuilder.core.domain.pdf.PDFModelBuilder
import app.invoicebuilder.core.domain.pdf.PDFTemplate
import app.invoicebuilder.core.domain.pdf.PDFTemplateStore
import app.invoicebuilder.core.domain.reference.ReferenceData
import app.invoicebuilder.core.domain.repositories.AssetRepository
import app.invoicebuilder.core.domain.support.SpecJson
import app.invoicebuilder.core.domain.support.SpecLoadingError
import app.invoicebuilder.core.domain.tax.ComputedDocument
import app.invoicebuilder.core.domain.tax.TaxConfigStore
import app.invoicebuilder.core.pdf.PDFRenderRequest
import app.invoicebuilder.core.pdf.PDFRenderer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

/** A rendered PDF on disk: what the preview shows and what sharing and printing send. */
data class PDFFile(val file: File, val template: TemplateID)

/**
 * Renders documents to PDF files and keeps them in the cache directory (`spec/pdf/RENDERING.md` §5). An issued
 * document never changes, so its file is written once; a draft's file is replaced whenever it changes.
 * iOS: `PDFLibrary` (an actor there; a mutex here).
 */
class PDFLibrary(
    private val configs: TaxConfigStore,
    private val reference: ReferenceData,
    private val assets: AssetRepository,
    cacheDirectory: File,
) {
    private val templates = PDFTemplateStore.bundled()
    private val labels = PDFLabels.bundled()
    private val directory = File(cacheDirectory, "pdfs").also { it.mkdirs() }
    private val fontDirectory = cacheDirectory
    private val lock = Mutex()

    /** The templates the switcher offers, in spec order. */
    val allTemplates: List<PDFTemplate> get() = templates.all

    /** A rendered file for [document], from the cache when it is still valid. */
    suspend fun file(document: Document, business: Business, computed: ComputedDocument, template: TemplateID? = null): PDFFile = lock.withLock {
        val templateID = template ?: document.templateId
        val target = File(directory, name(document, business, templateID))
        if (!target.exists()) {
            val bytes = render(document, business, computed, templateID)
            val temp = File(directory, target.name + ".tmp")
            temp.writeBytes(bytes)
            temp.renameTo(target)
            prune(target, document.id, templateID)
            trim(target)
        }
        PDFFile(target, templateID)
    }

    /** The bytes, without touching the cache (the live preview while a draft is edited). */
    suspend fun data(document: Document, business: Business, computed: ComputedDocument, template: TemplateID? = null): ByteArray =
        render(document, business, computed, template ?: document.templateId)

    private suspend fun render(document: Document, business: Business, computed: ComputedDocument, template: TemplateID): ByteArray {
        val config = configs.config(document.taxConfigRef) ?: configs.latest(business.taxConfig, document.effectiveDate)
            ?: throw SpecLoadingError("tax/${document.taxConfigRef}", "no config for this document")
        val layout = templates.template(template) ?: throw SpecLoadingError("pdf/layout/${template.rawValue}.json", "template not bundled")
        val model = PDFModelBuilder.build(document, computed, config, labels, reference)
        val logoID = document.sellerSnapshot?.logoAssetId ?: business.logoAssetId
        val signatureID = document.sellerSnapshot?.signatureAssetId ?: business.signatureAssetId
        val request = PDFRenderRequest(
            model, layout, config.paperSize, business.accentColor,
            logoID?.let { assets.fetchAsset(it)?.data }, signatureID?.let { assets.fetchAsset(it)?.data },
        )
        // Drawing is CPU work: off the main thread (≈ `Task.detached(priority: .userInitiated)`).
        return withContext(Dispatchers.Default) { PDFRenderer.render(request, fontDirectory) }
    }

    /** Everything that changes the drawing goes into the name: the document itself, the template and the branding. */
    private fun name(document: Document, business: Business, template: TemplateID): String {
        val key = SpecJson.encodeToString(Document.serializer(), document) +
            "|${template.rawValue}|${business.accentColor ?: "-"}|${business.logoAssetId ?: "-"}|${business.signatureAssetId ?: "-"}"
        var hash = -0x340d631b7bdddcdbL // FNV-1a offset basis 0xcbf29ce484222325
        for (byte in key.encodeToByteArray()) hash = (hash xor (byte.toLong() and 0xFF)) * 0x100000001b3L
        return "${prefix(document.id, template)}${java.lang.Long.toUnsignedString(hash, 16)}.pdf"
    }

    private fun prefix(documentID: String, template: TemplateID) = "$documentID-${template.rawValue}-"

    /** Drops the files this one replaces but keeps other templates, so switching back does not re-render. */
    private fun prune(keeping: File, documentID: String, template: TemplateID) {
        val prefix = prefix(documentID, template)
        directory.listFiles()?.filter { it.name.startsWith(prefix) && it != keeping }?.forEach { it.delete() }
    }

    /** Keeps the cache to [limit] files, oldest first. */
    private fun trim(keeping: File, limit: Int = 240) {
        val files = directory.listFiles()?.toList() ?: return
        if (files.size <= limit) return
        files.filter { it != keeping }.sortedBy { it.lastModified() }.take(files.size - limit).forEach { it.delete() }
    }

    /** Removes every cached file (after a restore replaced the data). */
    suspend fun forgetAll() = lock.withLock { directory.listFiles()?.forEach { it.delete() }; Unit }

    /** Removes the cached files of one document (a deleted draft). */
    suspend fun forget(documentID: String) = lock.withLock {
        directory.listFiles()?.filter { it.name.startsWith(documentID) }?.forEach { it.delete() }; Unit
    }
}
