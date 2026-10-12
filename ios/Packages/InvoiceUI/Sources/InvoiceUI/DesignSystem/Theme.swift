import CoreText
import InvoiceCore
import SwiftUI
import UIKit

/// Colours, fonts, spacing, radii and layout sizes from `spec/design/tokens.json` (v2, ADR-0020), shared with
/// Android's `:core:designsystem`. Every text style scales with Dynamic Type.
public enum Theme {
    static let tokens = (try? DesignTokens.bundled()) ?? DesignTokens.fallback

    // MARK: Colours (light/dark pairs)

    public static let brand = color(\.brand)
    /// Pressed brand, and brand-coloured text on `brandTint` / muted fills (brand itself is too light there).
    public static let brandPressed = color(\.brandPressed)
    public static let brandOn = color(\.brandOn)
    /// Selected chips and cards, avatars, the hero panel, the "added for you" badge.
    public static let brandTint = color(\.brandTint)
    public static let background = color(\.background)
    public static let surface = color(\.surface)
    public static let surfaceMuted = color(\.surfaceMuted)
    public static let surfaceSubtle = color(\.surfaceSubtle)
    public static let border = color(\.border)
    public static let borderStrong = color(\.borderStrong)
    /// Unchecked radio/checkbox rings and the off track of a switch.
    public static let control = color(\.control)
    public static let textPrimary = color(\.textPrimary)
    public static let textSecondary = color(\.textSecondary)
    /// Chevrons and decorative icons only, never text.
    public static let textTertiary = color(\.textTertiary)
    public static let tip = color(\.tip)
    public static let tipOn = color(\.tipOn)
    public static let tipIcon = color(\.tipIcon)
    public static let highlight = color(\.highlight)
    public static let scrim = color(\.scrim)
    public static let success = color(\.success)
    public static let warning = color(\.warning)
    public static let danger = color(\.danger)
    public static let info = color(\.info)

    /// PDF accent presets (the business accent colour is one of these).
    public static let accentPresets: [String] = tokens.pdf.accentPresets

    /// Shadows use the ink colour (`design.md` §2.1).
    static let shadow = Color(red: 42 / 255, green: 33 / 255, blue: 53 / 255)

    // MARK: Spacing, radii, layout

    public enum Space {
        public static let xxs = CGFloat(Theme.tokens.space["xxs"] ?? 2)
        public static let xs = CGFloat(Theme.tokens.space["xs"] ?? 4)
        public static let s = CGFloat(Theme.tokens.space["s"] ?? 8)
        public static let m = CGFloat(Theme.tokens.space["m"] ?? 12)
        public static let l = CGFloat(Theme.tokens.space["l"] ?? 16)
        public static let xl = CGFloat(Theme.tokens.space["xl"] ?? 24)
        public static let xxl = CGFloat(Theme.tokens.space["xxl"] ?? 32)
    }

    public enum Radius {
        public static let s = CGFloat(Theme.tokens.radius["s"] ?? 6)
        public static let m = CGFloat(Theme.tokens.radius["m"] ?? 10)
        public static let l = CGFloat(Theme.tokens.radius["l"] ?? 16)
        public static let input = CGFloat(Theme.tokens.radius["input"] ?? 14)
        public static let button = CGFloat(Theme.tokens.radius["button"] ?? 16)
        public static let card = CGFloat(Theme.tokens.radius["card"] ?? 20)
        public static let sheet = CGFloat(Theme.tokens.radius["sheet"] ?? 26)
        public static let hero = CGFloat(Theme.tokens.radius["hero"] ?? 24)
    }

    public enum Layout {
        public static let minTouchTarget = CGFloat(Theme.tokens.layout["minTouchTarget"] ?? 44)
        /// Forms and text never grow wider than this, even on a 13-inch iPad.
        public static let maxReadableWidth = CGFloat(Theme.tokens.layout["maxReadableWidth"] ?? 720)
        public static let primaryButtonHeight = CGFloat(Theme.tokens.layout["primaryButtonHeight"] ?? 56)
        public static let inputHeight = CGFloat(Theme.tokens.layout["inputHeight"] ?? 50)
        public static let screenGutter = CGFloat(Theme.tokens.layout["screenGutter"] ?? 20)
    }

    // MARK: Text styles (`tokens.json` "type")

    /// The type roles, each a bundled font at its token size, scaled with Dynamic Type relative to a system style.
    public enum Fonts {
        public static let largeTitle = font("largeTitle", relativeTo: .largeTitle)
        public static let title = font("title", relativeTo: .title)
        public static let title3 = font("title3", relativeTo: .title3)
        public static let headline = font("headline", relativeTo: .headline)
        public static let body = font("body", relativeTo: .body)
        public static let rowTitle = font("rowTitle", relativeTo: .body)
        public static let button = font("button", relativeTo: .headline)
        public static let callout = font("callout", relativeTo: .callout)
        public static let subhead = font("subhead", relativeTo: .subheadline)
        public static let footnote = font("footnote", relativeTo: .footnote)
        public static let caption = font("caption", relativeTo: .caption)
        public static let overline = font("overline", relativeTo: .footnote)
        public static let amountLarge = font("amountLarge", relativeTo: .title).monospacedDigit()
        public static let amount = font("amount", relativeTo: .body).monospacedDigit()

        /// The tracking of a role, in points (largeTitle −0.6, title −0.4, overline 0.6).
        public static func tracking(_ role: String) -> CGFloat { CGFloat(Theme.tokens.type[role]?.tracking ?? 0) }

