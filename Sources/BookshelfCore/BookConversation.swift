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
    public var created: Double
    public init(role: String, text: String, backend: String, page: Int, state: String = "complete", harness: String? = nil, skill: String? = nil) {
        id = UUID().uuidString; self.role = role; self.text = text; self.backend = backend
        self.page = page; self.state = state; self.harness = harness; self.skill = skill; created = Date().timeIntervalSince1970
    }
}

public struct BookConversation: Codable, Sendable {
    public var messages: [BookChatMessage]
    public var revision: Int
    public init(messages: [BookChatMessage] = [], revision: Int = 0) {
        self.messages = messages; self.revision = revision
    }
}
