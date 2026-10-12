package app.invoicebuilder.core.domain.pdf

import app.invoicebuilder.core.domain.support.SpecJson
import app.invoicebuilder.core.domain.support.SpecResources
import kotlinx.serialization.Serializable

/**
 * Everything a PDF shows, already formatted (`spec/pdf/RENDERING.md` §1). The renderers draw this and nothing
 * else: no rounding, no label lookups and no locale formatting happen while drawing. iOS: `PDFDocumentModel`.
 */
@Serializable
data class PDFDocumentModel(
    val title: String,
    /** No number yet: every page carries `draftLabel` as a watermark. */
    val isDraft: Boolean,
    val draftLabel: String? = null,
    val number: String? = null,
    val numberLabel: String,
    val meta: List<Field> = emptyList(),
    val seller: Party,
    val buyer: Party? = null,
    val shipTo: Party? = null,
    val columns: List<Column> = emptyList(),
    /** One row per line, in column order. */
    val rows: List<List<String>> = emptyList(),
    val totals: List<TotalRow> = emptyList(),
    val taxSummary: Table? = null,
    val amountInWords: String? = null,
    val homeTotals: String? = null,
    val reverseChargeNote: String? = null,
    val notes: List<Note> = emptyList(),
    val payment: Payment = Payment(),
    val signature: Signature,
    val footer: Footer,
) {
    @Serializable data class Field(val label: String, val value: String)

    @Serializable
    data class Party(val heading: String? = null, val name: String, val lines: List<String> = emptyList(), val fields: List<Field> = emptyList())

    /** [id]: `index`, `description`, `productCode`, `quantity`, `unit`, `unitPrice`, `discount`, `taxable`, `tax:<component>` or `amount`. */
    @Serializable data class Column(val id: String, val label: String, val align: Align)

    @Serializable enum class Align { leading, trailing }

    @Serializable data class Table(val columns: List<Column>, val rows: List<List<String>>)

    @Serializable data class TotalRow(val label: String, val value: String, val emphasis: Emphasis = Emphasis.normal)

    @Serializable enum class Emphasis { normal, strong }

    /** `top` notes are printed above the items, `bottom` ones below the totals. */
    @Serializable data class Note(val label: String? = null, val text: String, val placement: String)

    @Serializable
    data class Payment(val bank: List<Field> = emptyList(), val upi: UPI? = null) {
        /** [payload] is the `upi://pay` link the QR code encodes (`ENGINE.md` §9). */
        @Serializable data class UPI(val id: String, val caption: String, val payload: String)
    }

    @Serializable data class Signature(val imageAssetId: String? = null, val forBusiness: String, val authorisedSignatory: String)

    /** [pageLabel] still holds `{page}` and `{pages}`: the renderer knows the page count. */
    @Serializable data class Footer(val pageLabel: String, val continued: String)

    /** Notes printed above the items table. */
    val topNotes: List<Note> get() = notes.filter { it.placement == "top" }
    /** Notes printed below the totals. */
    val bottomNotes: List<Note> get() = notes.filter { it.placement != "top" }
}

/** The shared label strings (`spec/pdf/labels/en.json`), with `{placeholder}` substitution. iOS: `PDFLabels`. */
@Serializable
data class PDFLabels(val locale: String, val labels: Map<String, String>) {
    /** The label for [key], with each `{name}` replaced. An unknown key returns the key itself. */
    fun text(key: String, arguments: Map<String, String> = emptyMap()): String {
        var text = labels[key] ?: key
        for ((name, value) in arguments) text = text.replace("{$name}", value)
        return text
    }

    companion object {
        fun bundled(locale: String = "en"): PDFLabels =
            SpecJson.decodeFromString(serializer(), SpecResources.text("pdf/labels/$locale.json"))
    }
}