        /// A family font at a size, for the few places that draw at a fixed size (the welcome illustration).
        static func display(_ size: CGFloat) -> Font { .custom(AppFonts.displayFamily, fixedSize: size).weight(.bold) }

        private static func font(_ role: String, relativeTo style: Font.TextStyle) -> Font {
            AppFonts.registerIfNeeded()
            let spec = Theme.tokens.type[role] ?? DesignTokens.TextStyle(font: "text", size: 16, weight: "regular")
            let family = spec.font == "display" ? AppFonts.displayFamily : AppFonts.textFamily
            return Font.custom(family, size: CGFloat(spec.size), relativeTo: style).weight(spec.fontWeight)
        }
    }

    private static func color(_ key: KeyPath<DesignTokens.Palette, String>) -> Color {
        let light = UIColor(hex: tokens.color.light[keyPath: key])
        let dark = UIColor(hex: tokens.color.dark[keyPath: key])
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// A UIKit colour from the palette, for UIKit appearance (navigation and tab bars).
    static func uiColor(_ key: KeyPath<DesignTokens.Palette, String>) -> UIColor {
        let light = UIColor(hex: tokens.color.light[keyPath: key])
        let dark = UIColor(hex: tokens.color.dark[keyPath: key])
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    /// A colour from `#RRGGBB` (business accent colours).
    public static func color(hex: String) -> Color {
        Color(uiColor: UIColor(hex: hex))
    }
}

/// The bundled UI fonts (`spec/design/fonts`, OFL), registered for this process once.
public enum AppFonts {
    static let displayFamily = Theme.tokens.fonts?.display.family ?? "Bricolage Grotesque"
    static let textFamily = Theme.tokens.fonts?.text.family ?? "Figtree"

    private static let registration: Bool = {
        let names = (Theme.tokens.fonts.map { [$0.display, $0.text] } ?? []).flatMap { Array($0.files.values) }
        let urls = names.map { SpecResources.url("design/fonts/\($0).ttf") }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
        return true
    }()

    /// Safe to call often; only the first call registers.
    public static func registerIfNeeded() {
        _ = registration
    }

    /// A UIKit font of a family at a weight, scaled for Dynamic Type like `style` (navigation and tab bars).
    static func uiFont(family: String, weight: UIFont.Weight, size: CGFloat, relativeTo style: UIFont.TextStyle)
        -> UIFont {
        registerIfNeeded()
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size))
    }
}

/// The parts of `tokens.json` the app reads.
struct DesignTokens: Decodable, Sendable {
    struct Palette: Decodable, Sendable {
        let brand, brandPressed, brandOn, brandTint, background, surface, surfaceMuted, surfaceSubtle: String
        let border, borderStrong, control, textPrimary, textSecondary, textTertiary: String
        let tip, tipOn, tipIcon, highlight, scrim, success, warning, danger, info: String
    }

    struct Colors: Decodable, Sendable {
        let light: Palette
        let dark: Palette
    }

    struct FontFamily: Decodable, Sendable {
        let family: String
        let files: [String: String]
    }

    struct FontRoles: Decodable, Sendable {
        let display: FontFamily
        let text: FontFamily
    }

    struct TextStyle: Decodable, Sendable {
        let font: String
        let size: Double
        let weight: String
        var tracking: Double?
        var uppercase: Bool?

        init(font: String, size: Double, weight: String) {
            self.font = font
            self.size = size
            self.weight = weight
        }

        var fontWeight: Font.Weight {
            switch weight {
            case "medium": .medium
            case "semibold": .semibold
            case "bold": .bold
            default: .regular
            }
        }
    }

    struct PDF: Decodable, Sendable {
        let accentPresets: [String]
    }

    let color: Colors
    let fonts: FontRoles?
    let type: [String: TextStyle]
    let space: [String: Double]
    let radius: [String: Double]
    let layout: [String: Double]
    let pdf: PDF

    static func bundled() throws -> DesignTokens {
        try JSONDecoder().decode(DesignTokens.self, from: SpecResources.data("design/tokens.json"))
    }

    /// Used only if the bundled tokens cannot be read (a packaging bug caught by tests).
    static let fallback: DesignTokens = {
        let palette = Palette(brand: "#C2482A", brandPressed: "#9E3820", brandOn: "#FFFFFF", brandTint: "#FDE3D8",
                              background: "#FFF5EF", surface: "#FFFFFF", surfaceMuted: "#F8ECE5",
                              surfaceSubtle: "#FBE9E0", border: "#EEDFD6", borderStrong: "#E2CFC4",
                              control: "#CDB3A6", textPrimary: "#2A2135", textSecondary: "#6B5F72",
                              textTertiary: "#9A8C92", tip: "#E3F0FF", tipOn: "#1D3A5F", tipIcon: "#2C5C94",
                              highlight: "#8EC5FF", scrim: "#5A4A55", success: "#126B33", warning: "#9A4A0B",
                              danger: "#B91C1C", info: "#1D4ED8")
        return DesignTokens(color: Colors(light: palette, dark: palette), fonts: nil, type: [:], space: [:],
                            radius: [:], layout: [:], pdf: PDF(accentPresets: ["#1F6FEB"]))
    }()
}

extension UIColor {
    /// `#RRGGBB`; anything else is mid grey.
    convenience init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self.init(white: 0.5, alpha: 1)
            return
        }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
