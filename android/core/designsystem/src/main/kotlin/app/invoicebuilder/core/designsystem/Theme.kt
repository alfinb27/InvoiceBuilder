package app.invoicebuilder.core.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import app.invoicebuilder.core.domain.support.SpecJson
import app.invoicebuilder.core.domain.support.SpecResources
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

/** `spec/design/tokens.json` (v2, ADR-0020), the same file InvoiceUI's `Theme` reads. */
@Serializable
data class DesignTokens(
    /** Light/dark pairs per status; a JSON element each because the object also holds a `"$comment"` string. */
    val color: Colors, val status: Map<String, JsonElement> = emptyMap(), val fonts: FontRoles? = null,
    val type: Map<String, TextStyleToken> = emptyMap(), val space: Map<String, Double>, val radius: Map<String, Double>,
    val layout: Map<String, Double>, val pdf: PDF,
) {
    @Serializable data class Palette(
        val brand: String, val brandPressed: String, val brandOn: String, val brandTint: String, val background: String,
        val surface: String, val surfaceMuted: String, val surfaceSubtle: String, val border: String, val borderStrong: String,
        val control: String, val textPrimary: String, val textSecondary: String, val textTertiary: String, val tip: String,
        val tipOn: String, val tipIcon: String, val highlight: String, val scrim: String, val success: String,
        val warning: String, val danger: String, val info: String,
    )
    @Serializable data class Colors(val light: Palette, val dark: Palette)
    @Serializable data class FontFamilyToken(val family: String, val files: Map<String, String>)
    @Serializable data class FontRoles(val display: FontFamilyToken, val text: FontFamilyToken)
    @Serializable data class TextStyleToken(
        val font: String, val size: Double, val weight: String, val tracking: Double? = null, val uppercase: Boolean? = null,
        val monospacedDigits: Boolean? = null,
    )
    @Serializable data class PDF(val accentPresets: List<String>)

    companion object {
        val bundled: DesignTokens by lazy { runCatching { load() }.getOrElse { fallback } }

        /** `spec/design/tokens.json`; throws when it doesn't decode (tests call this, so the fallback is never silent). */
        fun load(): DesignTokens = SpecJson.decodeFromString(serializer(), SpecResources.text("design/tokens.json"))
        private val fallbackPalette = Palette(
            "#C2482A", "#9E3820", "#FFFFFF", "#FDE3D8", "#FFF5EF", "#FFFFFF", "#F8ECE5", "#FBE9E0", "#EEDFD6", "#E2CFC4",
            "#CDB3A6", "#2A2135", "#6B5F72", "#9A8C92", "#E3F0FF", "#1D3A5F", "#2C5C94", "#8EC5FF", "#5A4A55", "#126B33",
            "#9A4A0B", "#B91C1C", "#1D4ED8",
        )
        private val fallback = DesignTokens(
            Colors(fallbackPalette, fallbackPalette), space = emptyMap(), radius = emptyMap(), layout = emptyMap(),
            pdf = PDF(listOf("#1F6FEB")),
        )
    }
}

fun hexColor(hex: String): Color {
    val value = hex.removePrefix("#").toLongOrNull(16) ?: 0x808080
    return Color(0xFF000000 or value)
}

/** The palette for the current appearance (≈ `Theme.brand` etc., which resolve light/dark themselves). */
@Immutable
data class AppColors(
    val brand: Color, val brandPressed: Color, val brandOn: Color, val brandTint: Color, val background: Color,
    val surface: Color, val surfaceMuted: Color, val surfaceSubtle: Color, val border: Color, val borderStrong: Color,
    val control: Color, val textPrimary: Color, val textSecondary: Color, val textTertiary: Color, val tip: Color,
    val tipOn: Color, val tipIcon: Color, val highlight: Color, val scrim: Color, val success: Color, val warning: Color,
    val danger: Color, val info: Color, val isDark: Boolean,
) {
    /** Shadows use the ink colour (`design.md` §2.1). */
    val shadow: Color get() = Color(0xFF2A2135)

    companion object {
        fun of(p: DesignTokens.Palette, dark: Boolean) = AppColors(
            hexColor(p.brand), hexColor(p.brandPressed), hexColor(p.brandOn), hexColor(p.brandTint), hexColor(p.background),
            hexColor(p.surface), hexColor(p.surfaceMuted), hexColor(p.surfaceSubtle), hexColor(p.border),
            hexColor(p.borderStrong), hexColor(p.control), hexColor(p.textPrimary), hexColor(p.textSecondary),
            hexColor(p.textTertiary), hexColor(p.tip), hexColor(p.tipOn), hexColor(p.tipIcon), hexColor(p.highlight),
            hexColor(p.scrim), hexColor(p.success), hexColor(p.warning), hexColor(p.danger), hexColor(p.info), dark,
        )
    }
}

