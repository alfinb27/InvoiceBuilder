import SwiftUI

// The components of `docs/design/design.md` §5, drawn from the theme tokens. Android: `:core:designsystem`
// `Components.kt`, same names.

// MARK: - Buttons

/// The large full-width brand button (height 56, radius 16), optionally with a trailing arrow.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var trailingArrow = false
    var isBusy = false
    var isEnabled = true
    let action: () -> Void

    init(title: String, systemImage: String? = nil, trailingArrow: Bool = false, isBusy: Bool = false,
         isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.trailingArrow = trailingArrow
        self.isBusy = isBusy
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: Theme.Space.s) {
                    if let systemImage { Image(systemName: systemImage).fontWeight(.bold) }
                    Text(title)
                    if trailingArrow { Image(systemName: "arrow.right").fontWeight(.bold) }
                }
                .opacity(isBusy ? 0 : 1)
                if isBusy { ProgressView().tint(Theme.brandOn) }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isBusy || !isEnabled)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.button)
            .foregroundStyle(Theme.brandOn)
            .frame(maxWidth: .infinity, minHeight: Theme.Layout.primaryButtonHeight)
            .padding(.horizontal, Theme.Space.l)
            .background(configuration.isPressed ? Theme.brandPressed : Theme.brand,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
    }
}

/// A brand-coloured text button with no fill, at least 44 high ("I've used this app before", "Keep as draft").
struct TextLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.callout.weight(.semibold))
            .foregroundStyle(configuration.isPressed ? Theme.brandPressed : Theme.brand)
            .frame(minHeight: Theme.Layout.minTouchTarget)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == TextLinkButtonStyle {
    static var textLink: TextLinkButtonStyle { TextLinkButtonStyle() }
}

/// A quiet secondary button: surface fill, strong border, primary text.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.rowTitle)
            .foregroundStyle(Theme.textPrimary)
            .frame(minHeight: Theme.Layout.minTouchTarget)
            .padding(.horizontal, Theme.Space.l)
            .background(configuration.isPressed ? Theme.surfaceMuted : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.input))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.input).stroke(Theme.borderStrong))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.input))
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Selection

/// One choice of a radio group drawn as a card: an icon tile, a title and hint, and a radio ring. Selected: a 2 pt
/// brand border and a filled dot (shown by weight and fill as well as colour).
struct SelectableCard: View {
    let title: String
    var hint: String?
    /// Short text in the icon tile ("IN", "UK", "+").
    var badge: String?
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m + 2) {
                if badge != nil || systemImage != nil {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Theme.brandTint)
                        if let systemImage {
                            Image(systemName: systemImage).fontWeight(.semibold)
                        } else if let badge {
                            Text(badge).font(Theme.Fonts.subhead.weight(.bold))
                        }
                    }
                    .foregroundStyle(Theme.brandPressed)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.Fonts.body.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    if let hint {
                        Text(hint).font(Theme.Fonts.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RadioMark(isSelected: isSelected)
            }
            .padding(.horizontal, Theme.Space.m + 2)
            .padding(.vertical, Theme.Space.m)
            .frame(minHeight: 68)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l)
                .strokeBorder(isSelected ? Theme.brand : Theme.border, lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The ring of a radio choice, filled when selected.
struct RadioMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(isSelected ? Theme.brand : Theme.control, lineWidth: 2)
            if isSelected { Circle().fill(Theme.brand).frame(width: 10, height: 10) }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// A single-choice pill (44 high). Off: surface with a strong border; on: brand tint with a 2 pt brand border.
struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.subhead.weight(fillsWidth ? .bold : .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Space.m + 2)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: Theme.Layout.minTouchTarget)
                .background(isSelected ? Theme.brandTint : Theme.surface,
                            in: RoundedRectangle(cornerRadius: fillsWidth ? 12 : 22))
                .overlay(RoundedRectangle(cornerRadius: fillsWidth ? 12 : 22)
                    .strokeBorder(isSelected ? Theme.brand : Theme.borderStrong, lineWidth: isSelected ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Lays chips out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = Theme.Space.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - Cards and sections

/// A surface card: white (surface) fill, radius 20, a 1 pt border.
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = Theme.Space.l
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.border))
    }
}

