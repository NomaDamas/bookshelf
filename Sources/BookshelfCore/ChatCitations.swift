import Foundation

public enum ChatCitations {
    public static func linkedMarkdown(_ text: String, pages: Set<Int>) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[p\.\s*(\d+)\](?!\()"#) else { return text }
        let original = text as NSString, result = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: original.length)).reversed() {
            guard let page = Int(original.substring(with: match.range(at: 1))), pages.contains(page) else { continue }
            result.replaceCharacters(in: match.range, with: "[p. \(page)](bookshelf-citation://page/\(page))")
        }
        return result as String
    }
    public static func page(in url: URL, allowed: Set<Int>) -> Int? {
        guard url.scheme == "bookshelf-citation", url.host == "page", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil, url.pathComponents.count == 2,
              let page = Int(url.lastPathComponent), allowed.contains(page) else { return nil }
        return page
    }
}
