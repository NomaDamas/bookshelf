import Foundation
import PDFKit

public struct PDFInspection: Codable, Sendable {
    public var pageCount: Int
    public var textPages: Int
    public var emptyPages: [Int]
}

public enum PDFService {
    public static func document(at url: URL) throws -> PDFDocument {
        guard FileAccess.isResident(url) else { throw ShelfError.message("iCloud에서 먼저 다운로드해야 하는 PDF입니다.") }
        guard let document = PDFDocument(url: url) else { throw ShelfError.message("PDF 파일을 열지 못했습니다.") }
        guard !document.isLocked else { throw ShelfError.message("암호로 잠긴 PDF입니다. 잠금이 해제된 사본을 추가해 주세요.") }
        return document
    }
    public static func inspect(_ url: URL, isCancelled: () -> Bool = { false }) throws -> PDFInspection {
        try autoreleasepool {
            if isCancelled() { throw CancellationError() }
            var empty: [Int] = []
            let pageCount = try scanPageText(url) { index, text in
                if isCancelled() { throw CancellationError() }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { empty.append(index + 1) }
                return true
            }
            return PDFInspection(pageCount: pageCount, textPages: pageCount - empty.count, emptyPages: empty)
        }
    }
    /// A PDFDocument keeps every page's extracted text layout until the document is released,
    /// about 2 MB per scanned page. Whole-book scans reopen the file every few pages so their
    /// peak memory does not grow with the book.
    static let pagesPerDocument = 16
    /// Returns the page count; `visit` returns false to stop.
    static func scanPageText(_ url: URL, _ visit: (Int, String) throws -> Bool) throws -> Int {
        var opened: PDFDocument? = try document(at: url)
        let pageCount = opened?.pageCount ?? 0
        var index = 0
        while index < pageCount {
            let more = try autoreleasepool { () throws -> Bool in
                let pdf = try opened ?? reopen(url, pageCount: pageCount)
                opened = nil
                for page in index..<min(index + pagesPerDocument, pageCount) {
                    if try !visit(page, pdf.page(at: page)?.string ?? "") { return false }
                }
                return true
            }
            guard more else { break }
            index += pagesPerDocument
        }
        return pageCount
    }
    static func reopen(_ url: URL, pageCount: Int) throws -> PDFDocument {
        guard let pdf = PDFDocument(url: url), !pdf.isLocked, pdf.pageCount == pageCount else {
            throw ShelfError.message("PDF가 변경되었습니다. 다시 열어 주세요.")
        }
        return pdf
    }
    public static func readPage(_ book: Book, page: Int) throws -> String {
        try autoreleasepool {
            let pdf = try document(at: book.url)
            guard page >= 1, page <= pdf.pageCount else { throw ShelfError.message("페이지는 1~\(pdf.pageCount) 범위여야 합니다.") }
            return pdf.page(at: page - 1)?.string ?? ""
        }
    }
    public static func search(_ book: Book, query: String, limit: Int = 20, ignoreWhitespace: Bool = true) throws -> [SearchHit] {
        let term = TextSearchQuery(query, ignoreWhitespace: ignoreWhitespace)
        guard !term.isEmpty else { return [] }
        return try autoreleasepool {
            var results: [SearchHit] = []
            _ = try scanPageText(book.url) { i, text in
                if let range = term.range(in: text) {
                    let start = text.index(range.lowerBound, offsetBy: -120, limitedBy: text.startIndex) ?? text.startIndex
                    let end = text.index(range.upperBound, offsetBy: 400, limitedBy: text.endIndex) ?? text.endIndex
                    results.append(SearchHit(page: i + 1, text: String(text[start..<end])))
                    if results.count >= min(max(limit, 1), 100) { return false }
                }
                return true
            }
            return results
        }
    }
    public static func validateOCR(source: URL, output: URL) throws -> PDFInspection {
        let original = try document(at: source), result = try document(at: output)
        guard original.pageCount == result.pageCount, result.pageCount > 0 else { throw ShelfError.message("OCR 결과의 페이지 수가 원본과 달라 연결하지 않았습니다.") }
        for i in 0..<original.pageCount {
            guard let a = original.page(at: i), let b = result.page(at: i) else { throw ShelfError.message("OCR 결과에 읽을 수 없는 페이지가 있습니다.") }
            guard a.rotation == b.rotation else { throw ShelfError.message("OCR 결과의 페이지 회전이 변경되어 연결하지 않았습니다.") }
            for box in [PDFDisplayBox.mediaBox, .cropBox] {
                let x = a.bounds(for: box), y = b.bounds(for: box)
                guard abs(x.minX-y.minX) <= 0.01, abs(x.minY-y.minY) <= 0.01, abs(x.width-y.width) <= 0.01, abs(x.height-y.height) <= 0.01 else {
                    throw ShelfError.message("OCR 결과의 페이지 크기 또는 잘림 영역이 변경되어 연결하지 않았습니다.")
                }
            }
        }
        let inspection = try inspect(output)
        guard inspection.textPages > 0 else { throw ShelfError.message("OCR 결과에서 텍스트를 찾지 못했습니다.") }
        return inspection
    }
}