/// A numbered question card of the guided builder: a 24 pt brand circle with the step number and the question.
struct NumberedCard<Trailing: View, Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        SurfaceCard(padding: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.s + 2) {
                    Text("\(number)")
                        .font(Theme.Fonts.footnote.weight(.bold))
                        .foregroundStyle(Theme.brandOn)
                        .frame(width: 24, height: 24)
                        .background(Theme.brand, in: Circle())
                        .accessibilityHidden(true)
                    Text(title)
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("Step \(number): \(title)")
                    trailing
                }
                content
            }
        }
    }
}

extension NumberedCard where Trailing == EmptyView {
    init(number: Int, title: String, @ViewBuilder content: () -> Content) {
        self.number = number
        self.title = title
        trailing = EmptyView()
        self.content = content()
    }
}

/// An uppercase section label ("ONCE YOU START SENDING").
struct Overline: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Fonts.overline)
            .tracking(Theme.Fonts.tracking("overline"))
            .foregroundStyle(Theme.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A screen's display title with a one-line reason under it.
struct ScreenHeader: View {
    let title: String
    var subtitle: String?
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title)
                .font(large ? Theme.Fonts.largeTitle : Theme.Fonts.title)
                .tracking(Theme.Fonts.tracking(large ? "largeTitle" : "title"))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Progress

/// Equal bars, one per stage, with the stage names under them; the current stage is brand and bold.
struct SteppedProgress: View {
    let stages: [String]
    let current: Int

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(index <= current ? Theme.brand : Theme.border)
                        .frame(height: 5)
                    Text(stage)
                        .font(Theme.Fonts.caption.weight(index == current ? .bold : .medium))
                        .foregroundStyle(index == current ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(stages.count): \(stages[safe: current] ?? "")")
    }
}

/// A 6 pt bar with an "n of m" label.
struct ProgressBar: View {
    let value: Int
    let total: Int

    var body: some View {
        HStack(spacing: Theme.Space.s + 2) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.border)
                    Capsule().fill(Theme.brand)
                        .frame(width: proxy.size.width * CGFloat(value) / CGFloat(max(total, 1)))
                }
            }
            .frame(height: 6)
            Text("\(value) of \(total)")
                .font(Theme.Fonts.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) of \(total) done")
    }
}

// MARK: - Callouts and badges

/// A blue tip or notice: an info (or lock) icon and short text.
struct TipCallout: View {
    let text: Text
    var systemImage = "info.circle"

    init(_ text: String, systemImage: String = "info.circle") {
        self.text = Text(text)
        self.systemImage = systemImage
    }

    init(text: Text, systemImage: String = "info.circle") {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s + 2) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.tipIcon)
                .accessibilityHidden(true)
            text
                .font(Theme.Fonts.footnote)
                .foregroundStyle(Theme.tipOn)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Space.m + 2)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.tip, in: RoundedRectangle(cornerRadius: Theme.Radius.input))
        .accessibilityElement(children: .combine)
    }
}

/// A small pill: brand tint fill, pressed-brand text ("added for you").
struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.brandPressed)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 2)
            .background(Theme.brandTint, in: Capsule())
    }
}

/// Initials in a tinted circle (a client, the business).
struct Avatar: View {
    let name: String
    var size: CGFloat = 40
    var style: Style = .brand

    enum Style { case brand, tip }

    var body: some View {
        Text(Self.initials(name))
            .font(Theme.Fonts.subhead.weight(.bold))
            .foregroundStyle(style == .brand ? Theme.brandPressed : Theme.tipOn)
            .frame(width: size, height: size)
            .background(style == .brand ? Theme.brandTint : Theme.tip, in: Circle())
            .accessibilityHidden(true)
    }

