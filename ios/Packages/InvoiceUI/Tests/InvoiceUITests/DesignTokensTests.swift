import Testing
import UIKit
@testable import InvoiceUI

/// `spec/design/tokens.json` decodes as it is and the bundled fonts register (ADR-0020): the theme falls back to
/// built-in values when they don't, which looks almost right and hides the problem. Android: `DesignTokensTests`.
@MainActor
@Suite("Design tokens")
struct DesignTokensTests {
    @Test func theBundledTokensDecode() throws {
        let tokens = try DesignTokens.bundled()
        #expect(tokens.color.light.brand == "#C2482A" && tokens.color.dark.brand == "#F0866A")
        #expect(tokens.type["largeTitle"]?.size == 31 && tokens.type["title"]?.font == "display")
        #expect(tokens.fonts?.display.family == "Bricolage Grotesque")
        #expect(tokens.radius["card"] == 20)
    }

    @Test func theUIFontsRegister() {
        AppFonts.registerIfNeeded()
        for name in ["BricolageGrotesque-SemiBold", "BricolageGrotesque-Bold", "Figtree-Regular", "Figtree-Medium",
                     "Figtree-SemiBold", "Figtree-Bold"] {
            #expect(UIFont(name: name, size: 12) != nil, "\(name) is not registered")
        }
    }
}
