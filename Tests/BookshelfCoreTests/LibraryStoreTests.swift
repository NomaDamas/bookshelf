import XCTest
import Foundation
@testable import BookshelfCore

final class LibraryStoreTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("bookshelf-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func makeFile(_ name: String) throws -> URL { let url = directory.appendingPathComponent(name); try Data("synthetic fixture".utf8).write(to: url); return url }
    func testNotesBookmarksAndProgressSurviveReopen() throws {
        let pdf = try makeFile("book.pdf"), data = directory.appendingPathComponent("data")
        var bookID = ""
        do {
            let store = try LibraryStore(directory: data)
            let book = try store.register(source: pdf, ocr: nil, root: directory); bookID = book.id
            try store.saveNotebook(bookID: book.id, body: "내가 이해한 내용", expectedRevision: 0)
            try store.saveHighlight(Highlight(bookID: book.id, page: 2, quote: "근거 문장", comment: "내 생각"))
            try store.toggleBookmark(bookID: book.id, page: 2)
            try store.savePosition(bookID: book.id, page: 2)
        }
        let reopened = try LibraryStore(directory: data)
        XCTAssertEqual(try reopened.notebook(bookID: bookID).body, "내가 이해한 내용")
        XCTAssertEqual(try reopened.bookmarks(bookID: bookID), [2])
        XCTAssertEqual(try reopened.book(bookID).lastPage, 2)
        XCTAssertEqual(try reopened.highlights(bookID: bookID).first?.comment, "내 생각")
    }
    func testConflictingWriterCannotOverwriteNewerNote() throws {
        let pdf = try makeFile("book.pdf"), data = directory.appendingPathComponent("data")
        let a = try LibraryStore(directory: data), b = try LibraryStore(directory: data)
        let book = try a.register(source: pdf, ocr: nil, root: directory)
        try a.saveNotebook(bookID: book.id, body: "new", expectedRevision: 0)
        XCTAssertThrowsError(try b.saveNotebook(bookID: book.id, body: "stale", expectedRevision: 0))
        XCTAssertEqual(try b.notebook(bookID: book.id).body, "new")
    }
    func testOCRAttachmentKeepsIdentityAndNotes() throws {
        let pdf = try makeFile("책.pdf"), ocr = try makeFile("책_ocr.pdf")
        let store = try LibraryStore(directory: directory.appendingPathComponent("data"))
        let book = try store.register(source: pdf, ocr: nil, root: directory)
        try store.saveNotebook(bookID: book.id, body: "OCR 이전 메모", expectedRevision: 0)
        try store.attachOCR(bookID: book.id, url: ocr, pageCount: 3, textPages: 3)
        XCTAssertEqual(try store.book(book.id).activePath, FileAccess.canonicalPath(ocr))
        XCTAssertEqual(try store.notebook(bookID: book.id).body, "OCR 이전 메모")
        let imported = try LibraryImporter.add(directory, to: store)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.id, book.id)
    }
    func testRenameKeepsIdentity() throws {
        let pdf = try makeFile("old.pdf"), renamed = directory.appendingPathComponent("new.pdf")
        let store = try LibraryStore(directory: directory.appendingPathComponent("data"))
        let book = try store.register(source: pdf, ocr: nil, root: directory)
        try store.saveNotebook(bookID: book.id, body: "보존", expectedRevision: 0)
        try FileManager.default.moveItem(at: pdf, to: renamed)
        let updated = try store.register(source: renamed, ocr: nil, root: directory)
        XCTAssertEqual(updated.id, book.id)
        XCTAssertEqual(try store.notebook(bookID: updated.id).body, "보존")
    }
    func testRescanKeepsOriginalAndLatestOCRVersion() throws {
        let source = try makeFile("book.pdf"), firstOCR = try makeFile("book_ocr.pdf"), newerOCR = try makeFile("book_2_ocr.pdf")
        let store = try LibraryStore(directory: directory.appendingPathComponent("data"))
        let b = try store.register(source: source, ocr: firstOCR, root: directory)
        try store.attachOCR(bookID: b.id, url: newerOCR, pageCount: 2, textPages: 2)
        _ = try LibraryImporter.add(directory, to: store)
        XCTAssertEqual(try store.books().count, 1)
        XCTAssertEqual(try store.book(b.id).sourcePath, FileAccess.canonicalPath(source))
        XCTAssertEqual(try store.book(b.id).activePath, FileAccess.canonicalPath(newerOCR))
    }
    func testBookNotesRemainSeparate() throws {
        let store = try LibraryStore(directory: directory.appendingPathComponent("data"))
        let first = try store.register(source: makeFile("first.pdf"), ocr: nil, root: directory)
        let second = try store.register(source: makeFile("second.pdf"), ocr: nil, root: directory)
        try store.saveNotebook(bookID: first.id, body: "첫 번째 책", expectedRevision: 0)
        XCTAssertEqual(try store.notebook(bookID: second.id).body, "")
        XCTAssertThrowsError(try store.savePosition(bookID: second.id, page: 0))
    }
    func testReviewCandidatesStayUnattachedAcrossRescansAndVersionsKeepOneBook() throws {
        let source = try makeFile("book.pdf"), candidate = try makeFile("book_ocr.pdf"), next = try makeFile("book_2_ocr.pdf")
        let store = try LibraryStore(directory: directory.appendingPathComponent("data"))
        let book = try store.register(source: source, ocr: nil, root: directory)
        let report = directory.appendingPathComponent("review.json")
        try store.holdOCRCandidate(bookID: book.id, url: candidate, report: report)
        try store.holdOCRCandidate(bookID: book.id, url: next, report: report)
        _ = try LibraryImporter.add(directory, to: store)
        XCTAssertEqual(try store.books().count, 1)
        XCTAssertNil(try store.book(book.id).ocrPath)
        try store.attachOCR(bookID: book.id, url: candidate, pageCount: 2, textPages: 2, expectedSourcePath: source.path)
        XCTAssertThrowsError(try store.attachOCR(bookID: book.id, url: next, pageCount: 2, textPages: 2, expectedSourcePath: source.path))
        try store.attachOCR(bookID: book.id, url: next, pageCount: 2, textPages: 2, expectedSourcePath: candidate.path)
        _ = try LibraryImporter.add(directory, to: store)
        XCTAssertEqual(try store.books().count, 1)
        XCTAssertEqual(try store.book(book.id).ocrPath, next.path)
    }
    func testCancelBeforeWorkerStartsDoesNotLaunchOCR() throws {
        let source = try makeFile("source.pdf"), output = directory.appendingPathComponent("output.pdf")
        let store = try LibraryStore(directory: directory.appendingPathComponent("data"))
        let book = try store.register(source: source, ocr: nil, root: directory)
        let service = OCRService(); service.cancel()
        XCTAssertThrowsError(try service.run(book: book, output: output, language: "kor", store: store, progress: { _ in })) { error in
            guard let value = error as? ShelfError, case .cancelled = value else { return XCTFail("Expected cancellation before any PDF or executable access") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
}
