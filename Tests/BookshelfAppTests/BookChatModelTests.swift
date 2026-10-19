import XCTest
import BookshelfCore
@testable import BookshelfApp

@MainActor final class BookChatModelTests: XCTestCase {
    func testReadingScopeAndSourcesSurviveReopenAndIgnoreStaleCoverage() async throws {
        guard let node = AgentRuntime.findExecutable("node") else { throw XCTSkip("Node.js not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let file = root.appendingPathComponent("Book.pdf"); try Data("authored".utf8).write(to: file)
        let book = try store.register(source: file, ocr: nil, root: root)
        var prior = BookChatMessage(role: "assistant", text: "Old evidence from page 1", backend: "claude", page: 1)
        prior.scope = .init(mode: "book", startPage: 1, endPage: 6)
        _ = try store.saveConversation(bookID: book.id, messages: [prior], expectedRevision: 0)
        let script = root.appendingPathComponent("reading.mjs")
        try """
        let input='';process.stdin.on('data',c=>input+=c);process.stdin.on('end',()=>{
          const r=JSON.parse(input);if(r.book.text||r.messages.length||r.book.scope.startPage!==3)process.exit(3);
          const emit=e=>console.log(JSON.stringify(e));
          for(const [bookID,pages] of [[r.book.id,[4]],[r.book.id,[3]],['another-book',[5]]])emit({type:'reading',reading:{bookID,scope:r.book.scope,readPages:pages,sourcePages:pages,emptyPages:[]}});
          emit({type:'answer',text:'Verified [p. 3] and [p. 4]'});emit({type:'done'});
        });
        """.write(to: script, atomically: true, encoding: .utf8)
        let chat = BookChatModel(store: store, bridgeFactory: { AgentBridge(executable: node, script: script) })
        XCTAssertTrue(chat.selectBook(book.id)); XCTAssertEqual(chat.scopeMode, "book")
        chat.draft = "Find evidence within this range"
        let scope = BookReadingScope(mode: "range", startPage: 3, endPage: 5)
        chat.send(context: AgentRequest.Context(id: book.id, title: book.title, page: 1, text: "Outside the selected range", notes: "", selection: "", scope: scope))
        for _ in 0..<200 where chat.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(chat.errorMessage); XCTAssertEqual(chat.messages.last?.scope, scope)
        XCTAssertEqual(chat.messages.last?.reading?.readPages, [3,4]); XCTAssertEqual(chat.messages.last?.sourcePages, [3,4])
        let restored = BookChatModel(store: try LibraryStore(directory: store.directory))
        XCTAssertTrue(restored.selectBook(book.id)); XCTAssertEqual(restored.messages.last?.sourcePages, [3,4])
        XCTAssertEqual(restored.messages.last?.scope, scope)
    }
    func testAutoModeReceivesGeneratedImageAndReopensItAfterUndo() async throws {
        guard let node = AgentRuntime.findExecutable("node") else { throw XCTSkip("Node.js not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let file = root.appendingPathComponent("Book.pdf"); try Data("authored".utf8).write(to: file)
        let book = try store.register(source: file, ocr: nil, root: root)
        let script = root.appendingPathComponent("image.mjs")
        try """
        import fs from 'node:fs';import {join} from 'node:path';import {randomUUID} from 'node:crypto';
        let input='';process.stdin.on('data',c=>input+=c);process.stdin.on('end',()=>{
          const r=JSON.parse(input);if(r.skill!=='auto'||r.backend!=='codex')process.exit(3);
          const id=randomUUID(),fileName=id+'.png';fs.mkdirSync(r.assetDirectory,{recursive:true});
          fs.writeFileSync(join(r.assetDirectory,fileName),Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==','base64'));
          const emit=e=>console.log(JSON.stringify(e));emit({type:'activity',message:'이미지 생성 중'});
          emit({type:'attachment',attachment:{id,name:'Codex 생성 이미지',fileName,kind:'image'}});
          emit({type:'answer',text:''});emit({type:'done'});
        });
        """.write(to: script, atomically: true, encoding: .utf8)
        let chat = BookChatModel(store: store, bridgeFactory: { AgentBridge(executable: node, script: script) })
        chat.chooseBackend(.codex, checkStatus: false); XCTAssertEqual(chat.skill, "auto")
        XCTAssertTrue(chat.selectBook(book.id)); chat.draft = "이미지로 설명해줘"
        chat.send(context: AgentRequest.Context(id: book.id, title: book.title, page: 1, text: "reference", notes: "", selection: ""))
        for _ in 0..<200 where chat.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(chat.busy); XCTAssertNil(chat.errorMessage); XCTAssertEqual(chat.activityMessage, "")
        XCTAssertEqual(chat.messages.last?.state, "complete")
        let attachment = try XCTUnwrap(chat.messages.last?.attachments?.first)
        XCTAssertNotNil(ChatAssetStore.generatedImageURL(for: attachment, directory: store.directory))
        chat.clearConversation(); XCTAssertTrue(chat.messages.isEmpty); chat.undoEdit()
        XCTAssertEqual(chat.messages.last?.attachments?.first, attachment)
        let reopened = BookChatModel(store: try LibraryStore(directory: store.directory))
        XCTAssertTrue(reopened.selectBook(book.id))
        XCTAssertEqual(reopened.messages.last?.attachments?.first, attachment)
        var escaping = attachment; escaping.fileName = "../" + attachment.fileName
        XCTAssertNil(ChatAssetStore.generatedImageURL(for: escaping, directory: store.directory))
        let validURL = try XCTUnwrap(ChatAssetStore.url(for: attachment, directory: store.directory))
        try Data("not a PNG".utf8).write(to: validURL)
        XCTAssertNil(ChatAssetStore.generatedImageURL(for: attachment, directory: store.directory))
    }
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
