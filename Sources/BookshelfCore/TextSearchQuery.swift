import Foundation

/// A search projection only: quotations and PDF text always come from the original string.
struct TextSearchQuery {
    private let term: String
    private let compactTerm: String
    private let ignoreWhitespace: Bool
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    private static let ignored = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "\u{200B}\u{FEFF}\u{00AD}"))

    init(_ query: String, ignoreWhitespace: Bool) {
        term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        compactTerm = String(query.unicodeScalars.filter { !Self.ignored.contains($0) })
        self.ignoreWhitespace = ignoreWhitespace
    }

    var isEmpty: Bool { ignoreWhitespace ? compactTerm.isEmpty : term.isEmpty }

    func range(in text: String) -> Range<String.Index>? {
        guard !isEmpty else { return nil }
        // Prefer a literal occurrence if one exists, preserving normal word boundaries when possible.
        if let literal = text.range(of: term, options: Self.options) { return literal }
        guard ignoreWhitespace else { return nil }

        var compact = String.UnicodeScalarView()
        var sourceUnits: [NSRange] = []
        var offset = 0
        for scalar in text.unicodeScalars {
            let length = scalar.value > 0xFFFF ? 2 : 1
            if !Self.ignored.contains(scalar) {
                compact.append(scalar)
                // NSString search returns UTF-16 offsets, including surrogate pairs and decomposed text.
                sourceUnits.append(contentsOf: repeatElement(NSRange(location: offset, length: length), count: length))
            }
            offset += length
        }
        let match = (String(compact) as NSString).range(of: compactTerm, options: Self.options)
        guard match.location != NSNotFound, match.length > 0 else { return nil }
        let start = sourceUnits[match.location].location
        let end = NSMaxRange(sourceUnits[NSMaxRange(match) - 1])
        let original = (text as NSString).rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
        return Range(original, in: text)
    }
}
