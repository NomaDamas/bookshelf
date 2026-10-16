import SwiftUI
import BookshelfCore

@MainActor final class BookChatModel: ObservableObject {
    let store: LibraryStore
    private let bridgeFactory: () -> AgentBridge
    @Published private(set) var messages: [BookChatMessage] = []
    @Published var draft = ""
    @Published private(set) var backend: ChatBackend = .claude
    @Published private(set) var usePi = true
    @Published var skill = "explain"
    @Published private(set) var busy = false
    @Published private(set) var operation = ""
    @Published private(set) var accounts: [ChatBackend: AgentAccountStatus] = [:]
    @Published var errorMessage: String?
    @Published var loginURL: URL?
    @Published private(set) var hasUnsavedChanges = false
    private var bookID: String?
    private var revision = 0
    private var runID = UUID()
    private var task: Task<Void, Never>?
    private var bridge: AgentBridge?
    private var drafts: [String: String] = [:]
    private var assistantID: String?
    private var receivedAnswer = false

    init(store: LibraryStore, bridgeFactory: @escaping () -> AgentBridge = { AgentBridge() }) {
        self.store = store; self.bridgeFactory = bridgeFactory
        if let saved = try? store.setting("agent.backend"), let value = ChatBackend(rawValue: saved) { backend = value }
        usePi = (try? store.setting("agent.usePi")) != "false"
    }
    var account: AgentAccountStatus? { accounts[backend] }
    @discardableResult func selectBook(_ id: String) -> Bool {
        guard id != bookID else { return true }
        stop()
        guard persist() else { return false }
        if let bookID { drafts[bookID] = draft }
        do {
            let saved = try store.conversation(bookID: id)
            bookID = id; messages = saved.messages; revision = saved.revision; draft = drafts[id] ?? ""
            errorMessage = nil; return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func chooseBackend(_ value: ChatBackend) {
        guard backend != value else { return }
        stop(); backend = value; loginURL = nil
        do { try store.setSetting("agent.backend", value: value.rawValue) } catch { errorMessage = error.localizedDescription }
        checkConnection()
    }
    func setPi(_ enabled: Bool) {
        stop(); usePi = enabled
        do { try store.setSetting("agent.usePi", value: enabled ? "true" : "false") } catch { errorMessage = error.localizedDescription }
    }
    func checkConnection() { guard !busy else { return }; start(AgentRequest(action: "status", backend: backend, directory: store.directory)) }
    func login() { guard !busy else { return }; start(AgentRequest(action: "login", backend: backend, directory: store.directory)) }
    func send(context: AgentRequest.Context) {
        guard !busy, selectBook(context.id), persist() else { return }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        guard question.utf16.count <= 10000 else { errorMessage = "질문은 10000자 이내로 입력해 주세요."; return }
        let history = messages.filter { $0.state == "complete" }.suffix(12).map { AgentRequest.Message(role: $0.role, text: String($0.text.prefix(6000))) }
        messages.append(BookChatMessage(role: "user", text: question, backend: backend.rawValue, page: context.page))
        hasUnsavedChanges = true
        guard persist() else { return }
        draft = ""
        let answer = BookChatMessage(role: "assistant", text: "", backend: backend.rawValue, page: context.page, state: "interrupted")
        messages.append(answer); assistantID = answer.id; receivedAnswer = false; hasUnsavedChanges = true
        start(AgentRequest(action: "chat", backend: backend, directory: store.directory, usePi: usePi, skill: skill,
                           question: question, messages: history, book: context))
    }
    func stop() {
        runID = UUID(); task?.cancel(); bridge?.cancel(); task = nil; bridge = nil
        if let index = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[index].state = receivedAnswer ? "complete" : "interrupted"
            hasUnsavedChanges = true
        }
        assistantID = nil; busy = false; operation = ""; _ = persist()
    }
    @discardableResult func persist() -> Bool {
        guard hasUnsavedChanges, let bookID else { return true }
        do {
            let result = try store.saveConversation(bookID: bookID, messages: messages, expectedRevision: revision)
            revision = result.revision; hasUnsavedChanges = false; return true
        } catch { errorMessage = "대화를 저장하지 못했습니다. " + error.localizedDescription; return false }
    }
    private func start(_ request: AgentRequest) {
        let id = UUID(); runID = id; errorMessage = nil; busy = true; operation = request.action
        let connection = bridgeFactory(); bridge = connection
        task = Task {
            do {
                for try await event in connection.events(for: request) {
                    guard id == runID, !Task.isCancelled else { return }
                    receive(event, backend: request.backend)
                }
            } catch {
                if id == runID && !Task.isCancelled { errorMessage = error.localizedDescription }
            }
            guard id == runID else { return }
            if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[index].state = receivedAnswer ? "complete" : "failed"; hasUnsavedChanges = true
            }
            assistantID = nil; busy = false; operation = ""; bridge = nil; _ = persist()
        }
    }
    private func receive(_ event: AgentEvent, backend: ChatBackend) {
        switch event.type {
        case "status": if let status = event.status { accounts[backend] = status }
        case "delta", "answer":
            guard let text = event.text, let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
            if event.type == "answer" { messages[index].text = text; messages[index].state = "complete"; receivedAnswer = true }
            else { messages[index].text += text }
            hasUnsavedChanges = true
        case "error": errorMessage = event.message ?? "답변을 완료하지 못했습니다."
        case "login_url":
            guard let value = event.url, let url = URL(string: value), url.scheme == "https",
                  let host = url.host, ["auth.openai.com", "auth0.openai.com", "chatgpt.com", "claude.ai", "platform.claude.com", "console.anthropic.com"].contains(host) else {
                errorMessage = "공식 로그인 주소를 확인하지 못했습니다."; return
            }
            loginURL = url
            if event.openAutomatically == true { NSWorkspace.shared.open(url) }
        default: break
        }
    }
}
