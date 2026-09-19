import Foundation

/// Whole-string matching for the regular expressions written in the spec (tax ID formats, numbering rules,
/// field rules). The patterns use a subset that ICU and JavaScript read the same way.
enum SpecRegex {
    /// True when `pattern` matches all of `text`. An invalid pattern never matches.
    static func matches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        // Require the match to cover the whole input: ICU's `$` also matches before a final line terminator.
        guard let match = regex.firstMatch(in: text, range: range) else { return false }
        return match.range == range
    }
}

extension String {
    /// Removes every whitespace or newline character, including those inside the string.
    var removingWhitespace: String {
        String(unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
    }

    /// Trimmed text, or nil when nothing is left (optional fields store NULL, `spec/setup.md` §1).
    public var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// True when every character is an ASCII digit (and the string is not empty).
    var isASCIIDigits: Bool {
        !isEmpty && utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }
}
