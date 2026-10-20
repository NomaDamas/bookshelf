import Foundation
import PDFKit

/// One embedded outline item with the PDF pages it covers (1-based, inclusive).
public struct BookOutlineEntry: Equatable, Sendable {
    public var title: String
    public var startPage: Int
    public var endPage: Int
    public var depth: Int
    public init(title: String, startPage: Int, endPage: Int, depth: Int) {
        self.title = title; self.startPage = startPage; self.endPage = endPage; self.depth = depth
    }
}

/// Chapter boundaries from the PDF's embedded outline. Pi's `get_book_overview` and the
/// panel's pre-reading offer both read these entries, so they agree on where a chapter starts.
public enum BookOutline {
    /// An entry ends before the next entry at the same or a shallower depth, or at the last page.
    public static func entries(in pdf: PDFDocument) -> [BookOutlineEntry] {
        var items: [(title: String, page: Int, depth: Int)] = []
        func walk(_ node: PDFOutline, depth: Int) {
            guard items.count < 300, depth < 12 else { return }
            if let page = (node.destination ?? (node.action as? PDFActionGoTo)?.destination)?.page {
                let index = pdf.index(for: page)
                if index != NSNotFound { items.append((String((node.label ?? "").prefix(200)), index + 1, depth)) }
            }
            for i in 0..<node.numberOfChildren { if let child = node.child(at: i) { walk(child, depth: depth + 1) } }
        }
        if let root = pdf.outlineRoot { walk(root, depth: -1) }
        return items.enumerated().map { index, item in
            let next = items.dropFirst(index + 1).first { $0.depth <= item.depth && $0.page > item.page }?.page ?? (pdf.pageCount + 1)
            return BookOutlineEntry(title: item.title, startPage: item.page, endPage: max(item.page, next - 1), depth: max(0, item.depth))
        }
    }
    /// The chapter a reader is opening: the outermost entry that starts on `page` and still has
    /// pages after it. A section that starts on the same page belongs to that chapter.
    public static func chapter(startingAt page: Int, in entries: [BookOutlineEntry]) -> BookOutlineEntry? {
        entries.filter { $0.startPage == page && $0.endPage > page }.min { $0.depth < $1.depth }
    }
}
