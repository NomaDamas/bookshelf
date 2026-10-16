import Foundation

public enum ReadingStatus: String, Codable, CaseIterable, Sendable {
    case unread, reading, finished

    public var title: String {
        switch self {
        case .unread: return "읽기 전"
        case .reading: return "읽는 중"
        case .finished: return "읽은 책"
        }
    }
    public var symbol: String {
        switch self {
        case .unread: return "book.closed"
        case .reading: return "book"
        case .finished: return "checkmark.circle"
        }
    }
}

public struct ReadingSummary: Codable, Equatable, Sendable {
    public var status: ReadingStatus = .unread
    public var completedCount = 0
    public var startedAt: Double?
    public var lastCompletedAt: Double?
    public var updatedAt: Double = 0
    public init() {}
    public var label: String {
        switch status {
        case .unread: return status.title
        case .reading: return "\(completedCount + 1)회독 중"
        case .finished: return "\(completedCount)회독 완료"
        }
    }
}

public struct ReadingCompletion: Codable, Identifiable, Sendable {
    public let id: String
    public let bookID: String
    public let startedAt: Double?
    public let completedAt: Double
}

public struct NoteCount: Codable, Equatable, Sendable {
    public var notebook = 0
    public var excerpts = 0
    public init() {}
    public var total: Int { notebook + excerpts }
    public var badge: String { total > 99 ? "99+" : String(total) }
    public var description: String { "책 노트 \(notebook)개, 발췌 메모 \(excerpts)개" }
}
