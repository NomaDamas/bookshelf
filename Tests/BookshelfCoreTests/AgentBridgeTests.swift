import XCTest
@testable import BookshelfCore

final class AgentBridgeTests: XCTestCase {
    func testProcessExitDoesNotRunTimersOnTheWaitingWorker() async throws {
        let result: (Bool, Int32) = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let probe = TimerProbe()
                let timer = Timer(timeInterval: 0.02, repeats: false) { _ in probe.fire() }
                RunLoop.current.add(timer, forMode: .default)
                defer { timer.invalidate() }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", "sleep 0.2; exit 7"]
                let exited = AgentProcessExit(process)
                do {
                    try process.run()
                    exited.wait()
                    continuation.resume(returning: (probe.fired, process.terminationStatus))
                } catch { continuation.resume(throwing: error) }
            }
        }
        XCTAssertFalse(result.0, "Waiting for an executor must not run worker-thread timers that can update PDFKit views")
        XCTAssertEqual(result.1, 7)
    }
    func testBridgeWaitsForFailureAfterTheExecutorClosesStdout() async throws {
        guard let node = AgentRuntime.findExecutable("node") else { throw XCTSkip("Node.js not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("failed-exit.mjs")
        try """
        process.stdin.resume(); process.stdin.on('end',()=>{
          console.log(JSON.stringify({type:'done'}));
          process.stdout.end();
          setTimeout(()=>process.exit(7),200);
        });
        """.write(to: script, atomically: true, encoding: .utf8)
        let bridge = AgentBridge(executable: node, script: script)
        var events: [String] = []
        do {
            for try await event in bridge.events(for: AgentRequest(action: "status", backend: .claude, directory: root)) { events.append(event.type) }
            XCTFail("A nonzero exit after stdout EOF must still report an executor failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("AI 실행기가 종료됐습니다."))
        }
        XCTAssertEqual(events, ["done"])
    }
    func testSmallStreamingEventsArriveBeforeTheExecutorExits() async throws {
        guard let node = AgentRuntime.findExecutable("node") else { throw XCTSkip("Node.js not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("stream.mjs"), marker = root.appendingPathComponent("finished")
        try """
        import {writeFileSync} from 'node:fs';
        process.stdin.resume();process.stdin.on('end',()=>{
          console.log(JSON.stringify({type:'delta',text:'첫 응답'}));
          setTimeout(()=>{writeFileSync(new URL('finished',import.meta.url),'done');console.log(JSON.stringify({type:'done'}));},1800);
        });
        """.write(to: script, atomically: true, encoding: .utf8)
        let bridge = AgentBridge(executable: node, script: script)
        var received = false
        for try await event in bridge.events(for: AgentRequest(action: "status", backend: .claude, directory: root)) {
            if event.type == "delta" {
                received = true
                XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "Small responses must stream before EOF, without waiting to fill an 8192-byte buffer")
            }
        }
        XCTAssertTrue(received)
    }
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
    func testNodeLookupIsRememberedUntilARecheckFindsTheNewInstall() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let node = root.appendingPathComponent("node")
        let lookup = ExecutableLookup { FileManager.default.isExecutableFile(atPath: node.path) ? node : nil }
        XCTAssertNil(lookup.url)
        try "#!/bin/sh\n".write(to: node, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        XCTAssertNil(lookup.url, "Re-evaluating a view must not walk PATH again")
        lookup.refresh()
        XCTAssertEqual(lookup.url, node, "Rechecking the connection must find Node.js installed while the app runs")
    }
}

private final class TimerProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func fire() { lock.lock(); value = true; lock.unlock() }
    var fired: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
