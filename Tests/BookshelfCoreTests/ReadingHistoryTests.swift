import XCTest
import CSQLite
@testable import BookshelfCore

final class ReadingHistoryTests: XCTestCase {
    private var directory: URL!
    private var store: LibraryStore!
    private var book: Book!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("reading-history-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try LibraryStore(directory: directory.appendingPathComponent("data"))
        let url = directory.appendingPathComponent("Test.pdf")
        try Data("authored fixture".utf8).write(to: url)
        book = try store.register(source: url, ocr: nil, root: directory)
        try store.updateInspection(bookID: book.id, pageCount: 20, textPages: 20)
    }
    override func tearDownWithError() throws {
        store = nil
        try FileManager.default.removeItem(at: directory)
    }
    private func summary() throws -> ReadingSummary { try XCTUnwrap(store.readingSummaries(bookID: book.id)[book.id]) }

    func testFourReadThroughsPersistWithDatesAndReviewDoesNotIncrement() throws {
        try store.saveNotebook(bookID: book.id, body: "보존할 노트", expectedRevision: 0)
        try store.savePosition(bookID: book.id, page: 20)
        XCTAssertEqual(try summary().status, .reading)
        XCTAssertEqual(try summary().completedCount, 0, "The last page is not completion")
        for cycle in 1...4 {
            if cycle > 1 {
                XCTAssertTrue(try store.startReading(bookID: book.id, now: Double(cycle * 100)))
                XCTAssertEqual(try store.book(book.id).lastPage, 1)
            }
            XCTAssertTrue(try store.completeReading(bookID: book.id, now: Double(cycle * 100 + 50)))
            XCTAssertFalse(try store.completeReading(bookID: book.id), "Double click must be idempotent")
            try store.savePosition(bookID: book.id, page: 8)
            XCTAssertEqual(try summary().status, .finished, "Reopening is review, not another read-through")
            XCTAssertEqual(try summary().completedCount, cycle)
        }
        let reloaded = try LibraryStore(directory: store.directory)
        XCTAssertEqual(try reloaded.readingSummaries(bookID: book.id)[book.id]?.completedCount, 4)
        XCTAssertEqual(try reloaded.readingHistory(bookID: book.id).map(\.completedAt), [450,350,250,150])
        XCTAssertEqual(try reloaded.notebook(bookID: book.id).body, "보존할 노트")
    }

    func testUndoOnlyLatestCompletionAndCancelRereadPreservePastHistory() throws {
        try store.completeReading(bookID: book.id, now: 100)
        try store.startReading(bookID: book.id, now: 200)
        try store.completeReading(bookID: book.id, now: 300)
        XCTAssertTrue(try store.undoReadingCompletion(bookID: book.id))
        XCTAssertFalse(try store.undoReadingCompletion(bookID: book.id))
        XCTAssertEqual(try summary().status, .reading)
        XCTAssertEqual(try summary().completedCount, 1)
        XCTAssertEqual(try summary().startedAt, 200)
        try store.shelveReading(bookID: book.id)
        XCTAssertEqual(try summary().status, .finished)
        XCTAssertEqual(try store.readingHistory(bookID: book.id).first?.completedAt, 100)
    }

    func testLegacyShelfMigratesWithoutInventingCompletionsOrLosingExclusions() throws {
        try store.setSetting("readingShelf.membership", value: "{\"\(book.id)\":false}")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(store.databaseURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "UPDATE books SET last_opened=1234,last_page=7;", nil, nil, nil), SQLITE_OK)
        let upgraded = try LibraryStore(directory: store.directory)
        XCTAssertEqual(try upgraded.readingSummaries()[book.id]?.status, .unread)
        try upgraded.savePosition(bookID: book.id, page: 8)
        XCTAssertEqual(try upgraded.readingSummaries()[book.id]?.status, .unread)
        XCTAssertEqual(try upgraded.readingSummaries()[book.id]?.completedCount, 0)
        try upgraded.startReading(bookID: book.id)
        try upgraded.completeReading(bookID: book.id)
        let reopened = try LibraryStore(directory: store.directory)
        XCTAssertEqual(try reopened.readingSummaries()[book.id]?.status, .finished, "Legacy flags cannot overwrite newer state")
        XCTAssertEqual(try reopened.book(book.id).lastPage, 8)
    }

    func testSeparateWritersAndOCRKeepOneHistory() throws {
        let other = try LibraryStore(directory: store.directory)
        XCTAssertTrue(try store.completeReading(bookID: book.id))
        XCTAssertFalse(try other.completeReading(bookID: book.id))
        let url = directory.appendingPathComponent("Test_ocr.pdf")
        try Data("replacement fixture".utf8).write(to: url)
        try store.attachOCR(bookID: book.id, url: url, pageCount: 20, textPages: 20)
        let imported = try store.register(source: url, ocr: nil, root: directory)
        XCTAssertEqual(imported.id, book.id)
        XCTAssertEqual(try other.readingSummaries()[book.id]?.completedCount, 1)
    }

    func testNoteCountsCountItemsNotRevisionsAndHandleNinetyNinePlus() throws {
        var note = try store.saveNotebook(bookID: book.id, body: " \n\t\u{3000}", expectedRevision: 0)
        XCTAssertEqual(try store.noteCounts()[book.id]?.total, 0)
        note = try store.saveNotebook(bookID: book.id, body: "책 전체 노트", expectedRevision: note.revision)
        try store.saveNotebook(bookID: book.id, body: "책 전체 노트 수정", expectedRevision: note.revision)
        let excerpts = (1...99).map { Highlight(bookID: book.id, page: 2, quote: "발췌 \($0)") }
        for excerpt in excerpts { try store.saveHighlight(excerpt) }
        XCTAssertEqual(try store.noteCounts()[book.id]?.total, 100)
        XCTAssertEqual(try store.noteCounts()[book.id]?.badge, "99+")
        var edited = excerpts[0]; edited.comment = "수정은 새 메모가 아닙니다."
        try store.saveHighlight(edited)
        XCTAssertEqual(try store.noteCounts()[book.id]?.total, 100)
        try store.deleteHighlight(id: excerpts[1].id, bookID: book.id)
        XCTAssertEqual(try store.noteCounts()[book.id]?.badge, "99")
        let reopened = try LibraryStore(directory: store.directory)
        XCTAssertEqual(try reopened.noteCounts()[book.id]?.total, 99)
    }
}
