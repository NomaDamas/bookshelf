import XCTest
import PDFKit
import BookshelfCore
@testable import BookshelfApp

@MainActor final class ReadingShelfTests: XCTestCase {
    private func fixture(_ name: String, in directory: URL, store: LibraryStore) throws -> Book {
        let pdf = PDFDocument()
        for index in 0..<4 {
            let page = PDFPage(); page.setBounds(CGRect(x: 0, y: 0, width: 300, height: 400), for: .mediaBox)
            pdf.insert(page, at: index)
        }
        let url = directory.appendingPathComponent(name + ".pdf")
        XCTAssertTrue(pdf.write(to: url))
        return try store.register(source: url, ocr: nil, root: directory)
    }
    private func open(_ book: Book, model: AppModel) async throws {
        model.selectBook(book)
        for _ in 0..<200 where model.isOpening { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(model.document); XCTAssertFalse(model.isOpening); XCTAssertNil(model.errorMessage)
    }
    private func directory() throws -> URL {
        let result = FileManager.default.temporaryDirectory.appendingPathComponent("reading-shelf-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }
    func testStartedBooksAppearImmediatelyInRecentOrderAndChoicesPersist() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let first = try fixture("First", in: root, store: store)
        let second = try fixture("Second", in: root, store: store)
        let waiting = try fixture("Waiting", in: root, store: store)
        let model = AppModel(store: store)
        XCTAssertTrue(model.readingBooks.isEmpty)
        try await open(first, model: model); model.goToPage(2); model.showReadingShelf()
        XCTAssertEqual(model.readingBooks.map(\.id), [first.id])
        XCTAssertEqual(model.readingBooks.first?.lastPage, 2)
        try await open(second, model: model); model.showReadingShelf()
        XCTAssertEqual(model.readingBooks.map(\.id), [second.id, first.id])
        model.shelveReading(second)
        model.startReading(waiting, open: false)
        XCTAssertEqual(model.readingBooks.map(\.id), [waiting.id, first.id])
        let restarted = AppModel(store: try LibraryStore(directory: store.directory))
        XCTAssertEqual(restarted.readingBooks.map(\.id), [waiting.id, first.id])
    }
    func testExcludedBookStaysOutWhenReopenedAndKeepsNotesAndPosition() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let book = try fixture("Keep my notes", in: root, store: store)
        let model = AppModel(store: store)
        try await open(book, model: model)
        model.editNotebook("책별 메모는 목록에서 제외해도 남아야 합니다.")
        model.goToPage(3); model.showReadingShelf()
        model.shelveReading(book)
        XCTAssertTrue(model.readingBooks.isEmpty)
        XCTAssertEqual(try store.notebook(bookID: book.id).body, "책별 메모는 목록에서 제외해도 남아야 합니다.")
        XCTAssertEqual(try store.book(book.id).lastPage, 3)
        try await open(book, model: model); model.showReadingShelf()
        XCTAssertTrue(model.readingBooks.isEmpty)
        model.startReading(book, open: false)
        XCTAssertEqual(model.readingBooks.first?.id, book.id)
        XCTAssertEqual(model.readingBooks.first?.lastPage, 3)
    }
    func testShelfNavigationFlushesEditsAndKeepsTheLoadedDocument() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let book = try fixture("Continue", in: root, store: store)
        let model = AppModel(store: store)
        try await open(book, model: model)
        let pdf = model.document
        model.editNotebook("저장 전에 모아보기로 이동")
        model.showReadingShelf()
        XCTAssertTrue(model.readingShelfVisible)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(try store.notebook(bookID: book.id).body, "저장 전에 모아보기로 이동")
        model.selectBook(book)
        XCTAssertFalse(model.readingShelfVisible)
        XCTAssertTrue(model.document === pdf)
    }
    func testNoteConflictKeepsDraftInReader() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let book = try fixture("Conflict", in: root, store: store)
        let model = AppModel(store: store)
        try await open(book, model: model)
        model.editNotebook("내가 쓰던 내용")
        try store.saveNotebook(bookID: book.id, body: "다른 창에서 저장한 내용", expectedRevision: 0)
        model.showReadingShelf()
        XCTAssertFalse(model.readingShelfVisible)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(model.notebookText, "내가 쓰던 내용")
        XCTAssertEqual(try store.notebook(bookID: book.id).body, "다른 창에서 저장한 내용")
        XCTAssertNotNil(model.errorMessage)
    }

    func testOpeningBookAppearsWhenShelfIsShownBeforeLoadingFinishes() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let book = try fixture("Opening", in: root, store: store)
        let model = AppModel(store: store)
        model.selectBook(book)
        model.showReadingShelf()
        for _ in 0..<200 where model.isOpening { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.readingShelfVisible)
        XCTAssertEqual(model.readingBooks.first?.id, book.id)
        XCTAssertEqual(model.readingBooks.first?.lastPage, 1)
    }

    func testHiddenPDFViewCannotMoveReadingPosition() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let book = try fixture("Hidden PDF", in: root, store: store)
        let model = AppModel(store: store)
        try await open(book, model: model)
        let pdf = try XCTUnwrap(model.document)
        let view = ReaderPDFView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        view.displayMode = .singlePage; view.document = pdf
        view.go(to: try XCTUnwrap(pdf.page(at: 3)))
        XCTAssertEqual(pdf.index(for: try XCTUnwrap(view.currentPage)), 3)
        let coordinator = PDFReaderView.Coordinator(model: model); coordinator.view = view
        for shelfVisible in [true, false] {
            model.goToPage(2)
            model.readingShelfVisible = shelfVisible; model.textMode = !shelfVisible
            coordinator.changedPage()
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(model.page, 2, "Hidden PDF reflow must not replace the saved position")
        }
    }

    func testFinishedBookReviewAndRereadPreserveCountsAndResetOnlyRereadPosition() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let book = try fixture("Repeated reading", in: root, store: store)
        let model = AppModel(store: store)
        try await open(book, model: model)
        model.goToPage(3); model.completeReading(book)
        model.showReadingShelf(.finished)
        XCTAssertEqual(model.shelfBooks.map(\.id), [book.id])
        try await open(book, model: model)
        XCTAssertEqual(model.page, 3)
        XCTAssertEqual(model.readingSummary(book).status, .finished)
        model.startReading(book)
        XCTAssertEqual(model.page, 1)
        model.showReadingShelf()
        XCTAssertEqual(try store.book(book.id).lastPage, 1)
        XCTAssertEqual(model.readingSummary(book).label, "2회독 중")
        model.completeReading(book); model.completeReading(book)
        XCTAssertEqual(model.readingSummary(book).completedCount, 2)
    }

    func testSortDirectionPersistsAcrossShelvesAndRestartAndCountsUpdateAfterEditing() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let alpha = try fixture("Alpha", in: root, store: store)
        let beta = try fixture("Beta", in: root, store: store)
        let model = AppModel(store: store)
        model.setSort(.title); model.setSortAscending(false)
        XCTAssertEqual(model.filteredBooks.map(\.id), [beta.id, alpha.id])
        model.showReadingShelf(.unread)
        XCTAssertEqual(model.shelfBooks.map(\.id), [beta.id, alpha.id])
        let restarted = AppModel(store: try LibraryStore(directory: store.directory))
        XCTAssertEqual(restarted.sortPreferences.criterion, .title)
        XCTAssertFalse(restarted.sortPreferences.ascending)
        XCTAssertEqual(restarted.filteredBooks.map(\.id), [beta.id, alpha.id])
        try await open(alpha, model: model)
        model.editNotebook("메모 한 개"); model.showReadingShelf()
        XCTAssertEqual(model.noteCount(alpha).total, 1)
        model.setSort(.notes)
        XCTAssertEqual(model.filteredBooks.map(\.id), [alpha.id, beta.id])
        model.selection = [Highlight(bookID: alpha.id, page: 2, quote: "또 하나의 메모")]
        model.saveSelection()
        XCTAssertEqual(model.noteCount(alpha).total, 2)
        model.deleteHighlight(try XCTUnwrap(model.highlights.first))
        XCTAssertEqual(model.noteCount(alpha).total, 1)
        model.completeReading(beta); model.setSort(.readCount)
        XCTAssertEqual(model.filteredBooks.map(\.id), [beta.id, alpha.id])
        model.showReadingShelf(.finished)
        XCTAssertEqual(model.sortPreferences.criterion, .readCount)
        model.libraryQuery = "no match"
        XCTAssertTrue(model.shelfBooks.isEmpty)
    }

    func testCompletionCannotLoseConflictingUnsavedNotes() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let book = try fixture("Protected draft", in: root, store: store)
        let model = AppModel(store: store)
        try await open(book, model: model)
        model.editNotebook("내 초안")
        try store.saveNotebook(bookID: book.id, body: "외부 수정", expectedRevision: 0)
        model.completeReading(book)
        XCTAssertEqual(model.readingSummary(book).completedCount, 0)
        XCTAssertEqual(model.notebookText, "내 초안")
        XCTAssertTrue(model.hasUnsavedChanges)
    }

}
