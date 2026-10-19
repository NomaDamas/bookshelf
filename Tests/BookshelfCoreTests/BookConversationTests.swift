import XCTest
@testable import BookshelfCore

final class BookConversationTests: XCTestCase {
    func testClearAndEditCanBeUndoneAfterReopenWithoutOverwritingAnotherWriter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Book.pdf"); try Data("authored".utf8).write(to: file)
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let book = try store.register(source: file, ocr: nil, root: root)
        let original = [BookChatMessage(role: "user", text: "첫 질문", backend: "claude", page: 1), BookChatMessage(role: "assistant", text: "첫 답변", backend: "claude", page: 1)]
        _ = try store.saveConversation(bookID: book.id, messages: original, expectedRevision: 0)
        let cleared = try store.saveConversation(bookID: book.id, messages: [], expectedRevision: 1, preservePrevious: true)
        XCTAssertTrue(cleared.messages.isEmpty)
        let reopened = try LibraryStore(directory: store.directory)
        XCTAssertTrue(try reopened.canUndoConversationEdit(bookID: book.id))
        XCTAssertThrowsError(try reopened.undoConversationEdit(bookID: book.id, expectedRevision: 1))
        XCTAssertTrue(try reopened.conversation(bookID: book.id).messages.isEmpty)
        let restored = try reopened.undoConversationEdit(bookID: book.id, expectedRevision: 2)
        XCTAssertEqual(restored.messages, original)
        XCTAssertEqual(restored.revision, 3)
        XCTAssertFalse(try reopened.canUndoConversationEdit(bookID: book.id))
        XCTAssertEqual(try reopened.notebook(bookID: book.id).body, "")
    }
    func testMessagesSavedBeforeStepsStillDecodeAndNewStepsRoundTrip() throws {
        let legacy = #"[{"id":"A","role":"assistant","text":"답","backend":"claude","page":3,"state":"complete","created":1}]"#
        let decoded = try JSONDecoder().decode([BookChatMessage].self, from: Data(legacy.utf8))
        XCTAssertNil(decoded[0].steps); XCTAssertNil(decoded[0].finished); XCTAssertEqual(decoded[0].text, "답")
        var message = decoded[0]
        var step = ChatStep(kind: "read", title: "책 읽기", detail: "3~4쪽", started: 2); step.result = "2쪽 읽음"; step.state = "done"; step.finished = 5
        message.steps = [step]; message.finished = 6
        let again = try JSONDecoder().decode([BookChatMessage].self, from: JSONEncoder().encode([message]))
        XCTAssertEqual(again, [message])
    }
    func testConversationSurvivesReopenAndStaysSeparateFromNotesAndOtherBooks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let firstURL = root.appendingPathComponent("First.pdf"), secondURL = root.appendingPathComponent("Second.pdf")
        try Data("one".utf8).write(to: firstURL); try Data("two".utf8).write(to: secondURL)
        let first = try store.register(source: firstURL, ocr: nil, root: root)
        let second = try store.register(source: secondURL, ocr: nil, root: root)
        let messages = [BookChatMessage(role: "user", text: "설명해줘", backend: "claude", page: 2),
                        BookChatMessage(role: "assistant", text: "근거가 있는 설명 [p. 2]", backend: "claude", page: 2)]
        try store.saveConversation(bookID: first.id, messages: messages, expectedRevision: 0)
        let reloaded = try LibraryStore(directory: store.directory)
        XCTAssertEqual(try reloaded.conversation(bookID: first.id).messages, messages)
        XCTAssertTrue(try reloaded.conversation(bookID: second.id).messages.isEmpty)
        XCTAssertEqual(try reloaded.notebook(bookID: first.id).body, "")
        XCTAssertEqual(try reloaded.noteCounts(bookID: first.id)[first.id]?.total, 0)
    }
    func testStaleConversationWriterCannotReplaceNewerMessages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Book.pdf"); try Data("fixture".utf8).write(to: url)
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let book = try store.register(source: url, ocr: nil, root: root)
        let older = try LibraryStore(directory: store.directory)
        let messages = [BookChatMessage(role: "user", text: "새 질문", backend: "codex", page: 1)]
        try store.saveConversation(bookID: book.id, messages: messages, expectedRevision: 0)
        XCTAssertThrowsError(try older.saveConversation(bookID: book.id, messages: [], expectedRevision: 0))
        XCTAssertEqual(try store.conversation(bookID: book.id).messages, messages)
        var invalid = messages; invalid[0].role = "system"
        XCTAssertThrowsError(try store.saveConversation(bookID: book.id, messages: invalid, expectedRevision: 1))
        XCTAssertEqual(try store.conversation(bookID: book.id).revision, 1)
    }
}
