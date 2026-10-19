import Foundation
import PDFKit

public struct BookReadingScope: Codable, Equatable, Sendable {
    public var mode: String
    public var startPage: Int
    public var endPage: Int
    public init(mode: String, startPage: Int, endPage: Int) {
        self.mode = mode; self.startPage = startPage; self.endPage = endPage
    }
    public func contains(_ page: Int) -> Bool { page >= startPage && page <= endPage }
    public var pageCount: Int { max(0, endPage - startPage + 1) }
    public var title: String {
        if mode == "book" { return "이 책 전체" }
        if mode == "page" { return "현재 \(startPage)쪽" }
        return "\(startPage)~\(endPage)쪽"
    }
}

public struct BookReadingCoverage: Codable, Equatable, Sendable {
    public var bookID: String
    public var scope: BookReadingScope
    public var readPages: [Int]
    public var sourcePages: [Int]
    public var emptyPages: [Int]
    public init(bookID: String, scope: BookReadingScope, readPages: [Int] = [], sourcePages: [Int] = [], emptyPages: [Int] = []) {
        self.bookID = bookID; self.scope = scope; self.readPages = readPages; self.sourcePages = sourcePages; self.emptyPages = emptyPages
    }
}

/// One book and an immutable page boundary per request. PDF bytes are never modified.
public actor BookReadingSession {
    private let book: Book
    private let pdf: PDFDocument
    private let scope: BookReadingScope
    private var textCache: [Int: String] = [:]
    private var textSource: PDFDocument?
    private var textReads = 0
    private var readPrefix: [Int: Int] = [:]
    private var complete = Set<Int>()
    private var sources = Set<Int>()
    private var empty = Set<Int>()

    public init(book: Book, scope: BookReadingScope, providedPage: Int? = nil, providedCharacters: Int = 0) throws {
        let document = try PDFService.document(at: book.url)
        guard ["book", "page", "range"].contains(scope.mode), scope.startPage >= 1,
              scope.endPage >= scope.startPage, scope.endPage <= document.pageCount,
              scope.mode != "book" || (scope.startPage == 1 && scope.endPage == document.pageCount),
              scope.mode != "page" || scope.startPage == scope.endPage else {
            throw ShelfError.message("질문할 페이지 범위를 확인해 주세요.")
        }
        // A nonisolated actor init may only write isolated state before every stored property is set.
        if let page = providedPage, scope.contains(page), providedCharacters > 0 {
            let text = document.page(at: page - 1)?.string ?? ""
            let count = min(text.count, min(providedCharacters, 10000))
            textCache[page] = text; readPrefix[page] = count
            if count > 0 { sources.insert(page) }
            if count == text.count && count > 0 { complete.insert(page) }
        }
        self.book = book; pdf = document; self.scope = scope
    }

    public func call(_ tool: String, query: String? = nil, startPage: Int? = nil, endPage: Int? = nil, offset: Int? = nil) throws -> String {
        var result: [String: Any] = ["bookID": book.id, "title": book.title, "pageCount": pdf.pageCount]
        switch tool {
        case "get_book_overview":
            result["outline"] = outline()
            result["guidance"] = "PDF page indices are 1-based. If the PDF outline is empty, read the beginning of the allowed range to find a printed table of contents. A whole-book summary requires reading every chapter, not only search hits."
        case "search_book":
            guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.count <= 200 else {
                throw ShelfError.message("검색어는 1~200자로 입력해 주세요.")
            }
            let start = startPage ?? scope.startPage
            try check(start)
            let term = TextSearchQuery(query, ignoreWhitespace: true)
            guard !term.isEmpty else { throw ShelfError.message("검색어를 확인해 주세요.") }
            var hits: [[String: Any]] = []
            for page in start...scope.endPage {
                try Task.checkCancellation()
                let value = text(page)
                if let match = term.range(in: value) {
                    let a = value.index(match.lowerBound, offsetBy: -120, limitedBy: value.startIndex) ?? value.startIndex
                    let b = value.index(match.upperBound, offsetBy: 400, limitedBy: value.endIndex) ?? value.endIndex
                    hits.append(["page": page, "text": String(value[a..<b])]); sources.insert(page)
                    if hits.count == 12 {
                        if page < scope.endPage { result["nextPage"] = page + 1 }
                        break
                    }
                }
            }
            result["matches"] = hits
            result["guidance"] = "Search excerpts are not complete page reads. Read relevant pages and adjacent context before drawing conclusions. Try related terms when needed."
        case "read_pages":
            guard let start = startPage else { throw ShelfError.message("start_page가 필요합니다.") }
            let end = endPage ?? start, initialOffset = offset ?? 0
            try check(start); try check(end)
            guard end >= start, initialOffset >= 0 else { throw ShelfError.message("페이지 순서와 offset을 확인해 주세요.") }
            var pages: [[String: Any]] = [], remaining = 24000
            for page in start...min(end, start + 9) {
                try Task.checkCancellation()
                let value = text(page), begin = page == start ? initialOffset : 0
                guard begin <= value.count else { throw ShelfError.message("offset이 페이지 길이를 넘었습니다.") }
                let chunk = String(value.dropFirst(begin).prefix(remaining)), finish = begin + chunk.count
                pages.append(["page": page, "text": chunk, "offset": begin, "truncated": finish < value.count])
                if !chunk.isEmpty { sources.insert(page) }
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { empty.insert(page) }
                else if begin <= (readPrefix[page] ?? 0) {
                    readPrefix[page] = max(readPrefix[page] ?? 0, finish)
                    if readPrefix[page] == value.count { complete.insert(page) }
                }
                remaining -= chunk.count
                if finish < value.count {
                    result["nextPage"] = page; result["nextOffset"] = finish; break
                }
                if page < end { result["nextPage"] = page + 1; result["nextOffset"] = 0 }
                else { result.removeValue(forKey: "nextPage"); result.removeValue(forKey: "nextOffset") }
                if remaining == 0 { break }
            }
            result["pages"] = pages
        case "get_reading_coverage": break
        default: throw ShelfError.message("이 책에서 사용할 수 없는 도구입니다.")
        }
        let coverage = BookReadingCoverage(bookID: book.id, scope: scope, readPages: complete.sorted(), sourcePages: sources.sorted(), emptyPages: empty.sorted())
        result["reading"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(coverage))
        result["referenceOnly"] = true
        return String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!
    }

    private func check(_ page: Int) throws {
        guard scope.contains(page) else { throw ShelfError.message("허용된 질문 범위는 \(scope.startPage)~\(scope.endPage)쪽입니다.") }
    }
    private func text(_ page: Int) -> String {
        if let cached = textCache[page] { return cached }
        // Whole-book searches read through a short-lived copy replaced every few pages (see PDFService.pagesPerDocument).
        if textReads % PDFService.pagesPerDocument == 0 {
            textSource = PDFDocument(url: book.url).flatMap { $0.pageCount == pdf.pageCount && !$0.isLocked ? $0 : nil }
        }
        textReads += 1
        let value = autoreleasepool { (textSource ?? pdf).page(at: page - 1)?.string ?? "" }
        textCache[page] = value; return value
    }
    private func outline() -> [[String: Any]] {
        var entries: [(title: String, page: Int, depth: Int)] = []
        func walk(_ node: PDFOutline, depth: Int) {
            guard entries.count < 300, depth < 12 else { return }
            if let page = (node.destination ?? (node.action as? PDFActionGoTo)?.destination)?.page {
                let index = pdf.index(for: page)
                if index != NSNotFound { entries.append((String((node.label ?? "").prefix(200)), index + 1, depth)) }
            }
            for i in 0..<node.numberOfChildren { if let child = node.child(at: i) { walk(child, depth: depth + 1) } }
        }
        if let root = pdf.outlineRoot { walk(root, depth: -1) }
        return entries.enumerated().compactMap { index, entry in
            let next = entries.dropFirst(index + 1).first { $0.depth <= entry.depth && $0.page > entry.page }?.page ?? (pdf.pageCount + 1)
            let start = max(scope.startPage, entry.page), end = min(scope.endPage, next - 1)
            guard start <= end else { return nil }
            return ["title": entry.title, "startPage": start, "endPage": end, "depth": max(0, entry.depth)]
        }
    }
}
