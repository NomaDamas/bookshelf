import Foundation
import Darwin

public enum ChatBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex
    public var id: String { rawValue }
    public var title: String { self == .claude ? "Claude" : "Codex" }
}
public struct AgentAccountStatus: Decodable, Sendable {
    public var connected: Bool
    public var billing: String
    public var label: String
}
public struct AgentEvent: Decodable, Sendable {
    public var type: String
    public var text: String?
    public var message: String?
    public var status: AgentAccountStatus?
    public var url: String?
    public var openAutomatically: Bool?
}
public struct AgentRequest: Encodable, Sendable {
    public struct Message: Encodable, Sendable {
        public var role: String
        public var text: String
        public init(role: String, text: String) { self.role = role; self.text = text }
    }
    public struct Context: Encodable, Sendable {
        public var id: String
        public var title: String
        public var page: Int
        public var text: String
        public var notes: String
        public var selection: String
        public init(id: String, title: String, page: Int, text: String, notes: String, selection: String) {
            self.id = id; self.title = title; self.page = page; self.text = String(text.prefix(10000))
            self.notes = String(notes.prefix(4000)); self.selection = String(selection.prefix(3000))
        }
    }
    public var action: String
    public var clientVersion: String
    public var backend: ChatBackend
    public var usePi: Bool
    public var skill: String
    public var workspace: String
    public var codexHome: String
    public var claudePath: String?
    public var codexPath: String?
    public var question: String?
    public var messages: [Message]
    public var book: Context?
    public init(action: String, backend: ChatBackend, directory: URL, usePi: Bool = true, skill: String = "explain",
                question: String? = nil, messages: [Message] = [], book: Context? = nil) {
        self.action = action; self.clientVersion = AppMetadata.current.version; self.backend = backend; self.usePi = usePi; self.skill = skill
        let agentBase = ProcessInfo.processInfo.environment["BOOKSHELF_AGENT_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? directory
        workspace = agentBase.appendingPathComponent("Agent/Workspace", isDirectory: true).path
        codexHome = agentBase.appendingPathComponent("Agent/Codex", isDirectory: true).path
        claudePath = AgentRuntime.findExecutable("claude")?.path; codexPath = AgentRuntime.findExecutable("codex")?.path
        self.question = question; self.messages = messages; self.book = book
    }
}
public enum AgentRuntime {
    public static func findExecutable(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [home.appendingPathComponent(".local/bin").path, home.appendingPathComponent(".bun/bin").path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        return directories.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    public static var bridgeURL: URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Agent/bridge.mjs")
        return bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }
    public static var ready: Bool { findExecutable("node") != nil && bridgeURL != nil }
}

/// One request per process. The app owns history; provider credentials never cross this protocol.
public final class AgentBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private let executable: URL?
    private let script: URL?
    public init(executable: URL? = AgentRuntime.findExecutable("node"), script: URL? = AgentRuntime.bridgeURL) {
        self.executable = executable; self.script = script
    }
    public func events(for request: AgentRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in self?.cancel() }
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    guard let executable, let script else { throw ShelfError.message("AI 실행 환경이 없습니다. Node.js 설치와 앱 빌드를 확인해 주세요.") }
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                    let payload = try encoder.encode(request)
                    guard payload.count < 1_000_000 else { throw ShelfError.message("질문에 포함된 내용이 너무 큽니다.") }
                    let task = Process(), input = Pipe(), output = Pipe()
                    task.executableURL = executable; task.arguments = [script.path]
                    task.standardInput = input; task.standardOutput = output; task.standardError = FileHandle.nullDevice
                    let keys = Set(["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "SHELL", "CLAUDE_CONFIG_DIR"])
                    task.environment = ProcessInfo.processInfo.environment.filter { keys.contains($0.key) }
                    lock.lock(); process = task; let shouldCancel = cancelled; lock.unlock()
                    if shouldCancel { throw CancellationError() }
                    try task.run()
                    lock.lock(); let stopped = cancelled; lock.unlock()
                    if stopped { task.terminate() }
                    try input.fileHandleForWriting.write(contentsOf: payload); try input.fileHandleForWriting.close()
                    var buffer = Data(), reportedError = false
                    while let chunk = try output.fileHandleForReading.read(upToCount: 8192), !chunk.isEmpty {
                        buffer.append(chunk)
                        guard buffer.count < 2_000_000 else { cancel(); throw ShelfError.message("AI 실행기 응답이 너무 큽니다.") }
                        while let end = buffer.firstIndex(of: 10) {
                            let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                            if line.isEmpty { continue }
                            let event = try JSONDecoder().decode(AgentEvent.self, from: line)
                            if event.type == "error" { reportedError = true }
                            continuation.yield(event)
                        }
                    }
                    task.waitUntilExit()
                    if task.terminationStatus != 0 && !reportedError { throw ShelfError.message("AI 실행기가 종료됐습니다. 연결 상태를 다시 확인해 주세요.") }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }
    public func cancel() {
        lock.lock(); cancelled = true; let task = process; lock.unlock()
        guard let task, task.isRunning else { return }
        task.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
            if task.isRunning { kill(task.processIdentifier, SIGKILL) }
        }
    }
}
