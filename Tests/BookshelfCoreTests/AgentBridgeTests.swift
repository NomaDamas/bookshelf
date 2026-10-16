import XCTest
@testable import BookshelfCore

final class AgentBridgeTests: XCTestCase {
    func testNativeBridgeReceivesUnicodeEventsAndKeepsSecretsOutOfChildEnvironment() async throws {
        guard let node = AgentRuntime.findExecutable("node") else { throw XCTSkip("Node.js not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("fixture.mjs")
        try """
        let input=''; process.stdin.setEncoding('utf8');
        process.stdin.on('data',chunk=>input+=chunk);
        process.stdin.on('end',()=>{
          const request=JSON.parse(input);
          if(process.env.OPENAI_API_KEY || process.env.ANTHROPIC_API_KEY || process.env.CLAUDE_CODE_OAUTH_TOKEN) process.exit(3);
          const result=Buffer.from(JSON.stringify({type:'answer',text:request.book.title+' 설명'})+'\\n'+JSON.stringify({type:'done'})+'\\n');
          for(let i=0;i<result.length;i+=2) process.stdout.write(result.subarray(i,i+2));
        });
        """.write(to: script, atomically: true, encoding: .utf8)
        let context = AgentRequest.Context(id: "synthetic", title: "테스트 책", page: 1, text: "원문", notes: "", selection: "")
        let request = AgentRequest(action: "chat", backend: .claude, directory: root, question: "설명해줘", book: context)
        let bridge = AgentBridge(executable: node, script: script)
        var events: [AgentEvent] = []
        for try await event in bridge.events(for: request) { events.append(event) }
        XCTAssertEqual(events.map(\.type), ["answer", "done"])
        XCTAssertEqual(events.first?.text, "테스트 책 설명")
    }
}
