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
    func testStatusCheckRunsWithoutLockingThePanel() async throws {
        guard let node = AgentRuntime.findExecutable("node") else { throw XCTSkip("Node.js not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let file = root.appendingPathComponent("Book.pdf"); try Data("authored".utf8).write(to: file)
        let book = try store.register(source: file, ocr: nil, root: root)
        let script = root.appendingPathComponent("status.mjs")
        try """
        let input='';process.stdin.on('data',c=>input+=c);process.stdin.on('end',()=>{
          const r=JSON.parse(input);if(r.action!=='status'||r.backend!=='claude')process.exit(3);
          setTimeout(()=>{console.log(JSON.stringify({type:'status',status:{connected:true,billing:'subscription',label:'Claude 연결됨'}}));
            console.log(JSON.stringify({type:'done'}));},300);
        });
        """.write(to: script, atomically: true, encoding: .utf8)
        let chat = BookChatModel(store: store, bridgeFactory: { AgentBridge(executable: node, script: script) })
        XCTAssertTrue(chat.selectBook(book.id)); XCTAssertFalse(chat.checkedBackends.contains(.claude))
        chat.checkConnection()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(chat.checkingStatus); XCTAssertFalse(chat.busy); XCTAssertEqual(chat.operation, "")
        for _ in 0..<300 where chat.checkingStatus { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(chat.checkingStatus); XCTAssertNil(chat.errorMessage)
        XCTAssertEqual(chat.account?.connected, true); XCTAssertTrue(chat.checkedBackends.contains(.claude))
    }
    func testSettingsLoginKeepsTheConversationEngine() async throws {
        guard let node = AgentRuntime.findExecutable("node") else { throw XCTSkip("Node.js not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let script = root.appendingPathComponent("login.mjs")
        try """
        let input='';process.stdin.on('data',c=>input+=c);process.stdin.on('end',()=>{
          const r=JSON.parse(input);if(r.action!=='login'||r.backend!=='codex')process.exit(3);
          console.log(JSON.stringify({type:'status',status:{connected:true,billing:'subscription',label:'ChatGPT 연결됨'}}));
          console.log(JSON.stringify({type:'done'}));
        });
        """.write(to: script, atomically: true, encoding: .utf8)
        let chat = BookChatModel(store: store, bridgeFactory: { AgentBridge(executable: node, script: script) })
        XCTAssertEqual(chat.backend, .claude)
        chat.login(using: .codex)
        XCTAssertTrue(chat.busy); XCTAssertEqual(chat.operation, "login"); XCTAssertEqual(chat.loginBackend, .codex)
        XCTAssertEqual(chat.backend, .claude)
        for _ in 0..<300 where chat.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(chat.busy); XCTAssertNil(chat.errorMessage)
        XCTAssertEqual(chat.accounts[.codex]?.connected, true); XCTAssertNil(chat.accounts[.claude])
        XCTAssertEqual(chat.backend, .claude); XCTAssertNotEqual(try store.setting("agent.backend"), "codex")
    }
    func testComposerExplainsWhySendingIsUnavailable() {
        func block(node: Bool = true, bridge: Bool = true, connected: Bool? = true, checking: Bool = false, operation: String = "",
                   document: Bool = true, range: Bool = false, editing: Bool = false, draft: String = "질문") -> PiComposerBlock? {
            PiComposerBlock.evaluate(nodeFound: node, bridgeFound: bridge, backend: .claude, connected: connected, checking: checking,
                                     operation: operation, documentReady: document, choosingRange: range, editing: editing, draft: draft)
        }
        XCTAssertNil(block()); XCTAssertNil(block(draft: ""))
        XCTAssertEqual(block(bridge: false, connected: nil), .bridgeMissing)
        XCTAssertEqual(block(node: false, connected: nil), .nodeMissing)
        XCTAssertEqual(block(connected: nil, checking: true), .checkingAccount(.claude))
        XCTAssertEqual(block(connected: nil), .accountUnknown(.claude))
        XCTAssertEqual(block(connected: false), .accountDisconnected(.claude))
        XCTAssertEqual(block(connected: false, checking: true, operation: "login"), .signingIn(.claude))
        XCTAssertEqual(block(document: false), .documentLoading)
        XCTAssertEqual(block(range: true), .choosingRange)
        XCTAssertEqual(block(editing: true), .editingQuestion)
        XCTAssertEqual(block(draft: String(repeating: "가", count: 10001)), .tooLong)
        XCTAssertTrue(PiComposerBlock.accountDisconnected(.codex).needsConnection)
        XCTAssertTrue(PiComposerBlock.nodeMissing.needsConnection)
        XCTAssertFalse(PiComposerBlock.checkingAccount(.codex).needsConnection)
        XCTAssertFalse(PiComposerBlock.choosingRange.needsConnection)
        XCTAssertEqual(BookReadingScope(mode: "book", startPage: 1, endPage: 90).composerLabel(currentPage: 27), "이 책 전체, 27쪽에서")
        XCTAssertEqual(BookReadingScope(mode: "page", startPage: 27, endPage: 27).composerLabel(currentPage: 27), "현재 쪽(27쪽)")
        XCTAssertEqual(BookReadingScope(mode: "range", startPage: 27, endPage: 40).composerLabel(currentPage: 30), "27~40쪽")
        XCTAssertEqual(PiExplanation(skill: "auto").title, "자동"); XCTAssertEqual(PiExplanation(skill: "unknown"), .auto)
        XCTAssertEqual(PiExplanation.allCases.map(\.title), ["자동", "쉽게 설명", "비교표", "시각 자료", "막힌 곳 찾기", "내 설명 점검"])
    }
    func testStartingPromptsSwitchTutoringModesWithoutSending() throws {
        XCTAssertEqual(PiStarter.all(selection: "").map(\.title), ["이 페이지 쉽게 설명해줘", "이 장 핵심 정리해줘", "확인 퀴즈 내줘", "내 설명 점검받기"])
        XCTAssertEqual(PiStarter.all(selection: " \n ").count, 4, "Whitespace is not a selected sentence")
        let stuck = try XCTUnwrap(PiStarter.all(selection: "드립 속도는\n  수두에 따라 변한다.").first)
        XCTAssertEqual(stuck.title, "선택한 문장에서 막혔어요"); XCTAssertEqual(stuck.mode, .trace)
        XCTAssertTrue(stuck.prompt.hasPrefix("“드립 속도는 수두에 따라 변한다.”\n"), "The stuck sentence stays in the question history")
        let long = PiStarter.trace(selection: String(repeating: "가", count: 500)).prompt
        XCTAssertTrue(long.contains(String(repeating: "가", count: 200) + "…”")); XCTAssertFalse(long.contains(String(repeating: "가", count: 201)))
        XCTAssertEqual(PiStarter.check.mode, .check); XCTAssertTrue(PiStarter.check.prompt.hasSuffix("내 설명: "))
        // A tutoring chip switches the mode; a plain prompt leaves a tutoring mode but keeps a chosen format.
        XCTAssertEqual(PiExplanation.compare.starting(.trace), .trace)
        XCTAssertEqual(PiExplanation.trace.starting(nil), .auto)
        XCTAssertEqual(PiExplanation.check.starting(nil), .auto)
        XCTAssertEqual(PiExplanation.compare.starting(nil), .compare)
        XCTAssertEqual(PiExplanation.allCases.filter(\.isTutoring), [.trace, .check])
        XCTAssertNotEqual(PiExplanation.trace.placeholder, PiExplanation.auto.placeholder)
    }
    func testTutoringModeLastsForTheConversationAndEndsOnClearOrBookSwitch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        var books: [Book] = []
        for name in ["A", "B"] {
            let file = root.appendingPathComponent(name + ".pdf"); try Data(name.utf8).write(to: file)
            books.append(try store.register(source: file, ocr: nil, root: root))
        }
        let chat = BookChatModel(store: store)
        XCTAssertTrue(chat.selectBook(books[0].id))
        chat.skill = "trace"; XCTAssertTrue(chat.selectBook(books[0].id)); XCTAssertEqual(chat.skill, "trace", "Reselecting the same book keeps the trace")
        XCTAssertTrue(chat.selectBook(books[1].id)); XCTAssertEqual(chat.skill, "auto")
        chat.skill = "check"; chat.clearConversation(); XCTAssertEqual(chat.skill, "auto")
        chat.skill = "visualize"; XCTAssertTrue(chat.selectBook(books[0].id)); chat.clearConversation()
        XCTAssertEqual(chat.skill, "visualize", "Plain explanation formats are a standing preference")
    }
    func testOnlyTheReplyThatChangedIsRebuiltWhileAnotherStreams() {
        let finished = ChatResponseView(text: "답 [p. 3]", streaming: false, sourcePages: [3]) { _ in }
        XCTAssertEqual(finished, ChatResponseView(text: "답 [p. 3]", streaming: false, sourcePages: [3]) { _ in XCTFail() },
                       "A new page-selection closure alone must not re-parse a finished reply")
        XCTAssertNotEqual(finished, ChatResponseView(text: "답 [p. 3] 이어서", streaming: false, sourcePages: [3]), "Each streamed delta must reach the reply")
        XCTAssertNotEqual(finished, ChatResponseView(text: "답 [p. 3]", streaming: true, sourcePages: [3]))
        XCTAssertNotEqual(finished, ChatResponseView(text: "답 [p. 3]", streaming: false, sourcePages: [3, 4]), "Citation links follow the sources read")
    }
    func testConversationCopyNamesTheExecutorAndModel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let file = root.appendingPathComponent("Book.pdf"); try Data("authored".utf8).write(to: file)
        let book = try store.register(source: file, ocr: nil, root: root)
        var answer = BookChatMessage(role: "assistant", text: "답", backend: "claude", page: 27); answer.model = "sonnet"
        var material = BookChatMessage(role: "user", text: "", backend: "local", page: 27)
        material.attachments = [ChatAttachment(id: "a", name: "강의.m4a", fileName: "a.m4a", kind: "audio")]
        let messages = [BookChatMessage(role: "user", text: "질문", backend: "claude", page: 27), answer,
                        BookChatMessage(role: "assistant", text: "다른 답", backend: "codex", page: 27), material,
                        BookChatMessage(role: "assistant", text: "", backend: "claude", page: 27, state: "failed")]
        try store.saveConversation(bookID: book.id, messages: messages, expectedRevision: 0)
        let chat = BookChatModel(store: store)
        XCTAssertTrue(chat.selectBook(book.id))
        XCTAssertEqual(chat.speaker(of: answer), "Claude / sonnet")
        XCTAssertEqual(chat.transcript(), "질문 (27쪽)\n질문\n\nClaude / sonnet\n답\n\nCodex / 자동\n다른 답\n\n자료: 강의.m4a")
    }
    func testToolActivityBecomesPersistentStepsWithResults() async throws {
        guard let node = AgentRuntime.findExecutable("node") else { throw XCTSkip("Node.js not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let file = root.appendingPathComponent("Book.pdf"); try Data("authored".utf8).write(to: file)
        let book = try store.register(source: file, ocr: nil, root: root)
        let script = root.appendingPathComponent("steps.mjs")
        try """
        let input='';process.stdin.on('data',c=>input+=c);process.stdin.on('end',()=>{
          const r=JSON.parse(input),emit=e=>console.log(JSON.stringify(e));
          const reading=(read,source)=>emit({type:'reading',reading:{bookID:r.book.id,scope:r.book.scope,readPages:read,sourcePages:source,emptyPages:[]}});
          emit({type:'activity',message:'책에서 관련 내용을 찾고 있습니다.'});reading([],[3,4]);emit({type:'activity',message:''});
          emit({type:'activity',message:'3~4쪽을 읽고 있습니다.'});reading([3,4],[3,4]);emit({type:'activity',message:''});
          emit({type:'activity',message:'읽은 범위를 확인하고 있습니다.'});reading([3,4],[3,4]);emit({type:'activity',message:''});
          emit({type:'activity',message:'책의 목차를 확인하고 있습니다.'});
          emit({type:'answer',text:'Verified [p. 3]'});emit({type:'done'});
        });
        """.write(to: script, atomically: true, encoding: .utf8)
        let chat = BookChatModel(store: store, bridgeFactory: { AgentBridge(executable: node, script: script) })
        XCTAssertTrue(chat.selectBook(book.id)); chat.draft = "3~5쪽에서 찾아줘"
        let scope = BookReadingScope(mode: "range", startPage: 3, endPage: 5)
        chat.send(context: AgentRequest.Context(id: book.id, title: book.title, page: 1, text: "", notes: "", selection: "", scope: scope))
        for _ in 0..<200 where chat.busy { try await Task.sleep(for: .milliseconds(10)) }
        let reply = try XCTUnwrap(chat.messages.last)
        XCTAssertNil(chat.errorMessage); XCTAssertNotNil(reply.finished)
        let steps = try XCTUnwrap(reply.steps)
        XCTAssertEqual(steps.map(\.title), ["책 검색", "책 읽기", "읽은 범위 확인", "목차 확인"])
        XCTAssertEqual(steps.map(\.detail), [nil, "3~4쪽", nil, nil])
        XCTAssertEqual(steps.map(\.result), ["관련 쪽 2곳 찾음", "2쪽 읽음", "본문 2/3쪽 확인", nil])
        // The outline call never reported its end; a completed reply settles it as done.
        XCTAssertEqual(steps.map(\.state), ["done", "done", "done", "done"])
        let reopened = BookChatModel(store: try LibraryStore(directory: store.directory))
        XCTAssertTrue(reopened.selectBook(book.id)); XCTAssertEqual(reopened.messages.last?.steps, steps)
    }
    func testStepWordingFollowsTheBridgeSentences() {
        XCTAssertEqual(PiStepWording.step(for: "27~29쪽을 읽고 있습니다.").detail, "27~29쪽")
        XCTAssertEqual(PiStepWording.step(for: "5쪽을 읽고 있습니다.").title, "책 읽기")
        XCTAssertEqual(PiStepWording.step(for: "이미지를 만들고 있습니다. 잠시 기다려 주세요.").kind, "image")
        XCTAssertEqual(PiStepWording.step(for: "새로운 작업을 하고 있습니다.").title, "새로운 작업을 하고 있습니다")
        let scope = BookReadingScope(mode: "book", startPage: 1, endPage: 10)
        let before = BookReadingCoverage(bookID: "b", scope: scope, readPages: [1], sourcePages: [1])
        let after = BookReadingCoverage(bookID: "b", scope: scope, readPages: [1], sourcePages: [1, 2], emptyPages: [2])
        XCTAssertEqual(PiStepWording.result(for: PiStepWording.step(for: "2쪽을 읽고 있습니다."), before: before, after: after), "1쪽 일부 읽음, 글자 없는 쪽 1")
        XCTAssertEqual(PiStepWording.result(for: PiStepWording.step(for: "책에서 관련 내용을 찾고 있습니다."), before: after, after: after), "새로 찾은 쪽 없음")
        // Pages read earlier in the session still count for the call that read them again.
        let reread = BookReadingCoverage(bookID: "b", scope: scope, readPages: [1, 2, 3], sourcePages: [1, 2, 3])
        XCTAssertEqual(PiStepWording.result(for: PiStepWording.step(for: "1~3쪽을 읽고 있습니다."), before: reread, after: reread), "3쪽 읽음")
    }
    func testTurnSummaryNamesDurationStateAndSpeaker() {
        XCTAssertEqual(PiTurnWording.duration(8.4), "8초")
        XCTAssertEqual(PiTurnWording.duration(724), "12분 4초")
        XCTAssertEqual(PiTurnWording.duration(3720), "1시간 2분")
        var reply = BookChatMessage(role: "assistant", text: "답", backend: "claude", page: 3)
        let now = Date(timeIntervalSince1970: reply.created + 12)
        reply.finished = reply.created + 12
        XCTAssertEqual(PiTurnWording.finished(reply, speaker: "Claude / Sonnet", now: now),
                       "12초 동안 작업, \(PiTurnWording.clock(reply.created + 12, now: now)) 완료, Claude / Sonnet")
        reply.state = "failed"
        XCTAssertEqual(PiTurnWording.finished(reply, speaker: "Codex / 자동", now: now), "12초 동안 작업, 완료하지 못함, Codex / 자동")
        // Replies saved before turns were timed keep only their state and speaker.
        reply.finished = nil; reply.state = "complete"
        XCTAssertEqual(PiTurnWording.finished(reply, speaker: "Claude / 자동", now: now), "Claude / 자동")
        reply.state = "interrupted"
        XCTAssertEqual(PiTurnWording.finished(reply, speaker: "Claude / 자동", now: now), "중단됨, Claude / 자동")
        XCTAssertEqual(PiTurnWording.running(started: 100, writing: false, now: Date(timeIntervalSince1970: 108)), "생각하는 중, 8초")
        XCTAssertEqual(PiTurnWording.running(started: 100, writing: true, now: Date(timeIntervalSince1970: 112)), "답변 쓰는 중, 12초")
    }
}
