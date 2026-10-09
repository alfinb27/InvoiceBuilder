package app.invoicebuilder.core.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.invoicebuilder.core.domain.support.SpecJson
import app.invoicebuilder.core.domain.support.SpecResources
import kotlinx.serialization.Serializable

/** `spec/design/tokens.json`, the same file InvoiceUI's `Theme` reads. */
@Serializable
data class DesignTokens(val color: Colors, val status: Map<String, List<String>> = emptyMap(), val space: Map<String, Double>,
                        val radius: Map<String, Double>, val layout: Map<String, Double>, val pdf: PDF) {
    @Serializable data class Palette(
        val brand: String, val brandOn: String, val background: String, val surface: String, val surfaceMuted: String,
        val border: String, val textPrimary: String, val textSecondary: String, val textTertiary: String,
        val success: String, val warning: String, val danger: String, val info: String,
    )
    @Serializable data class Colors(val light: Palette, val dark: Palette)
    @Serializable data class PDF(val accentPresets: List<String>)

    companion object {
        val bundled: DesignTokens by lazy {
            runCatching { SpecJson.decodeFromString(serializer(), SpecResources.text("design/tokens.json")) }.getOrElse { fallback }
        }
        private val fallback = DesignTokens(
            Colors(
                Palette("#1A5FD6", "#FFFFFF", "#F7F8FA", "#FFFFFF", "#EEF1F5", "#D8DEE6", "#111827", "#4B5563", "#5B6371", "#126B33", "#9A4A0B", "#B91C1C", "#1D4ED8"),
                Palette("#4C8DFF", "#0B1220", "#0B0F17", "#131A24", "#1C2532", "#2B3646", "#F3F4F6", "#C4CAD4", "#9AA3AF", "#4ADE80", "#FBBF24", "#F87171", "#93C5FD"),
            ),
            emptyMap(), emptyMap(), emptyMap(), emptyMap(), PDF(listOf("#1F6FEB")),
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
    val brand: Color, val brandOn: Color, val background: Color, val surface: Color, val surfaceMuted: Color,
    val border: Color, val textPrimary: Color, val textSecondary: Color, val textTertiary: Color,
    val success: Color, val warning: Color, val danger: Color, val info: Color, val isDark: Boolean,
) {
    companion object {
        fun of(palette: DesignTokens.Palette, dark: Boolean) = AppColors(
            hexColor(palette.brand), hexColor(palette.brandOn), hexColor(palette.background), hexColor(palette.surface),
            hexColor(palette.surfaceMuted), hexColor(palette.border), hexColor(palette.textPrimary), hexColor(palette.textSecondary),
            hexColor(palette.textTertiary), hexColor(palette.success), hexColor(palette.warning), hexColor(palette.danger),
            hexColor(palette.info), dark,
        )
    }
}

val LocalAppColors = staticCompositionLocalOf { AppColors.of(DesignTokens.bundled.color.light, false) }

/** Token access, named as on iOS: `Theme.colors.brand`, `Theme.Space.l`. */
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
    }

    object Layout {
        /** Material's own minimum is 48 dp; the token (44) is the floor both platforms share. */
        val minTouchTarget = (DesignTokens.bundled.layout["minTouchTarget"] ?: 44.0).dp
        val maxReadableWidth = (DesignTokens.bundled.layout["maxReadableWidth"] ?: 720.0).dp
        /** Two panes (list + detail) from here up (≈ regular horizontal size class). */
        val regularWidthBreakpoint = (DesignTokens.bundled.layout["regularWidthBreakpoint"] ?: 600.0).dp
        val builderPreviewMinWidth = (DesignTokens.bundled.layout["builderPreviewMinWidth"] ?: 900.0).dp
    }

    /** Status chip colour for a derived status (`ENGINE.md` §6), light or dark. */
    fun statusColor(status: String, dark: Boolean): Color =
        tokens.status[status]?.getOrNull(if (dark) 1 else 0)?.let(::hexColor) ?: if (dark) Color(0xFF9AA3AF) else Color(0xFF6B7280)
}

/** Material 3 with the token palette (≈ `.tint(Theme.brand)` on the root view). No dynamic colour: brand first. */
@Composable
fun InvoiceTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val tokens = DesignTokens.bundled
    val colors = AppColors.of(if (dark) tokens.color.dark else tokens.color.light, dark)
    val scheme = if (dark) {
        darkColorScheme(
            primary = colors.brand, onPrimary = colors.brandOn, background = colors.background, onBackground = colors.textPrimary,
            surface = colors.surface, onSurface = colors.textPrimary, surfaceVariant = colors.surfaceMuted,
            onSurfaceVariant = colors.textSecondary, outline = colors.border, outlineVariant = colors.border, error = colors.danger,
            surfaceContainer = colors.surface, surfaceContainerLow = colors.surface, surfaceContainerHigh = colors.surfaceMuted,
            secondaryContainer = colors.brand.copy(alpha = 0.24f), onSecondaryContainer = colors.textPrimary,
        )
    } else {
        lightColorScheme(
            primary = colors.brand, onPrimary = colors.brandOn, background = colors.background, onBackground = colors.textPrimary,
            surface = colors.surface, onSurface = colors.textPrimary, surfaceVariant = colors.surfaceMuted,
            onSurfaceVariant = colors.textSecondary, outline = colors.border, outlineVariant = colors.border, error = colors.danger,
            surfaceContainer = colors.surface, surfaceContainerLow = colors.surface, surfaceContainerHigh = colors.surfaceMuted,
            secondaryContainer = colors.brand.copy(alpha = 0.14f), onSecondaryContainer = colors.textPrimary,
        )
    }
    val type = Typography(
        headlineLarge = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold),
        titleLarge = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold),
        titleMedium = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
        bodyLarge = TextStyle(fontSize = 17.sp),
        bodyMedium = TextStyle(fontSize = 15.sp),
        bodySmall = TextStyle(fontSize = 13.sp),
        labelMedium = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold),
        labelSmall = TextStyle(fontSize = 12.sp),
    )
    androidx.compose.runtime.CompositionLocalProvider(LocalAppColors provides colors) {
        MaterialTheme(colorScheme = scheme, typography = type, content = content)
    }
}
