import InvoiceCore
import SwiftUI
import UIKit

/// Colours, spacing, radii and layout sizes from `spec/design/tokens.json`, shared with Android's
/// `:core:designsystem`. Text uses the system text styles so Dynamic Type works everywhere.
public enum Theme {
    static let tokens = (try? DesignTokens.bundled()) ?? DesignTokens.fallback

    // MARK: Colours (light/dark pairs)

    public static let brand = color(\.brand)
    public static let brandOn = color(\.brandOn)
    public static let background = color(\.background)
    public static let surface = color(\.surface)
    public static let surfaceMuted = color(\.surfaceMuted)
    public static let border = color(\.border)
    public static let textPrimary = color(\.textPrimary)
    public static let textSecondary = color(\.textSecondary)
    public static let textTertiary = color(\.textTertiary)
    public static let success = color(\.success)
    public static let warning = color(\.warning)
    public static let danger = color(\.danger)
    public static let info = color(\.info)

    /// PDF accent presets (the business accent colour is one of these).
    public static let accentPresets: [String] = tokens.pdf.accentPresets

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
    }

    public enum Layout {
        public static let minTouchTarget = CGFloat(Theme.tokens.layout["minTouchTarget"] ?? 44)
        /// Forms and text never grow wider than this, even on a 13-inch iPad.
        public static let maxReadableWidth = CGFloat(Theme.tokens.layout["maxReadableWidth"] ?? 720)
    }

    private static func color(_ key: KeyPath<DesignTokens.Palette, String>) -> Color {
        let light = UIColor(hex: tokens.color.light[keyPath: key])
        let dark = UIColor(hex: tokens.color.dark[keyPath: key])
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// A colour from `#RRGGBB` (business accent colours).
    public static func color(hex: String) -> Color {
        Color(uiColor: UIColor(hex: hex))
    }
}

/// The parts of `tokens.json` the app reads.
struct DesignTokens: Decodable, Sendable {
    struct Palette: Decodable, Sendable {
        let brand, brandOn, background, surface, surfaceMuted, border: String
        let textPrimary, textSecondary, textTertiary, success, warning, danger, info: String
    }

    struct Colors: Decodable, Sendable {
        let light: Palette
        let dark: Palette
    }

    struct PDF: Decodable, Sendable {
        let accentPresets: [String]
    }

    let color: Colors
    let space: [String: Double]
    let radius: [String: Double]
    let layout: [String: Double]
    let pdf: PDF

    static func bundled() throws -> DesignTokens {
        try JSONDecoder().decode(DesignTokens.self, from: SpecResources.data("design/tokens.json"))
    }

    /// Used only if the bundled tokens cannot be read (a packaging bug caught by tests).
    static let fallback: DesignTokens = {
        let palette = Palette(brand: "#1A5FD6", brandOn: "#FFFFFF", background: "#F7F8FA", surface: "#FFFFFF",
                              surfaceMuted: "#EEF1F5", border: "#D8DEE6", textPrimary: "#111827",
                              textSecondary: "#4B5563", textTertiary: "#5B6371", success: "#126B33",
                              warning: "#9A4A0B", danger: "#B91C1C", info: "#1D4ED8")
        return DesignTokens(color: Colors(light: palette, dark: palette), space: [:], radius: [:], layout: [:],
                            pdf: PDF(accentPresets: ["#1F6FEB"]))
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
