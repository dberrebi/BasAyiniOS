import SwiftUI

enum HebrewNumerals {
    /// Hebrew letter-numbers with geresh / gershayim. 15 and 16 avoid the divine name.
    static func string(_ number: Int) -> String {
        guard number > 0, number < 1000 else { return String(number) }
        if number == 15 { return "ט״ו" }
        if number == 16 { return "ט״ז" }
        let ones = ["", "א", "ב", "ג", "ד", "ה", "ו", "ז", "ח", "ט"]
        let tens = ["", "י", "כ", "ל", "מ", "נ", "ס", "ע", "פ", "צ"]
        let hundreds = ["", "ק", "ר", "ש", "ת", "תק", "תר", "תש", "תת", "תתק"]
        var letters = hundreds[number / 100]
        let rest = number % 100
        if rest == 15 {
            letters += "טו"
        } else if rest == 16 {
            letters += "טז"
        } else {
            letters += tens[rest / 10]
            letters += ones[rest % 10]
        }
        if letters.count <= 1 {
            return letters + "׳"
        }
        var characters = Array(letters)
        characters.insert("״", at: characters.count - 1)
        return String(characters)
    }
}

enum HebrewText {
    /// Marks that write an abbreviation (חז"ל) or a number (ל"ב). Search ignores them,
    /// like the index in scripts/build_data.py, so חזל and חז"ל find the same places.
    static let quoteMarks: Set<Character> = ["\"", "'", "׳", "״", "`", "’", "‘", "”", "“"]

    static func containsHebrew(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0590...0x05FF).contains($0.value) }
    }

    static func isHebrewLetter(_ scalar: Unicode.Scalar) -> Bool {
        (0x05D0...0x05EA).contains(scalar.value)
    }

    static func number(_ value: Int, language: AppLanguage) -> String {
        language == .he ? HebrewNumerals.string(value) : String(value)
    }

    /// The Hebrew words of a query: points, cantillation and quote marks dropped. Anything
    /// else that is not a Hebrew letter separates words.
    static func searchTerms(_ raw: String) -> [String] {
        var words: [String] = []
        var current = ""
        for scalar in stripNikud(raw).unicodeScalars {
            if isHebrewLetter(scalar) {
                current.unicodeScalars.append(scalar)
            } else if quoteMarks.contains(Character(scalar)) {
                continue
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }

    /// FTS5 query: each word is a prefix, and every word must match.
    static func ftsQuery(_ terms: [String]) -> String {
        terms.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    static func ftsQuery(_ raw: String) -> String {
        ftsQuery(searchTerms(raw))
    }

    static func stripNikud(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x0591...0x05BD).contains(value) { continue }
            switch value {
            case 0x05BF, 0x05C1, 0x05C2, 0x05C4, 0x05C5, 0x05C7:
                continue
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    static func plain(_ markup: String) -> String {
        segments(in: markup).map(\.text).joined()
            .replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func preview(_ paragraph: Paragraph, length: Int = 90) -> String {
        let text = plain(paragraph.body)
        if text.count <= length { return text }
        let end = text.index(text.startIndex, offsetBy: length)
        return String(text[..<end]) + "…"
    }

    /// A short passage around the first search word, cut at spaces. The words are matched
    /// as prefixes at the start of a word, ignoring quote marks, as the index matches them.
    static func snippet(_ markup: String, terms: [String], before: Int = 36, after: Int = 110) -> String {
        let characters = Array(plain(markup))
        guard !characters.isEmpty else { return "" }
        // The text without quote marks, and for each of its characters the position in the original.
        var folded: [Character] = []
        var origin: [Int] = []
        for (index, character) in characters.enumerated() where !quoteMarks.contains(character) {
            folded.append(character)
            origin.append(index)
        }
        var hit: Int?
        for term in terms {
            let needle = Array(term)
            guard !needle.isEmpty, needle.count <= folded.count else { continue }
            for start in 0...(folded.count - needle.count) {
                if start > 0, folded[start - 1].unicodeScalars.allSatisfy(isHebrewLetter) { continue }
                if Array(folded[start..<(start + needle.count)]) == needle {
                    let position = origin[start]
                    if hit == nil || position < hit! { hit = position }
                    break
                }
            }
        }
        guard let hit else {
            return characters.count <= after ? String(characters) : String(characters[..<after]) + "…"
        }
        var lower = max(0, hit - before)
        var upper = min(characters.count, hit + after)
        if lower > 0 {
            while lower < hit, characters[lower - 1] != " " { lower += 1 }
        }
        if upper < characters.count {
            while upper > hit + 1, characters[upper] != " " { upper -= 1 }
        }
        let body = String(characters[lower..<upper]).trimmingCharacters(in: .whitespaces)
        return (lower > 0 ? "…" : "") + body + (upper < characters.count ? "…" : "")
    }

    static func attributed(
        _ markup: String,
        size: CGFloat,
        textColor: Color,
        emphasisColor: Color
    ) -> AttributedString {
        var result = AttributedString()
        for segment in segments(in: markup) {
            guard !segment.text.isEmpty else { continue }
            var part = AttributedString(segment.text)
            part.font = Theme.hebrewFont(size: size, emphasis: segment.emphasis)
            part.foregroundColor = segment.emphasis ? emphasisColor : textColor
            result += part
        }
        return result
    }

    private struct Segment {
        var text: String
        var emphasis: Bool
    }

    /// The edition sets the opening word of a paragraph, and some quotations, in `<b>`.
    private static func segments(in markup: String) -> [Segment] {
        var output: [Segment] = []
        var buffer = ""
        var emphasis = false
        var index = markup.startIndex
        while index < markup.endIndex {
            if markup[index] == "<" {
                let rest = markup[index...]
                if rest.hasPrefix("<b>") {
                    flush(&buffer, emphasis: emphasis, into: &output)
                    emphasis = true
                    index = markup.index(index, offsetBy: 3)
                    continue
                }
                if rest.hasPrefix("</b>") {
                    flush(&buffer, emphasis: emphasis, into: &output)
                    emphasis = false
                    index = markup.index(index, offsetBy: 4)
                    continue
                }
            }
            buffer.append(markup[index])
            index = markup.index(after: index)
        }
        flush(&buffer, emphasis: emphasis, into: &output)
        return output
    }

    private static func flush(_ buffer: inout String, emphasis: Bool, into output: inout [Segment]) {
        if !buffer.isEmpty {
            output.append(Segment(text: buffer, emphasis: emphasis))
            buffer = ""
        }
    }
}

extension View {
    /// Marks Hebrew content so VoiceOver reads it with a Hebrew voice, also when the
    /// interface is in English. SwiftUI takes a text's speech language from the locale
    /// in its environment and has no per-view accessibility language, so apply this to
    /// the Hebrew text alone, not to a row that also holds interface labels.
    func hebrewSpeech() -> some View {
        environment(\.locale, Locale(identifier: "he"))
    }
}
