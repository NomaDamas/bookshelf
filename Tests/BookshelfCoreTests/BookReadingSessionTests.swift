import XCTest
import PDFKit
import CoreText
import AppKit
@testable import BookshelfCore

final class BookReadingSessionTests: XCTestCase {
    func testCodexHandshakeIgnoresOnlyUnsupportedExperimentalCapabilities() throws {
        let raw = Data(#"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{"experimental":{"codex/auth-change":{},"known":"value"},"elicitation":{"form":{},"url":{}}},"clientInfo":{"name":"codex-mcp-client","version":"0.163.0"}}}"#.utf8)
        let decoded = try json(String(decoding: MCPHandshakeCompatibility.ignoringUnsupportedExtensions(raw), as: UTF8.self))
        let params = try XCTUnwrap(decoded["params"] as? [String: Any]), caps = try XCTUnwrap(params["capabilities"] as? [String: Any])
        XCTAssertEqual(caps["experimental"] as? [String: String], ["known":"value"])
        XCTAssertNotNil(caps["elicitation"]); XCTAssertEqual(params["protocolVersion"] as? String, "2025-06-18")
        let call = Data(#"{"method":"tools/call","params":{"experimental":{"keep":{}}}}"#.utf8)
        XCTAssertEqual(MCPHandshakeCompatibility.ignoringUnsupportedExtensions(call), call)
    }
    private func fixture(lines: [[String]], root: URL) throws -> Book {
        var box = CGRect(x: 0, y: 0, width: 3500, height: 900)
        let url = root.appendingPathComponent("Reading.pdf")
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for page in lines {
            context.beginPDFPage(nil)
            for (index, line) in page.enumerated() {
                context.textPosition = CGPoint(x: 20, y: 860 - index * 9)
                CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: [.font: NSFont.systemFont(ofSize: 8)])), context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        let pdf = try XCTUnwrap(PDFDocument(url: url)), outline = PDFOutline()
        for (title, page) in [("Chapter 1: Inventory", 0), ("Chapter 2: Warranty", max(0, lines.count - 1))] {
            let child = PDFOutline(); child.label = title; child.destination = PDFDestination(page: pdf.page(at: page)!, at: .zero)
            outline.insertChild(child, at: outline.numberOfChildren)
        }
        pdf.outlineRoot = outline; XCTAssertTrue(pdf.write(to: url))
        return try LibraryStore(directory: root.appendingPathComponent("data")).register(source: url, ocr: nil, root: root)
    }
    private func root() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true); return value
    }
    private func json(_ value: String) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]) }

    func testWholeBookSearchReadsDistantPagesAndOutlineWithoutOverclaimingCoverage() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let book = try fixture(lines: [["Introduction"], ["Set quantity to one."], ["Add one."], ["War ran ty lasts nine years."]], root: root)
        let session = try BookReadingSession(book: book, scope: .init(mode: "book", startPage: 1, endPage: 4))
        let overview = try json(await session.call("get_book_overview"))
        XCTAssertEqual((overview["outline"] as? [[String: Any]])?.last?["startPage"] as? Int, 4)
        let search = try json(await session.call("search_book", query: "Warranty"))
        XCTAssertEqual((search["matches"] as? [[String: Any]])?.first?["page"] as? Int, 4)
        XCTAssertEqual((search["reading"] as? [String: Any])?["readPages"] as? [Int], [])
        let read = try json(await session.call("read_pages", startPage: 4))
        XCTAssertTrue(((read["pages"] as? [[String: Any]])?.first?["text"] as? String ?? "").contains("nine years"))
        XCTAssertEqual((read["reading"] as? [String: Any])?["readPages"] as? [Int], [4])
        _ = try await session.call("read_pages", startPage: 1, endPage: 3)
        let covered = try json(await session.call("get_reading_coverage"))
        XCTAssertEqual((covered["reading"] as? [String: Any])?["readPages"] as? [Int], [1,2,3,4])
    }
    func testWholeBookScansCrossDocumentReopenBoundaries() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        // Pages 17 and 33 start the second and third reopened document copies.
        let book = try fixture(lines: (1...40).map { $0 == 17 || $0 == 33 ? [] : ["Marker \($0) end"] }, root: root)
        let inspection = try PDFService.inspect(book.url)
        XCTAssertEqual(inspection.pageCount, 40); XCTAssertEqual(inspection.emptyPages, [17, 33])
        XCTAssertEqual(try PDFService.search(book, query: "Marker 34 end", limit: 20, ignoreWhitespace: false).map(\.page), [34])
        XCTAssertEqual(try PDFService.search(book, query: "Marker", limit: 20, ignoreWhitespace: false).map(\.page).last, 21)
        let session = try BookReadingSession(book: book, scope: .init(mode: "book", startPage: 1, endPage: 40))
        let search = try json(await session.call("search_book", query: "Marker 39 end"))
        XCTAssertEqual((search["matches"] as? [[String: Any]])?.compactMap { $0["page"] as? Int }, [39])
    }
    func testRestrictedRangeCannotSearchOrReadOutsideIt() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let book = try fixture(lines: [["Start"], ["Inventory"], ["Outside secret phrase"]], root: root)
        let session = try BookReadingSession(book: book, scope: .init(mode: "range", startPage: 1, endPage: 2))
        let search = try json(await session.call("search_book", query: "secret"))
        XCTAssertTrue((search["matches"] as? [[String: Any]])?.isEmpty == true)
        for page in [0,3] {
            do { _ = try await session.call("read_pages", startPage: page); XCTFail("Accepted page outside range") } catch { }
        }
        do { _ = try await session.call("list_books"); XCTFail("Exposed another book") } catch { }
    }
    func testLargePageContinuationOnlyCountsCompleteContiguousReads() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let line = String(repeating: "source ", count: 70)
        let book = try fixture(lines: [Array(repeating: line, count: 80)], root: root)
        let session = try BookReadingSession(book: book, scope: .init(mode: "page", startPage: 1, endPage: 1))
        let tail = try json(await session.call("read_pages", startPage: 1, offset: 20000))
        XCTAssertEqual((tail["reading"] as? [String: Any])?["readPages"] as? [Int], [])
        let first = try json(await session.call("read_pages", startPage: 1))
        XCTAssertEqual(first["nextPage"] as? Int, 1)
        let offset = try XCTUnwrap(first["nextOffset"] as? Int)
        XCTAssertEqual(offset, 24000)
        let rest = try json(await session.call("read_pages", startPage: 1, offset: offset))
        XCTAssertEqual((rest["reading"] as? [String: Any])?["readPages"] as? [Int], [1])
        XCTAssertNil(rest["nextPage"])
    }
    func testCitationsOnlyLinkVerifiedPagesAndRangesExcludeTheCurrentPageText() {
        let context = AgentRequest.Context(id: "book", title: "Test", page: 1, text: "outside", notes: "note", selection: "outside selection", scope: .init(mode: "range", startPage: 3, endPage: 5))
        XCTAssertEqual(context.text, ""); XCTAssertEqual(context.selection, ""); XCTAssertEqual(context.providedCharacters, 0)
        let linked = ChatCitations.linkedMarkdown("한글 [p. 4] and [p. 99]", pages: [4])
        XCTAssertTrue(linked.contains("bookside-citation://page/4")); XCTAssertTrue(linked.hasSuffix("[p. 99]"))
        XCTAssertEqual(ChatCitations.page(in: URL(string: "bookside-citation://page/4")!, allowed: [4]), 4)
        XCTAssertNil(ChatCitations.page(in: URL(string: "bookside-citation://page/99")!, allowed: [4]))
        XCTAssertNil(ChatCitations.page(in: URL(string: "bookside-citation://other/4")!, allowed: [4]))
    }
}
