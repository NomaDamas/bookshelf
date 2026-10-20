import XCTest
import PDFKit
import CoreText
import AppKit
@testable import BookshelfCore

final class PretestQuestionsTests: XCTestCase {
    private func reply(_ questions: [(String, Int, String)], fence: String = "```", before: String = "읽기 전에 추측해 보세요.") -> String {
        let items = questions.map { #"{"question":"\#($0.0)","answerPage":\#($0.1),"answer":"\#($0.2)"}"# }
        return before + "\n\n" + fence + "pretest\n{\"questions\":[" + items.joined(separator: ",") + "]}\n" + fence + "\n"
    }
    private let range = BookReadingScope(mode: "range", startPage: 5, endPage: 8)

    func testOnlyQuestionsAnsweredOnAPageAheadThatPiReadSurvive() throws {
        let text = reply([("박자는 무엇으로 맞출까요?", 6, "방울 소리로 맞춘다."), ("지금 쪽의 질문", 5, "현재 쪽"), ("앞 장의 질문", 3, "앞 장"),
                          ("범위 밖 질문", 9, "다음 장"), ("읽지 않은 쪽 질문", 7, "읽지 않음"), ("겨울에는 어떻게 할까요?", 8, "박자를 늦춘다.")])
        let result = PretestBlock.extract(text, askedOn: 5, scope: range, sourcePages: [5, 6, 8, 9])
        XCTAssertEqual(result.text, "읽기 전에 추측해 보세요.", "The block and its answers never stay in the reply text")
        let set = try XCTUnwrap(result.set)
        XCTAssertEqual(set.questions.map(\.answerPage), [6, 8]); XCTAssertEqual(set.dropped, 4)
        XCTAssertEqual(set.questions.first?.answer, "방울 소리로 맞춘다."); XCTAssertNil(set.questions.first?.revealed)
        XCTAssertNil(set.questions.first?.guess)
        let book = PretestBlock.extract(text, askedOn: 5, scope: nil, sourcePages: [6, 7, 8, 9])
        XCTAssertEqual(book.set?.questions.map(\.answerPage), [6, 9, 7], "Without a range any later page counts; at most three are kept")
        XCTAssertEqual(book.set?.dropped, 3)
    }
    func testMalformedOrMissingBlocksNeverShowTheirContent() {
        XCTAssertNil(PretestBlock.extract("그냥 답", askedOn: 1, scope: nil, sourcePages: []).set)
        XCTAssertEqual(PretestBlock.extract("그냥 답", askedOn: 1, scope: nil, sourcePages: []).text, "그냥 답")
        let broken = PretestBlock.extract("추측해 보세요.\n```pretest\n{\"questions\":[{\"question\":\"Q\"}]}\n```", askedOn: 1, scope: nil, sourcePages: [2])
        XCTAssertEqual(broken.text, "추측해 보세요."); XCTAssertNil(broken.set)
        let unclosed = PretestBlock.extract("추측해 보세요.\n```pretest\n{\"questions\":[{\"answer\":\"숨길 답", askedOn: 1, scope: nil, sourcePages: [2])
        XCTAssertEqual(unclosed.text, "추측해 보세요."); XCTAssertNil(unclosed.set)
        let tilde = PretestBlock.extract(reply([("Q", 2, "A")], fence: "~~~~", before: "앞\n```mermaid\nflowchart TD\n```"), askedOn: 1, scope: nil, sourcePages: [2])
        XCTAssertEqual(tilde.text, "앞\n```mermaid\nflowchart TD\n```", "Other fenced blocks stay")
        XCTAssertEqual(tilde.set?.questions.count, 1)
    }
    func testStreamingHidesTheBlockAndAFenceThatMayStillOpenIt() {
        XCTAssertEqual(PretestBlock.streamingText("추측해 보세요.\n```pretest\n{\"questions\":[{\"answer\":\"방울"), "추측해 보세요.")
        XCTAssertEqual(PretestBlock.streamingText("추측해 보세요.\n```pre"), "추측해 보세요.")
        XCTAssertEqual(PretestBlock.streamingText("추측해 보세요.\n``"), "추측해 보세요.")
        XCTAssertEqual(PretestBlock.streamingText("추측해 보세요.\n```merm"), "추측해 보세요.\n```merm", "Another block's fence is not held back")
        XCTAssertEqual(PretestBlock.streamingText("추측해 보세요"), "추측해 보세요")
    }
    func testUnreachedAnswersStayOutOfHistoryAndCopies() throws {
        var message = BookChatMessage(role: "assistant", text: "추측해 보세요.", backend: "claude", page: 5, skill: "pretest")
        var set = PretestSet(questions: [PretestQuestion(question: "박자는?", answerPage: 6, answer: "방울 소리"), PretestQuestion(question: "겨울에는?", answerPage: 8, answer: "은바늘")])
        set.questions[0].guess = "북소리"; set.questions[0].revealed = 1; set.questions[1].guess = "모름"
        message.pretest = set
        XCTAssertTrue(message.conversationText.contains("Reader's guess: 북소리")); XCTAssertTrue(message.conversationText.contains("[p. 6]: 방울 소리"))
        XCTAssertTrue(message.conversationText.contains("Reader's guess: 모름"))
        XCTAssertFalse(message.conversationText.contains("은바늘")); XCTAssertFalse(message.conversationText.contains("p. 8"))
        XCTAssertTrue(message.transcriptText.contains("답(6쪽): 방울 소리"))
        XCTAssertTrue(message.transcriptText.contains("답: 아직 읽지 않은 쪽에 있습니다.")); XCTAssertFalse(message.transcriptText.contains("은바늘"))
        let decoded = try JSONDecoder().decode(BookChatMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.pretest, set, "Questions, guesses and reveals are saved with the conversation")
        let old = try JSONDecoder().decode(BookChatMessage.self, from: Data(#"{"id":"a","role":"assistant","text":"t","backend":"claude","page":1,"state":"complete","created":1}"#.utf8))
        XCTAssertNil(old.pretest, "Conversations saved before pre-reading questions still load")
        var crashed = BookChatMessage(role: "assistant", text: reply([("Q", 6, "숨길 답")]), backend: "claude", page: 5, state: "interrupted", skill: "pretest")
        XCTAssertFalse(crashed.visibleText.contains("숨길 답")); XCTAssertFalse(crashed.transcriptText.contains("숨길 답"))
        crashed.skill = "auto"; XCTAssertTrue(crashed.visibleText.contains("숨길 답"), "Only pretest replies hide the block")
    }
    func testChapterStartsComeFromTheSameOutlinePiReads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var box = CGRect(x: 0, y: 0, width: 400, height: 400)
        let url = root.appendingPathComponent("Outlined.pdf")
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for page in 1...11 {
            context.beginPDFPage(nil); context.textPosition = CGPoint(x: 20, y: 360)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "Page \(page)", attributes: [.font: NSFont.systemFont(ofSize: 12)])), context)
            context.endPDFPage()
        }
        context.closePDF()
        let pdf = try XCTUnwrap(PDFDocument(url: url)), outline = PDFOutline()
        func entry(_ title: String, _ page: Int) -> PDFOutline {
            let item = PDFOutline(); item.label = title; item.destination = PDFDestination(page: pdf.page(at: page - 1)!, at: .zero); return item
        }
        let two = entry("2장", 5)
        for (index, child) in [entry("2장 시작", 5), entry("2.2", 7), entry("2.3", 8)].enumerated() { two.insertChild(child, at: index) }
        for (index, child) in [entry("1장", 2), two, entry("3장", 9), entry("부록", 11)].enumerated() { outline.insertChild(child, at: index) }
        pdf.outlineRoot = outline; XCTAssertTrue(pdf.write(to: url))
        let reopened = try XCTUnwrap(PDFDocument(url: url)), entries = BookOutline.entries(in: reopened)
        XCTAssertEqual(entries.map(\.endPage), [4, 8, 6, 7, 8, 10, 11], "An entry ends before the next one at its depth or shallower")
        XCTAssertEqual((1...11).compactMap { BookOutline.chapter(startingAt: $0, in: entries)?.startPage }, [2, 5, 9],
                       "One-page sections and the one-page appendix have no pages ahead to ask about")
        XCTAssertEqual(BookOutline.chapter(startingAt: 5, in: entries).map { [$0.title, "\($0.endPage)"] }, ["2장", "8"], "The outermost entry wins")
        XCTAssertTrue(BookOutline.entries(in: PDFDocument()).isEmpty)
        // The offer and get_book_overview must name the same chapter starts for the same PDF.
        let book = try LibraryStore(directory: root.appendingPathComponent("data")).register(source: url, ocr: nil, root: root)
        let session = try BookReadingSession(book: book, scope: .init(mode: "book", startPage: 1, endPage: 11))
        let raw = try await session.call("get_book_overview")
        let overview = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        let tool = try XCTUnwrap(overview["outline"] as? [[String: Any]]).map {
            BookOutlineEntry(title: $0["title"] as? String ?? "", startPage: $0["startPage"] as? Int ?? 0, endPage: $0["endPage"] as? Int ?? 0, depth: $0["depth"] as? Int ?? 0)
        }
        XCTAssertEqual(tool, entries)
        XCTAssertEqual((1...11).compactMap { BookOutline.chapter(startingAt: $0, in: tool)?.startPage }, [2, 5, 9])
    }
}
