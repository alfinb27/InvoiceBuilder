import InvoiceCore
import SwiftUI

/// A form row: a caption label above a text field, with the field's problem underneath. VoiceOver reads the label,
/// the value and the problem as one element.
///
/// `focus`/`focusValue` put `.focused` on the text field itself: on the container it only works from iOS 27, so
/// Return-to-next-field (`onSubmit { focus = … }`) did nothing on iOS 18–26.
struct FormTextField<Focus: Hashable>: View {
    let title: String
    @Binding var text: String
    var prompt: String?
    var issue: String?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var contentType: UITextContentType?
    var autocorrect = true
    var axis: Axis = .horizontal
    var focus: FocusState<Focus?>.Binding?
    var focusValue: Focus?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title)
                .font(Theme.Fonts.footnote)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            TextField(title, text: keyboard == .decimalPad ? $text.decimalPadInput() : $text,
                      prompt: Text(prompt ?? ""), axis: axis)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .textContentType(contentType)
                .autocorrectionDisabled(!autocorrect)
                .lineLimit(axis == .vertical ? 1...6 : 1...1)
                .modifier(FieldFocus(focus: focus, value: focusValue))
                .accessibilityLabel(title)
                .accessibilityHint(issue ?? "")
            if let issue {
                IssueText(message: issue)
            }
        }
        .padding(.vertical, Theme.Space.xxs)
    }
}

extension FormTextField where Focus == Never {
    /// A field nothing moves focus to.
    init(title: String, text: Binding<String>, prompt: String? = nil, issue: String? = nil,
         keyboard: UIKeyboardType = .default, capitalization: TextInputAutocapitalization = .sentences,
         contentType: UITextContentType? = nil, autocorrect: Bool = true, axis: Axis = .horizontal) {
        self.init(title: title, text: text, prompt: prompt, issue: issue, keyboard: keyboard,
                  capitalization: capitalization, contentType: contentType, autocorrect: autocorrect, axis: axis,
                  focus: nil, focusValue: nil)
    }
}

/// `.focused(_:equals:)` when there is a binding to focus with.
private struct FieldFocus<Focus: Hashable>: ViewModifier {
    let focus: FocusState<Focus?>.Binding?
    let value: Focus?

    func body(content: Content) -> some View {
        if let focus, let value {
            content.focused(focus, equals: value)
        } else {
            content
        }
    }
}

/// A red problem message under a field.
struct IssueText: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(Theme.Fonts.footnote)
            .foregroundStyle(Theme.danger)
            .accessibilityLabel("Problem: \(message)")
    }
}

/// A green confirmation under a field (e.g. a valid GSTIN and its state).
struct SuccessText: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(Theme.Fonts.footnote)
            .foregroundStyle(Theme.success)
    }
}

/// A small rounded tag such as "B2B" or "Archived". On a selected (highlighted) list row it turns white.
struct Tag: View {
    let text: String
    var color: Color = Theme.info
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let onHighlight = prominence == .increased
        Text(text)
            .font(Theme.Fonts.caption.weight(.semibold))
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, Theme.Space.xxs)
            .foregroundStyle(onHighlight ? Color.white : color)
            .background(onHighlight ? Color.white.opacity(0.22) : color.opacity(0.12), in: Capsule())
    }
}

extension View {
    /// Caps the width for readable forms on wide iPad windows, centred.
    func readableWidth() -> some View {
        frame(maxWidth: Theme.Layout.maxReadableWidth).frame(maxWidth: .infinity)
    }
}

/// A label and a value (usually an amount) side by side, stacked at accessibility text sizes so amounts never wrap
/// in the middle of a number.
struct AdaptiveRow<Label: View, Value: View>: View {
    var alignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder let label: Label
    @ViewBuilder let value: Value
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                label
                value
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: alignment, spacing: Theme.Space.m) {
                label
                Spacer(minLength: Theme.Space.s)
                value.layoutPriority(1)
            }
        }
    }
}

// MARK: - Decimal pads

/// A decimal pad types the device locale's decimal separator, while the spec parsers (`spec/setup.md` §11) read `.`
/// as the decimal point and drop `,` as a grouping mark. On comma-decimal locales a typed `,` becomes `.` as it is
/// typed, so "12,5" is 12.5, never 125.
enum DecimalPadText {
    static func normalized(_ text: String, locale: Locale = .current) -> String {
        guard locale.decimalSeparator == "," else { return text }
        return text.replacingOccurrences(of: ",", with: ".")
    }
}

