import SwiftUI
import UIKit

/// The theme where SwiftUI hands drawing to UIKit: navigation-bar titles, tab-bar labels and segmented controls use
/// the bundled fonts. Applied once, before the first window appears.
@MainActor
enum ThemeAppearance {
    private static var applied = false

    static func apply() {
        guard !applied else { return }
        applied = true
        AppFonts.registerIfNeeded()
        let display = AppFonts.displayFamily, text = AppFonts.textFamily
        let ink = Theme.uiColor(\.textPrimary)

        let title: [NSAttributedString.Key: Any] = [
            .font: AppFonts.uiFont(family: text, weight: .bold, size: 17, relativeTo: .headline),
            .foregroundColor: ink,
        ]
        let largeTitle: [NSAttributedString.Key: Any] = [
            .font: AppFonts.uiFont(family: display, weight: .bold, size: 31, relativeTo: .largeTitle),
            .foregroundColor: ink,
            .kern: Theme.Fonts.tracking("largeTitle"),
        ]
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.titleTextAttributes = title
        standard.largeTitleTextAttributes = largeTitle
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.titleTextAttributes = title
        edge.largeTitleTextAttributes = largeTitle
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = edge
        bar.compactScrollEdgeAppearance = edge

        let tabFont = AppFonts.uiFont(family: text, weight: .semibold, size: 11, relativeTo: .caption2)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabFont], for: .normal)
        UITabBar.appearance().unselectedItemTintColor = Theme.uiColor(\.textSecondary) // `design.md` §5: inactive tabs

        let segment = UISegmentedControl.appearance()
        segment.setTitleTextAttributes(
            [.font: AppFonts.uiFont(family: text, weight: .semibold, size: 14, relativeTo: .subheadline)], for: .normal)
        segment.setTitleTextAttributes(
            [.font: AppFonts.uiFont(family: text, weight: .bold, size: 14, relativeTo: .subheadline)], for: .selected)
    }
}

/// A grouped form on the theme's ground: the peach background with white (surface) sections. Use it where a screen
/// would use `Form`.
struct ThemedForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            Group { content }
                .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }
}

extension View {
    /// A list on the theme's ground (rows keep their own background).
    func themedList() -> some View {
        scrollContentBackground(.hidden).background(Theme.background)
    }

    /// The app's base text style, ink colour and tint, set once at the root.
    func themedRoot() -> some View {
        font(Theme.Fonts.body)
            .tint(Theme.brand)
    }
}
