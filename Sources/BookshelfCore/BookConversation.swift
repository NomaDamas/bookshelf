import Foundation

public struct BookChatMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var role: String
    public var text: String
    public var backend: String
    public var page: Int
    public var state: String
    public var harness: String?
    public var skill: String?
    public var usage: AgentContextUsage?
    public var model: String?
    public var attachments: [ChatAttachment]?
    public var scope: BookReadingScope?
    public var reading: BookReadingCoverage?
    /// Tool steps the agent took for this reply. Absent in conversations saved before steps existed.
    public var steps: [ChatStep]?
    /// When the reply stopped streaming (completed, failed or interrupted).
    public var finished: Double?
    /// Pre-reading questions parsed out of a `pretest` reply, with the reader's guesses and reveals.
    public var pretest: PretestSet?
    public var sourcePages: [Int] {
        Array(Set(reading?.sourcePages ?? (scope?.contains(page) == false ? [] : [page]))).sorted()
    }
    public var created: Double
    public init(role: String, text: String, backend: String, page: Int, state: String = "complete", harness: String? = nil, skill: String? = nil) {
        id = UUID().uuidString; self.role = role; self.text = text; self.backend = backend
        self.page = page; self.state = state; self.harness = harness; self.skill = skill; created = Date().timeIntervalSince1970
    }
}

/// Tokens reported by the official executor for its latest request, not lifetime spend.
public struct AgentContextUsage: Codable, Equatable, Sendable {
    public var model: String?
    public var inputTokens: Int
    public var outputTokens: Int
    public var contextWindow: Int?
    public var cachedInputTokens: Int?
    public var usedTokens: Int { max(0, inputTokens) + max(0, outputTokens) }
    public var fraction: Double? {
        guard let contextWindow, contextWindow > 0 else { return nil }
        return min(1, Double(usedTokens) / Double(contextWindow))
    }
    public init(model: String? = nil, inputTokens: Int, outputTokens: Int, contextWindow: Int? = nil, cachedInputTokens: Int? = nil) {
        self.model = model; self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.contextWindow = contextWindow; self.cachedInputTokens = cachedInputTokens
    }
}

/// One agent step within a reply, such as a page read or an image generation.
/// `title`/`detail` are stored as shown so later wording changes do not rewrite history.
public struct ChatStep: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var title: String
    public var detail: String?
    public var result: String?
    /// "running", "done", "failed" or "interrupted".
    public var state: String
    public var started: Double
    public var finished: Double?
    public init(kind: String, title: String, detail: String? = nil, state: String = "running", started: Double = Date().timeIntervalSince1970) {
        id = UUID().uuidString; self.kind = kind; self.title = title; self.detail = detail
        self.state = state; self.started = started
    }
}

public struct ChatAttachment: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var fileName: String
    public var kind: String
    public init(id: String, name: String, fileName: String, kind: String) {
        self.id = id; self.name = name; self.fileName = fileName; self.kind = kind
    }
}

public struct BookConversation: Codable, Sendable {
    public var messages: [BookChatMessage]
    public var revision: Int
    public init(messages: [BookChatMessage] = [], revision: Int = 0) {
        self.messages = messages; self.revision = revision
    }
}