extension Binding where Value == String {
    /// This binding with the locale's decimal separator turned into `.` on the way in.
    func decimalPadInput(locale: Locale = .current) -> Binding<String> {
        Binding(get: { wrappedValue }, set: { wrappedValue = DecimalPadText.normalized($0, locale: locale) })
    }
}

// MARK: - Messages

/// Human text for `FieldIssue`s. `field` is the field's name as shown on screen.
enum IssueMessages {
    static func text(_ issue: FieldIssue, field: String, taxIDName: String = "tax ID", maxLength: Int? = nil)
        -> String {
        switch issue {
        case .required:
            "Enter the \(field.lowercased())"
        case .invalid(let rule, let error):
            rule.message(error)
        case .invalidTaxID(.format):
            "This doesn't look like a \(taxIDName). Check for missing or extra characters."
        case .invalidTaxID(.checksum):
            "This \(taxIDName) has a typo: its last character doesn't match."
        case .invalidTaxID(.unknownRegion):
            "The first two digits of this \(taxIDName) aren't a state code."
        case .invalidNumber(.tooManyDecimals):
            "Too many decimal places"
        case .invalidNumber(.tooLarge):
            "That number is too large"
        case .invalidNumber:
            "Enter a number, like 1250.50"
        case .outOfRange(let range):
            "Enter a number from \(range.lowerBound) to \(range.upperBound)"
        case .invalidPattern(let issues):
            issues.first.map(patternMessage) ?? "Check the pattern"
        case .invalidNumbering(.numberTooLong):
            "Numbers made with this pattern would be longer than \(maxLength.map(String.init) ?? "allowed") characters"
        case .invalidNumbering(.numberInvalidChars):
            "Numbers can only use letters, digits, / and -"
        case .alreadyIssued(let highest):
            "Number \(highest) has already been issued. Start at \(highest + 1) or later."
        case .exceedsLineAmount:
            "The discount is more than the line amount"
        }
    }

    static func patternMessage(_ issue: NumberingPatternIssue) -> String {
        switch issue {
        case .missingSequence: "Add {seq:4} so every number is different"
        case .multipleSequences: "Use {seq:N} only once"
        case .unknownToken(let token): "\(token) isn't a pattern token"
        case .invalidSequenceWidth(let token): "\(token): use a width from 1 to 9, like {seq:4}"
        }
    }
}

extension FieldRule {
    func message(_ error: FieldError) -> String {
        switch self {
        case .email: "Enter an email address like name@example.com"
        case .ifsc: "An IFSC has 11 characters, like SBIN0001234"
        case .upiVpa: "A UPI ID looks like name@bank"
        case .sortCode: "A sort code has 6 digits, like 12-34-56"
        case .iban: error == .checksum ? "This IBAN has a typo: its check digits don't match" : "Check the IBAN"
        case .bic: "A SWIFT/BIC code has 8 or 11 characters"
        case .pan: "A PAN has 10 characters, like ABCDE1234F"
        case .postalCodeIN: "A PIN code has 6 digits"
        case .postalCodeGB: "Enter a UK postcode, like SW1A 1AA"
        case .companyNumberGB: "A company number has 8 characters, like 01234567 or SC123456"
        case .hsnSac: "HSN and SAC codes have 2 to 8 digits"
        }
    }
}

/// A labelled input outside a form (a label above a boxed text field, the problem underneath), as in the setup and
/// "Add an item" screens.
struct BoxedTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String?
    var issue: String?
    var hint: String?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: title)
            TextField(title, text: keyboard == .decimalPad ? $text.decimalPadInput() : $text,
                      prompt: Text(prompt ?? "").foregroundStyle(Theme.textSecondary))
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .focused($isFocused)
                .inputBox(isFocused: isFocused)
                .accessibilityLabel(title)
                .accessibilityHint(issue ?? hint ?? "")
            if let issue {
                IssueText(message: issue)
            } else if let hint {
                Text(hint).font(Theme.Fonts.caption.weight(.regular)).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
