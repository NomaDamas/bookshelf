import Foundation

/// A pre-reading question whose answer stays hidden until the reader reaches `answerPage`.
public struct PretestQuestion: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var question: String
    public var answerPage: Int
    public var answer: String
    /// What the reader wrote before reading on. Absent until they write something.
    public var guess: String?
    /// When the reader's position first reached `answerPage`. A revealed answer stays revealed.
    public var revealed: Double?
    public init(question: String, answerPage: Int, answer: String) {
        id = UUID().uuidString; self.question = question; self.answerPage = answerPage; self.answer = answer
    }
}

/// The questions Pi returned in one reply, after the app checked every answer page.
public struct PretestSet: Codable, Equatable, Sendable {
    public var questions: [PretestQuestion]
    /// Questions removed because their answer page was not a page ahead that Pi actually read.
    public var dropped: Int
    public init(questions: [PretestQuestion], dropped: Int = 0) { self.questions = questions; self.dropped = dropped }
}

/// Pi returns pre-reading questions in a fenced `pretest` block holding JSON:
/// `{"questions":[{"question":"…","answerPage":12,"answer":"…"}]}`. The block carries the
/// answers, so it never reaches the screen, a copy or the stored reply text.
public enum PretestBlock {
    public static let language = "pretest"
    public static let maximumQuestions = 3

    /// Reply text without the block, closed or not.
    public static func visibleText(_ text: String) -> String { split(text).visible }

    /// Streaming reply text without the block, including a block that is still arriving. A last
    /// line that may still become the opening fence is held back, so no fragment flashes on screen.
    /// Only for streaming: in a finished reply a bare closing fence on the last line is not an opening.
    public static func streamingText(_ text: String) -> String {
        let visible = split(text).visible
        guard let last = visible.components(separatedBy: "\n").last?.trimmingCharacters(in: .whitespaces),
              let marker = last.first, marker == "`" || marker == "~" else { return visible }
        let rest = last.drop(while: { $0 == marker }).lowercased()
        guard language.hasPrefix(rest) else { return visible }
        return String(visible.dropLast(last.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits a finished reply. A question survives only when its answer page comes after
    /// the page the reader asked from, lies inside the request's range, and was among the
    /// pages Pi's book tools returned.
    public static func extract(_ text: String, askedOn page: Int, scope: BookReadingScope?, sourcePages: [Int]) -> (text: String, set: PretestSet?) {
        let parts = split(text)
        guard let json = parts.block, let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return (parts.visible, nil) }
        let read = Set(sourcePages)
        var kept: [PretestQuestion] = [], dropped = 0
        for item in payload.questions {
            let question = item.question.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = item.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard kept.count < maximumQuestions, !question.isEmpty, question.count <= 400, !answer.isEmpty, answer.count <= 400,
                  item.answerPage > page, scope?.contains(item.answerPage) ?? true, read.contains(item.answerPage) else { dropped += 1; continue }
            kept.append(PretestQuestion(question: question, answerPage: item.answerPage, answer: answer))
        }
        return (parts.visible, PretestSet(questions: kept, dropped: dropped))
    }

    private struct Payload: Decodable {
        struct Item: Decodable { var question: String; var answerPage: Int; var answer: String }
        var questions: [Item]
    }

    private static func split(_ text: String) -> (visible: String, block: String?) {
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: opens) else { return (text, nil) }
        let marker = lines[start].trimmingCharacters(in: .whitespaces).first!
        let fence = String(lines[start].trimmingCharacters(in: .whitespaces).prefix(while: { $0 == marker }))
        let end = lines[(start + 1)...].firstIndex { line in
            let closing = line.trimmingCharacters(in: .whitespaces)
            return closing.count >= fence.count && closing.allSatisfy { $0 == marker }
        }
        let rest = end.map { Array(lines[($0 + 1)...]) } ?? []
        let visible = (lines[..<start] + rest).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (visible, end.map { lines[(start + 1)..<$0].joined(separator: "\n") })
    }
    private static func opens(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return false }
        let fence = trimmed.prefix(while: { $0 == marker })
        guard fence.count >= 3 else { return false }
        return trimmed.dropFirst(fence.count).trimmingCharacters(in: .whitespaces).lowercased() == language
    }
}

public extension BookChatMessage {
    /// Reply text as the reader may see it. A finished pretest reply is stored without its block;
    /// this also hides one in a reply saved mid-stream, for example before a crash.
    var visibleText: String { skill == PretestBlock.language ? PretestBlock.visibleText(text) : text }
    /// Reply text plus its pre-reading questions, as the next request sees them. Answers the
    /// reader has not reached are left out, so later turns stay within the reading position.
    var conversationText: String {
        let text = visibleText
        guard let questions = pretest?.questions, !questions.isEmpty else { return text }
        let lines = questions.enumerated().map { index, item in
            var line = "\(index + 1). \(item.question)"
            if let guess = item.guess, !guess.isEmpty { line += "\n   Reader's guess: \(guess)" }
            if item.revealed != nil { line += "\n   Answer, reached on [p. \(item.answerPage)]: \(item.answer)" }
            return line
        }
        return ([text, "Pre-reading questions:\n" + lines.joined(separator: "\n")].filter { !$0.isEmpty }).joined(separator: "\n\n")
    }
    /// The same questions for a person reading a copied conversation.
    var transcriptText: String {
        let text = visibleText
        guard let questions = pretest?.questions, !questions.isEmpty else { return text }
        let lines = questions.enumerated().map { index, item in
            var line = "\(index + 1). \(item.question)"
            if let guess = item.guess, !guess.isEmpty { line += "\n   내 추측: \(guess)" }
            line += item.revealed != nil ? "\n   답(\(item.answerPage)쪽): \(item.answer)" : "\n   답: 아직 읽지 않은 쪽에 있습니다."
            return line
        }
        return ([text, "예습 질문\n" + lines.joined(separator: "\n")].filter { !$0.isEmpty }).joined(separator: "\n\n")
    }
}
