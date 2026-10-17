import XCTest
import BookshelfCore
@testable import BookshelfApp

@MainActor final class BookChatModelTests: XCTestCase {
    func testEditingUsesTheOriginalPageAndKeepsTheUnsentDraftAndUndo() async throws {
        guard let node = AgentRuntime.findExecutable("node") else { throw XCTSkip("Node.js not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let file = root.appendingPathComponent("Book.pdf"); try Data("authored".utf8).write(to: file)
        let book = try store.register(source: file, ocr: nil, root: root)
        let old = [BookChatMessage(role: "user", text: "old question", backend: "claude", page: 3), BookChatMessage(role: "assistant", text: "old answer", backend: "claude", page: 3)]
        try store.saveConversation(bookID: book.id, messages: old, expectedRevision: 0)
        let script = root.appendingPathComponent("reply.mjs")
        try """
        let input='';process.stdin.on('data',c=>input+=c);process.stdin.on('end',()=>{
          const r=JSON.parse(input);if(r.book.page!==3||r.question!=='new question'||r.messages.length)process.exit(3);
          console.log(JSON.stringify({type:'answer',text:'new answer'}));console.log(JSON.stringify({type:'done'}));
        });
        """.write(to: script, atomically: true, encoding: .utf8)
        let model = BookChatModel(store: store, bridgeFactory: { AgentBridge(executable: node, script: script) })
        XCTAssertTrue(model.selectBook(book.id)); model.draft = "my next unsent question"
        model.reviseQuestion(old[0].id, text: "new question", context: AgentRequest.Context(id: book.id, title: book.title, page: 3, text: "reference", notes: "", selection: ""))
        for _ in 0..<200 where model.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.busy); XCTAssertEqual(model.messages.last?.text, "new answer")
        XCTAssertEqual(model.draft, "my next unsent question")
        model.undoEdit(); XCTAssertEqual(model.messages, old)
        XCTAssertEqual(model.draft, "my next unsent question")
    }
    func testSwitchingBooksCancelsOldReplyAndPreservesPerBookDrafts() async throws {
        guard let node = AgentRuntime.findExecutable("node") else { throw XCTSkip("Node.js not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        var books: [Book] = []
        for name in ["First", "Second"] {
            let file = root.appendingPathComponent(name + ".pdf")
            try Data(name.utf8).write(to: file)
            books.append(try store.register(source: file, ocr: nil, root: root))
        }
        let script = root.appendingPathComponent("delayed.mjs")
        try """
        process.stdin.resume();process.stdin.on('end',()=>setTimeout(()=>{
          console.log(JSON.stringify({type:'answer',text:'late reply from the first book'}));
          console.log(JSON.stringify({type:'done'}));
        },400));
        """.write(to: script, atomically: true, encoding: .utf8)
        let chat = BookChatModel(store: store, bridgeFactory: { AgentBridge(executable: node, script: script) })
        XCTAssertTrue(chat.selectBook(books[0].id)); chat.draft = "첫 책의 질문"
        chat.send(context: AgentRequest.Context(id: books[0].id, title: books[0].title, page: 1, text: "First", notes: "", selection: ""))
        try await Task.sleep(for: .milliseconds(60))
        chat.draft = "첫 책의 다음 질문 초안"
        XCTAssertTrue(chat.selectBook(books[1].id)); chat.draft = "두 번째 책의 초안"
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertEqual(chat.draft, "두 번째 책의 초안")
        XCTAssertTrue(try store.conversation(bookID: books[1].id).messages.isEmpty)
        let first = try store.conversation(bookID: books[0].id)
        XCTAssertEqual(first.messages.first?.text, "첫 책의 질문")
        XCTAssertEqual(first.messages.last?.state, "interrupted")
        XCTAssertFalse(first.messages.contains { $0.text == "late reply from the first book" })
        XCTAssertTrue(chat.selectBook(books[0].id))
        XCTAssertEqual(chat.draft, "첫 책의 다음 질문 초안")
    }
}
