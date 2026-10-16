import XCTest
import BookshelfCore
@testable import BookshelfApp

@MainActor final class BookChatModelTests: XCTestCase {
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
