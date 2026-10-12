package app.invoicebuilder.android.common

import app.invoicebuilder.core.designsystem.DesignTokens
import app.invoicebuilder.core.designsystem.Theme
import app.invoicebuilder.core.designsystem.hexColor
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * `spec/design/tokens.json` decodes as it is (ADR-0020): the theme falls back to built-in values when it doesn't, which
 * looks almost right and hides the problem. iOS: `DesignTokensTests`.
 */
class DesignTokensTests {
    @Test
    fun theBundledTokensDecode() {
        val tokens = DesignTokens.load()
        assertEquals("#C2482A", tokens.color.light.brand)
        assertEquals("#F0866A", tokens.color.dark.brand)
        assertEquals(31.0, tokens.type["largeTitle"]?.size)
        assertEquals("display", tokens.type["title"]?.font)
        assertEquals("Bricolage Grotesque", tokens.fonts?.display?.family)
        assertEquals(20.0, tokens.radius["card"])
    }

    @Test
    fun statusColoursSkipTheComment() {
        assertEquals(hexColor("#126B33"), Theme.statusColor("paid", dark = false))
        assertEquals(hexColor("#4ADE80"), Theme.statusColor("paid", dark = true))
    }
}
