package app.invoicebuilder.core.domain.pdf

import app.invoicebuilder.core.domain.models.TemplateID
import app.invoicebuilder.core.domain.support.SpecJson
import app.invoicebuilder.core.domain.support.SpecResources
import kotlinx.serialization.Serializable

/**
 * A template from `spec/pdf/layout/<id>.json` (`schema/pdf-layout.schema.json`): which blocks to draw, in order,
 * and the style tokens to draw them with. Both platforms decode this same file. iOS: `PDFTemplate`.
 */
@Serializable
data class PDFTemplate(
    val id: TemplateID,
    val label: String,
    val description: String? = null,
    val page: Page,
    val style: Style,
    val blocks: List<Block>,
) {
    @Serializable
    data class Page(val margins: Margins, val footerHeight: Double) {
        @Serializable data class Margins(val top: Double, val right: Double, val bottom: Double, val left: Double)
    }

    @Serializable
    data class Style(
        val fontSizes: FontSizes,
        val lineHeight: Double,
        val colors: Colors,
        val accentUse: List<String>,
        val rule: Rule,
        val table: Table,
        val blockSpacing: Double,
        val logo: Logo,
        val qrSize: Double? = null,
        val signatureHeight: Double? = null,
    ) {
        @Serializable data class FontSizes(val title: Double, val heading: Double, val body: Double, val small: Double)

        @Serializable
        data class Colors(
            val text: String, val muted: String, val rule: String, val onAccent: String,
            val tableHeaderFill: String? = null, val zebraFill: String? = null,
        )

        @Serializable data class Rule(val width: Double)

        @Serializable
        data class Table(val headerWeight: Weight, val headerUppercase: Boolean, val rowPadding: Padding, val rowRule: RowRule) {
            @Serializable data class Padding(val vertical: Double, val horizontal: Double)
        }

        @Serializable data class Logo(val maxWidth: Double, val maxHeight: Double)
    }

    @Serializable enum class Weight { regular, semibold, bold }

    @Serializable enum class RowRule { none, below, zebra }

    /** [id]: `header`, `parties`, `items`, `totals`, `payment`, `notes`, `signature`; open sets, like iOS. */
    @Serializable data class Block(val id: String, val variant: String)

    /** Where the accent colour is used (`title`, `headerBand`, `tableHeaderFill`, …); unknown values are ignored. */
    fun uses(accent: String): Boolean = accent in style.accentUse

    fun block(kind: String): Block? = blocks.firstOrNull { it.id == kind }
}

/** The templates bundled in `:core:domain` (`spec/pdf/layout`, copied by `make sync-spec`). iOS: `PDFTemplateStore`. */
class PDFTemplateStore(val templates: List<PDFTemplate>) {
    /** The template a document asks for, falling back to the first one (a value from a newer app version). */
    fun template(id: TemplateID): PDFTemplate? = templates.firstOrNull { it.id == id } ?: templates.firstOrNull()

    /** For the template switcher, in file order. */
    val all: List<PDFTemplate> get() = templates

    companion object {
        /** The files in `spec/pdf/layout`, sorted (resources cannot be listed; a test checks the list). */
        val bundledFiles = listOf("classic.json", "compact.json", "minimal.json", "modern.json")

        fun bundled(): PDFTemplateStore = PDFTemplateStore(bundledFiles.map {
            SpecJson.decodeFromString(PDFTemplate.serializer(), SpecResources.text("pdf/layout/$it"))
        })
    }
}