val LocalAppColors = staticCompositionLocalOf { AppColors.of(DesignTokens.bundled.color.light, false) }

/** The bundled UI fonts (`spec/design/fonts`, OFL), copied into `res/font` by `make sync-spec`. */
object AppFonts {
    /** Bricolage Grotesque: titles and amounts. */
    val display = FontFamily(
        Font(R.font.bricolage_grotesque_semi_bold, FontWeight.SemiBold),
        Font(R.font.bricolage_grotesque_bold, FontWeight.Bold),
    )

    /** Figtree: everything else. */
    val text = FontFamily(
        Font(R.font.figtree_regular, FontWeight.Normal),
        Font(R.font.figtree_medium, FontWeight.Medium),
        Font(R.font.figtree_semi_bold, FontWeight.SemiBold),
        Font(R.font.figtree_bold, FontWeight.Bold),
    )
}

/** Token access, named as on iOS: `Theme.colors.brand`, `Theme.Space.l`, `Theme.Fonts.title`. */
object Theme {
    val tokens get() = DesignTokens.bundled
    val colors: AppColors @Composable @ReadOnlyComposable get() = LocalAppColors.current
    val accentPresets: List<String> get() = tokens.pdf.accentPresets

    object Space {
        val xxs = (DesignTokens.bundled.space["xxs"] ?: 2.0).dp
        val xs = (DesignTokens.bundled.space["xs"] ?: 4.0).dp
        val s = (DesignTokens.bundled.space["s"] ?: 8.0).dp
        val m = (DesignTokens.bundled.space["m"] ?: 12.0).dp
        val l = (DesignTokens.bundled.space["l"] ?: 16.0).dp
        val xl = (DesignTokens.bundled.space["xl"] ?: 24.0).dp
        val xxl = (DesignTokens.bundled.space["xxl"] ?: 32.0).dp
    }

    object Radius {
        val s = (DesignTokens.bundled.radius["s"] ?: 6.0).dp
        val m = (DesignTokens.bundled.radius["m"] ?: 10.0).dp
        val l = (DesignTokens.bundled.radius["l"] ?: 16.0).dp
        val input = (DesignTokens.bundled.radius["input"] ?: 14.0).dp
        val button = (DesignTokens.bundled.radius["button"] ?: 16.0).dp
        val card = (DesignTokens.bundled.radius["card"] ?: 20.0).dp
        val sheet = (DesignTokens.bundled.radius["sheet"] ?: 26.0).dp
        val hero = (DesignTokens.bundled.radius["hero"] ?: 24.0).dp
    }

    object Layout {
        /** Material's own minimum is 48 dp; the token (44) is the floor both platforms share. */
        val minTouchTarget = (DesignTokens.bundled.layout["minTouchTarget"] ?: 44.0).dp
        val maxReadableWidth = (DesignTokens.bundled.layout["maxReadableWidth"] ?: 720.0).dp
        /** Two panes (list + detail) from here up (≈ regular horizontal size class). */
        val regularWidthBreakpoint = (DesignTokens.bundled.layout["regularWidthBreakpoint"] ?: 600.0).dp
        val builderPreviewMinWidth = (DesignTokens.bundled.layout["builderPreviewMinWidth"] ?: 900.0).dp
        val primaryButtonHeight = (DesignTokens.bundled.layout["primaryButtonHeight"] ?: 56.0).dp
        val inputHeight = (DesignTokens.bundled.layout["inputHeight"] ?: 50.0).dp
        val screenGutter = (DesignTokens.bundled.layout["screenGutter"] ?: 20.0).dp
    }

    /** The type roles of `tokens.json`, each a bundled font at its token size (scaled by the system font size). */
    object Fonts {
        val largeTitle get() = style("largeTitle")
        val title get() = style("title")
        val title3 get() = style("title3")
        val headline get() = style("headline")
        val body get() = style("body")
        val rowTitle get() = style("rowTitle")
        val button get() = style("button")
        val callout get() = style("callout")
        val subhead get() = style("subhead")
        val footnote get() = style("footnote")
        val caption get() = style("caption")
        val overline get() = style("overline")
        val amountLarge get() = style("amountLarge")
        val amount get() = style("amount")