    /// The first letters of the first two words ("Rao Traders" → "RT").
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }
}

// MARK: - Rows and fields

/// A checklist row: a ring (or a filled brand check when done), a title and hint, and a chevron when it opens
/// something. Done rows are struck through.
struct ChecklistRow: View {
    let title: String
    var hint: String?
    let isDone: Bool
    var action: (() -> Void)?

    var body: some View {
        let row = HStack(spacing: Theme.Space.m) {
            ZStack {
                if isDone {
                    Circle().fill(Theme.brand)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.brandOn)
                } else {
                    Circle().strokeBorder(Theme.control, lineWidth: 2)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(isDone ? Theme.Fonts.callout : Theme.Fonts.rowTitle)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? Theme.textSecondary : Theme.textPrimary)
                if let hint, !isDone {
                    Text(hint).font(Theme.Fonts.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if action != nil, !isDone {
                Image(systemName: "chevron.right").font(Theme.Fonts.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary).accessibilityHidden(true)
            }
        }
        .frame(minHeight: isDone ? 52 : 60)
        .contentShape(Rectangle())
        Group {
            if let action, !isDone {
                Button(action: action) { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? "Done" : "Not done")
    }
}

/// A row with a switch whose hint changes with its state.
struct SwitchRow: View {
    let title: String
    let hintOn: String
    let hintOff: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.rowTitle).foregroundStyle(Theme.textPrimary)
                Text(isOn ? hintOn : hintOff).font(Theme.Fonts.caption.weight(.regular))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .tint(Theme.brand)
        .padding(.horizontal, Theme.Space.m + 2)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.input))
    }
}

/// An input-shaped box with − / value / + ; the value can also be typed (decimal quantities).
struct QuantityStepper: View {
    @Binding var text: String
    let decrement: () -> Void
    let increment: () -> Void
    var accessibilityName = "Quantity"

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Fewer", action: decrement)
            TextField(accessibilityName, text: $text.decimalPadInput())
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(Theme.Fonts.button)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityLabel(accessibilityName)
            stepButton("plus", label: "More", action: increment)
        }
        .padding(.horizontal, 3)
        .frame(height: Theme.Layout.inputHeight)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.input))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.input).strokeBorder(Theme.borderStrong, lineWidth: 1.5))
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The input look: 50 high, radius 14, a 1.5 pt strong border (2 pt brand while focused).
struct InputBox: ViewModifier {
    var isFocused = false

    func body(content: Content) -> some View {
        content
            .font(Theme.Fonts.body)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Space.m + 2)
            .frame(minHeight: Theme.Layout.inputHeight)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.input))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.input)
                .strokeBorder(isFocused ? Theme.brand : Theme.borderStrong, lineWidth: isFocused ? 2 : 1.5))
    }
}

extension View {
    func inputBox(isFocused: Bool = false) -> some View { modifier(InputBox(isFocused: isFocused)) }
}

/// A field label above an input ("What did you sell?"), with an optional hint below.
struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text).font(Theme.Fonts.subhead.weight(.bold)).foregroundStyle(Theme.textPrimary)
            .accessibilityHidden(true)
    }
}

/// A money tile before there is any money: a dashed border, the amount in the display face and a label.
struct EmptyStatTile: View {
    let amount: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(amount).font(Theme.Fonts.title3).foregroundStyle(Theme.textPrimary).lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(Theme.Fonts.caption.weight(.regular)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.s + 2)
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l)
            .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .accessibilityElement(children: .combine)
    }
}

/// A money tile with a value: the amount in the display face and a label.
struct StatTile: View {
    let amount: String
    let label: String
    var emphasis: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(amount).font(Theme.Fonts.title3.monospacedDigit()).foregroundStyle(emphasis ?? Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(Theme.Fonts.caption.weight(.regular)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.s + 2)
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l).strokeBorder(Theme.border))
        .accessibilityElement(children: .combine)
    }
}
