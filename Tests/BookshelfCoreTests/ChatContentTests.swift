import XCTest
@testable import BookshelfCore

final class ChatContentTests: XCTestCase {
    func testVisualFencesPreserveLinesAndTablesStayOutsideCode() {
        let text = """
        핵심 관계입니다.
        ```mermaid
        flowchart TD
          A["자극"] --> B["반응"]
        ```
        | 조건 | 결과 |
        | --- | --- |
        | 있음 | 반응 |
        ```html
        <button onclick="this.textContent='확인'">눌러보기</button>
        ```
        ![그림](https://example.org/picture.png)
        [설명 듣기](https://example.org/lesson.m4a?download=1)
        """
        let blocks = ChatContent.blocks(text)
        XCTAssertEqual(blocks.map(\.kind), ["text", "mermaid", "text", "html", "image", "audio"])
        XCTAssertTrue(blocks[1].source.contains("\n  A"))
        XCTAssertEqual(blocks[4].source, "https://example.org/picture.png")
        XCTAssertEqual(blocks[5].label, "설명 듣기")
    }
    func testStreamingFenceIsNotRenderedUntilClosedAndRawSVGIsSupported() {
        let partial = ChatContent.blocks("```mermaid\nflowchart TD\nA --> B")
        XCTAssertEqual(partial.first?.kind, "mermaid")
        XCTAssertEqual(partial.first?.complete, false)
        XCTAssertEqual(ChatContent.blocks("~~~svg\n<svg></svg>\n~~~").first?.complete, true)
        XCTAssertEqual(ChatContent.blocks("<svg viewBox=\"0 0 20 20\">\n<circle r=\"5\"/>\n</svg>\n설명").map(\.kind), ["svg", "text"])
    }
    func testImportedMediaSurvivesSourceMoveAndCannotResolveEscapingPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("설명.wav"), directory = root.appendingPathComponent("data")
        try Data("authored audio fixture".utf8).write(to: file)
        let asset = try ChatAssetStore.importFile(file, directory: directory)
        try FileManager.default.removeItem(at: file)
        let saved = try XCTUnwrap(ChatAssetStore.url(for: asset, directory: directory))
        XCTAssertEqual(try Data(contentsOf: saved), Data("authored audio fixture".utf8))
        var invalid = asset; invalid.fileName = "../" + asset.fileName
        XCTAssertNil(ChatAssetStore.url(for: invalid, directory: directory))
        let outside = root.appendingPathComponent("outside.wav")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.removeItem(at: saved)
        try FileManager.default.createSymbolicLink(at: saved, withDestinationURL: outside)
        XCTAssertNil(ChatAssetStore.url(for: asset, directory: directory))
    }
    func testUsageAndMediaRoundTripWithoutBreakingOlderMessages() throws {
        let old = #"{"id":"old","role":"assistant","text":"이전 답변","backend":"claude","page":1,"state":"complete","created":1}"#
        var message = try JSONDecoder().decode(BookChatMessage.self, from: Data(old.utf8))
        XCTAssertNil(message.usage); XCTAssertNil(message.attachments)
        message.usage = AgentContextUsage(model: "reported-model", inputTokens: 2000, outputTokens: 400, contextWindow: 200000, cachedInputTokens: 1000)
        message.attachments = [ChatAttachment(id: "a", name: "자료.wav", fileName: "a.wav", kind: "audio")]
        let restored = try JSONDecoder().decode(BookChatMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(restored, message)
        XCTAssertEqual(restored.usage?.fraction ?? 0, 0.012, accuracy: 0.00001)
        XCTAssertNil(AgentContextUsage(inputTokens: 100, outputTokens: 20).fraction)
    }
}