        fun style(role: String): TextStyle {
            val token = DesignTokens.bundled.type[role] ?: DesignTokens.TextStyleToken("text", 16.0, "regular")
            return TextStyle(
                fontFamily = if (token.font == "display") AppFonts.display else AppFonts.text,
                fontSize = token.size.sp,
                fontWeight = when (token.weight) {
                    "medium" -> FontWeight.Medium
                    "semibold" -> FontWeight.SemiBold
                    "bold" -> FontWeight.Bold
                    else -> FontWeight.Normal
                },
                letterSpacing = (token.tracking ?: 0.0).sp,
                fontFeatureSettings = if (token.monospacedDigits == true) "tnum" else null,
                lineHeight = if (token.font == "display") 1.15.em else 1.4.em,
                lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
            )
        }
    }

    /** Status chip colour for a derived status (`ENGINE.md` §6), light or dark. */
    fun statusColor(status: String, dark: Boolean): Color =
        ((tokens.status[status] as? JsonArray)?.getOrNull(if (dark) 1 else 0) as? JsonPrimitive)?.content?.let(::hexColor)
            ?: if (dark) Color(0xFF9AA3AF) else Color(0xFF5C6270)
}

/**
 * Material 3 with the token palette, fonts and radii (≈ `.themedRoot()` on the root view). No dynamic colour: the
 * brand first.
 */
@Composable
fun InvoiceTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val tokens = DesignTokens.bundled
    val colors = AppColors.of(if (dark) tokens.color.dark else tokens.color.light, dark)
    val scheme = if (dark) {
        darkColorScheme(
            primary = colors.brand, onPrimary = colors.brandOn, primaryContainer = colors.brandTint,
            onPrimaryContainer = colors.brandPressed, background = colors.background, onBackground = colors.textPrimary,
            surface = colors.surface, onSurface = colors.textPrimary, surfaceVariant = colors.surfaceMuted,
            onSurfaceVariant = colors.textSecondary, outline = colors.borderStrong, outlineVariant = colors.border,
            error = colors.danger, surfaceContainer = colors.surface, surfaceContainerLow = colors.surface,
            surfaceContainerLowest = colors.surface, surfaceContainerHigh = colors.surfaceMuted,
            surfaceContainerHighest = colors.surfaceMuted, secondaryContainer = colors.brandTint,
            onSecondaryContainer = colors.textPrimary, scrim = colors.scrim,
        )
    } else {
        lightColorScheme(
            primary = colors.brand, onPrimary = colors.brandOn, primaryContainer = colors.brandTint,
            onPrimaryContainer = colors.brandPressed, background = colors.background, onBackground = colors.textPrimary,
            surface = colors.surface, onSurface = colors.textPrimary, surfaceVariant = colors.surfaceMuted,
            onSurfaceVariant = colors.textSecondary, outline = colors.borderStrong, outlineVariant = colors.border,
            error = colors.danger, surfaceContainer = colors.surface, surfaceContainerLow = colors.surface,
            surfaceContainerLowest = colors.surface, surfaceContainerHigh = colors.surfaceMuted,
            surfaceContainerHighest = colors.surfaceMuted, secondaryContainer = colors.brandTint,
            onSecondaryContainer = colors.textPrimary, scrim = colors.scrim,
        )
    }
    val type = Typography(
        displaySmall = Theme.Fonts.largeTitle,
        headlineLarge = Theme.Fonts.largeTitle,
        headlineMedium = Theme.Fonts.title,
        headlineSmall = Theme.Fonts.title3,
        titleLarge = Theme.Fonts.title3,
        titleMedium = Theme.Fonts.headline,
        titleSmall = Theme.Fonts.rowTitle,
        bodyLarge = Theme.Fonts.body,
        bodyMedium = Theme.Fonts.callout,
        bodySmall = Theme.Fonts.footnote,
        labelLarge = Theme.Fonts.callout.copy(fontWeight = FontWeight.SemiBold),
        labelMedium = Theme.Fonts.caption,
        labelSmall = Theme.Fonts.caption.copy(fontSize = 11.sp),
    )
    val shapes = Shapes(
        extraSmall = RoundedCornerShape(Theme.Radius.s),
        small = RoundedCornerShape(Theme.Radius.input),
        medium = RoundedCornerShape(Theme.Radius.card),
        large = RoundedCornerShape(Theme.Radius.sheet),
        extraLarge = RoundedCornerShape(Theme.Radius.sheet),
    )
    androidx.compose.runtime.CompositionLocalProvider(LocalAppColors provides colors) {
        MaterialTheme(colorScheme = scheme, typography = type, shapes = shapes, content = content)
    }
}
