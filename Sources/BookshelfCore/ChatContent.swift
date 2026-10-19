import Foundation

public struct ChatContentBlock: Identifiable, Equatable, Sendable {
    public let id: Int
    public let kind: String
    public let source: String
    public let label: String
    public let complete: Bool
}

/// Preserve fenced content before inline Markdown processing can discard its boundaries.
public enum ChatContent {
    /// Foundation Markdown treats paired single tildes as strikethrough, including
    /// Korean page ranges spanning paragraphs. Keep numeric ranges literal.
    public static func markdownProse(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<=[0-9])([ \t]*)~([ \t]*)(?=[0-9])"#) else { return text }
        let original = text as NSString, result = NSMutableString(string: text)
        let code = try? NSRegularExpression(pattern: #"(`+)[\s\S]*?\1"#)
        let codeRanges = code?.matches(in: text, range: NSRange(location: 0, length: original.length)).map(\.range) ?? []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: original.length)).reversed() {
            if codeRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { continue }
            result.replaceCharacters(in: match.range, with: original.substring(with: match.range).replacingOccurrences(of: "~", with: "\\~"))
        }
        return result as String
    }
    public static func blocks(_ text: String) -> [ChatContentBlock] {
        let lines = text.components(separatedBy: .newlines)
        var result: [ChatContentBlock] = [], paragraph: [String] = [], index = 0
        func append(_ kind: String, _ source: String, _ label: String = "", _ complete: Bool = true) {
            result.append(ChatContentBlock(id: result.count, kind: kind, source: source, label: label, complete: complete))
        }
        func flush() {
            let body = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { append("text", body) }
            paragraph = []
        }
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if let marker = line.first, marker == "`" || marker == "~" {
                let fence = String(line.prefix(while: { $0 == marker }))
                if fence.count >= 3 {
                    flush()
                    let language = line.dropFirst(fence.count).split(whereSeparator: { $0.isWhitespace }).first.map(String.init)?.lowercased() ?? ""
                    index += 1
                    var source: [String] = []
                    while index < lines.count {
                        let closing = lines[index].trimmingCharacters(in: .whitespaces)
                        if closing.count >= fence.count && closing.allSatisfy({ $0 == marker }) { break }
                        source.append(lines[index]); index += 1
                    }
                    let complete = index < lines.count
                    let kind = ["mermaid", "html", "svg"].contains(language) ? language : "code"
                    append(kind, source.joined(separator: "\n"), language, complete)
                    if complete { index += 1 }
                    continue
                }
            }
            if line.lowercased().hasPrefix("<svg") || line.lowercased().hasPrefix("<!doctype html") || line.lowercased().hasPrefix("<html") {
                flush()
                let kind = line.lowercased().hasPrefix("<svg") ? "svg" : "html"
                var source: [String] = []
                while index < lines.count {
                    source.append(lines[index]); index += 1
                    if source.last?.lowercased().contains(kind == "svg" ? "</svg>" : "</html>") == true { break }
                }
                append(kind, source.joined(separator: "\n"), kind, source.last?.lowercased().contains(kind == "svg" ? "</svg>" : "</html>") == true)
                continue
            }
            if let media = mediaLink(line) {
                flush(); append(media.kind, media.url, media.label); index += 1; continue
            }
            paragraph.append(lines[index]); index += 1
        }
        flush()
        return result
    }

    private static func mediaLink(_ line: String) -> (kind: String, url: String, label: String)? {
        let pattern = #"^(!?)\[([^\]]*)\]\(<?(.+?)>?(?:\s+\"[^\"]*\")?\)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let imageRange = Range(match.range(at: 1), in: line), let labelRange = Range(match.range(at: 2), in: line),
              let urlRange = Range(match.range(at: 3), in: line) else { return nil }
        let source = String(line[urlRange])
        let ext = URL(string: source)?.pathExtension.lowercased() ?? (source as NSString).pathExtension.lowercased()
        guard let kind = ChatAssetStore.kind(forExtension: ext) ?? (line[imageRange] == "!" ? "image" : nil),
              ["image", "audio", "video"].contains(kind) else { return nil }
        return (kind, source, String(line[labelRange]))
    }
}
