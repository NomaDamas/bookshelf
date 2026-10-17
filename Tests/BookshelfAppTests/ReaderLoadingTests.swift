import XCTest
import AppKit
import PDFKit
import BookshelfCore
@testable import BookshelfApp

@MainActor final class ReaderLoadingTests: XCTestCase {
    private func fixture(_ directory: URL, name: String, pages: Int = 3) throws -> URL {
        let url = directory.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for index in 1...pages {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            ("Reader fixture \(name), page \(index)" as NSString).draw(at: CGPoint(x: 20, y: 200), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF(); return url
    }
    private func open(_ book: Book, in model: AppModel) async throws -> PDFDocument {
        model.selectBook(book)
        for _ in 0..<200 {
            if !model.isOpening { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isOpening)
        return try XCTUnwrap(model.document)
    }
    func testSelectingBookKeepsSidebarAndReusesCurrentDocument() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory.appendingPathComponent("data"))
        let book = try store.register(source: fixture(directory, name: "book.pdf"), ocr: nil, root: directory)
        let model = AppModel(store: store)
        model.sidebarVisible = true
        let first = try await open(book, in: model)
        XCTAssertTrue(model.sidebarVisible, "Opening a book keeps its book tools available")
        XCTAssertTrue(model.isReadingBook)
        model.goToPage(2)
        let again = try await open(book, in: model)
        XCTAssertTrue(first === again, "Selecting the current book must not parse and rebuild its PDF")
        XCTAssertEqual(model.page, 2)
    }
    func testSwitchingBooksReusesUnchangedPDFButReloadsReplacedFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory.appendingPathComponent("data"))
        let a = try store.register(source: fixture(directory, name: "a.pdf"), ocr: nil, root: directory)
        let b = try store.register(source: fixture(directory, name: "b.pdf"), ocr: nil, root: directory)
        let model = AppModel(store: store)
        let first = try await open(a, in: model)
        _ = try await open(b, in: model)
        let cached = try await open(a, in: model)
        XCTAssertTrue(first === cached)
        _ = try fixture(directory, name: "a.pdf", pages: 5)
        let replaced = try await open(a, in: model)
        XCTAssertFalse(replaced === cached, "Replacing a PDF at the same path must invalidate cached data")
        XCTAssertEqual(replaced.pageCount, 5)
    }
    func testCachedDocumentDoesNotRestoreDeletedHighlights() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory.appendingPathComponent("data"))
        let book = try store.register(source: fixture(directory, name: "annotations.pdf"), ocr: nil, root: directory)
        let model = AppModel(store: store)
        let pdf = try await open(book, in: model)
        let page = try XCTUnwrap(pdf.page(at: 0))
        let original = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 20, height: 20), forType: .text, withProperties: nil)
        original.userName = "Original PDF annotation"; page.addAnnotation(original)
        let highlight = Highlight(bookID: book.id, page: 1, quote: "fixture", rects: [PageRect(x: 0.1, y: 0.3, width: 0.5, height: 0.1)])
        let firstView = ReaderPDFView(); firstView.document = pdf
        let first = PDFReaderView.Coordinator(model: model); first.view = firstView
        first.drawHighlights([highlight])
        XCTAssertEqual(page.annotations.filter { $0.userName == "Bookshelf" }.count, 1)
        let nextView = ReaderPDFView(); nextView.document = pdf
        let next = PDFReaderView.Coordinator(model: model); next.view = nextView
        next.drawHighlights([])
        XCTAssertEqual(page.annotations.filter { $0.userName == "Bookshelf" }.count, 0)
        XCTAssertTrue(page.annotations.contains { $0 === original })
    }

    func testInspectionCacheSurvivesReopenAndRejectsReplacedPDF() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try fixture(directory, name: "inspection.pdf")
        let data = directory.appendingPathComponent("data")
        let store = try LibraryStore(directory: data)
        let book = try store.register(source: url, ocr: nil, root: directory)
        let version = try PDFFileVersion(url)
        let inspection = try PDFService.inspect(url)
        try CachedPDFInspection(version: version, result: inspection).save(bookID: book.id, store: store)
        let reopened = try LibraryStore(directory: data)
        XCTAssertEqual(CachedPDFInspection.read(bookID: book.id, version: version, store: reopened)?.textPages, 3)
        _ = try fixture(directory, name: "inspection.pdf", pages: 5)
        XCTAssertNil(CachedPDFInspection.read(bookID: book.id, version: try PDFFileVersion(url), store: reopened))
        var calls = 0
        XCTAssertThrowsError(try PDFService.inspect(url, isCancelled: { calls += 1; return calls >= 3 })) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(calls, 3, "A cancelled inspection must stop between pages")
    }

    func testOldPDFViewCannotChangeNewBooksPosition() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory.appendingPathComponent("data"))
        let a = try store.register(source: fixture(directory, name: "old.pdf"), ocr: nil, root: directory)
        let b = try store.register(source: fixture(directory, name: "current.pdf"), ocr: nil, root: directory)
        let model = AppModel(store: store)
        let oldDocument = try await open(a, in: model)
        let oldView = ReaderPDFView(); oldView.document = oldDocument
        let oldCoordinator = PDFReaderView.Coordinator(model: model); oldCoordinator.view = oldView
        _ = try await open(b, in: model); model.goToPage(2)
        oldCoordinator.changedPage()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.page, 2, "A delayed notification from the old PDF must not overwrite the new reading position")
    }

}
