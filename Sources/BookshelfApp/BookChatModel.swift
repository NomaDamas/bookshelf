import SwiftUI
import BookshelfCore

@MainActor final class BookChatModel: ObservableObject {
    let store: LibraryStore
    private let bridgeFactory: () -> AgentBridge
    @Published private(set) var messages: [BookChatMessage] = []
    @Published var draft = ""
    @Published private(set) var backend: ChatBackend = .claude
    @Published private(set) var usePi = true
    @Published var skill = "auto"
    @Published private(set) var activityMessage = ""
    @Published var scopeMode = "book"
    @Published var pageRange: ClosedRange<Int>?
    func readingScope(page: Int, pageCount: Int) -> BookReadingScope {
        if scopeMode == "page" { return BookReadingScope(mode: "page", startPage: page, endPage: page) }
        if scopeMode == "range", let pageRange, pageRange.upperBound <= pageCount {
            return BookReadingScope(mode: "range", startPage: pageRange.lowerBound, endPage: pageRange.upperBound)
        }
        return BookReadingScope(mode: "book", startPage: 1, endPage: max(1, pageCount))
    }
    @Published private(set) var busy = false
    @Published private(set) var operation = ""
    @Published private(set) var accounts: [ChatBackend: AgentAccountStatus] = [:]
    @Published var errorMessage: String?
    @Published var loginURL: URL?
    @Published private(set) var importingAssets = false
    @Published private(set) var canUndoEdit = false
    @Published private(set) var models: [ChatBackend: [AgentModelChoice]] = [:]
    @Published private(set) var selectedModels: [ChatBackend: String] = [:]
    @Published private(set) var hasUnsavedChanges = false
    private var bookID: String?
    private var revision = 0
    private var runID = UUID()
    private var task: Task<Void, Never>?
    private var bridge: AgentBridge?
    private var drafts: [String: String] = [:]
    private var assistantID: String?
    private var receivedAnswer = false
    private var pendingDelta = ""
    private var deltaTask: Task<Void, Never>?

    init(store: LibraryStore, bridgeFactory: @escaping () -> AgentBridge = { AgentBridge() }) {
        self.store = store; self.bridgeFactory = bridgeFactory
        if let saved = try? store.setting("agent.backend"), let value = ChatBackend(rawValue: saved) { backend = value }
        usePi = (try? store.setting("agent.usePi")) != "false"
        for backend in ChatBackend.allCases { selectedModels[backend] = (try? store.setting("agent.model." + backend.rawValue)) ?? "" }
    }
    var account: AgentAccountStatus? { accounts[backend] }
    var selectedModel: String { selectedModels[backend] ?? "" }
    var modelTitle: String { models[backend]?.first(where: { $0.id == selectedModel })?.label ?? (selectedModel.isEmpty ? "자동" : selectedModel) }
    var contextUsage: AgentContextUsage? { messages.last(where: { $0.role == "assistant" && $0.backend == backend.rawValue && $0.usage != nil })?.usage }
    @discardableResult func selectBook(_ id: String) -> Bool {
        guard id != bookID else { return true }
        stop()
        guard persist() else { return false }
        if let bookID { drafts[bookID] = draft }
        do {
            let saved = try store.conversation(bookID: id)
            bookID = id; messages = saved.messages; revision = saved.revision; draft = drafts[id] ?? ""
            scopeMode = "book"; pageRange = nil
            canUndoEdit = (try? store.canUndoConversationEdit(bookID: id)) ?? false
            errorMessage = nil; return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func chooseBackend(_ value: ChatBackend, checkStatus: Bool = true) {
        guard backend != value else { return }
        stop(); backend = value; loginURL = nil
        do { try store.setSetting("agent.backend", value: value.rawValue) } catch { errorMessage = error.localizedDescription }
        if checkStatus { checkConnection() }
    }
    func chooseModel(_ value: String) {
        guard operation != "chat", value != selectedModel else { return }
        do { try store.setSetting("agent.model." + backend.rawValue, value: value); selectedModels[backend] = value }
        catch { errorMessage = error.localizedDescription }
    }
    func login(using backend: ChatBackend) { guard !busy else { return }; chooseBackend(backend, checkStatus: false); login() }
    func refreshConnections() async {
        guard !busy else { return }
        for backend in ChatBackend.allCases {
            guard !Task.isCancelled else { return }
            let connection = bridgeFactory()
            do {
                for try await event in connection.events(for: AgentRequest(action: "status", backend: backend, directory: store.directory)) {
                    guard !Task.isCancelled else { connection.cancel(); return }
                    if event.type == "status", let status = event.status { accounts[backend] = status }
                    if event.type == "models", let options = event.models { models[backend] = options }
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func setPi(_ enabled: Bool) {
        guard enabled != usePi else { return }
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
        let history = messages.filter {
            $0.state == "complete" && !$0.text.isEmpty && $0.backend != "local" &&
            (context.scope == nil || context.scope?.mode == "book" || $0.scope == context.scope)
        }.suffix(12).map { AgentRequest.Message(role: $0.role, text: String($0.text.prefix(6000))) }
        var user = BookChatMessage(role: "user", text: question, backend: backend.rawValue, page: context.page, harness: usePi ? "pi" : "direct", skill: skill)
        user.scope = context.scope; messages.append(user)
        hasUnsavedChanges = true
        guard persist() else { return }
        draft = ""
        var answer = BookChatMessage(role: "assistant", text: "", backend: backend.rawValue, page: context.page, state: "interrupted", harness: usePi ? "pi" : "direct", skill: skill)
        answer.model = selectedModel.isEmpty ? nil : selectedModel
        answer.scope = context.scope
        if let scope = context.scope {
            let provided = context.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [context.page]
            answer.reading = BookReadingCoverage(bookID: context.id, scope: scope, readPages: context.textTruncated ? [] : provided, sourcePages: provided)
        }
        messages.append(answer); assistantID = answer.id; receivedAnswer = false; hasUnsavedChanges = true
        start(AgentRequest(action: "chat", backend: backend, directory: store.directory, usePi: usePi, skill: skill,
                           question: question, messages: history, book: context, model: selectedModel))
    }
    func stop() {
        flushDelta()
        runID = UUID(); task?.cancel(); bridge?.cancel(); task = nil; bridge = nil
        if let index = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[index].state = receivedAnswer ? "complete" : "interrupted"
            hasUnsavedChanges = true
        }
        assistantID = nil; busy = false; operation = ""; activityMessage = ""; _ = persist()
    }
    private func flushDelta() {
        deltaTask?.cancel(); deltaTask = nil
        if !pendingDelta.isEmpty, let index = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[index].text += pendingDelta; hasUnsavedChanges = true
        }
        pendingDelta = ""
    }
    func clearConversation() { stop(); _ = replaceConversation(with: []) }
    func deleteFrom(_ id: String) {
        stop(); guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        _ = replaceConversation(with: Array(messages[..<index]))
    }
    func reviseQuestion(_ id: String, text: String, context: AgentRequest.Context) {
        guard context.id == bookID, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard text.utf16.count <= 10000 else { errorMessage = "질문은 10000자 이내로 입력해 주세요."; return }
        stop(); guard let index = messages.firstIndex(where: { $0.id == id && $0.role == "user" }) else { return }
        guard replaceConversation(with: Array(messages[..<index])) else { return }
        let unsentDraft = draft
        defer { draft = unsentDraft }
        draft = text; send(context: context)
    }
    var lastQuestion: BookChatMessage? { messages.last(where: { $0.role == "user" && ($0.attachments?.isEmpty ?? true) }) }
    func undoEdit() {
        stop(); guard persist(), let bookID else { return }
        do {
            let saved = try store.undoConversationEdit(bookID: bookID, expectedRevision: revision)
            messages = saved.messages; revision = saved.revision; errorMessage = nil
            canUndoEdit = try store.canUndoConversationEdit(bookID: bookID)
        } catch { errorMessage = error.localizedDescription }
    }
    private func replaceConversation(with replacement: [BookChatMessage]) -> Bool {
        guard persist(), let bookID else { return false }
        do {
            let saved = try store.saveConversation(bookID: bookID, messages: replacement, expectedRevision: revision, preservePrevious: true)
            messages = saved.messages; revision = saved.revision; hasUnsavedChanges = false; canUndoEdit = true; errorMessage = nil
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func addAttachments(_ urls: [URL], bookID target: String, page: Int) {
        guard !importingAssets, !busy, selectBook(target), persist() else { return }
        importingAssets = true
        let directory = store.directory
        Task {
            defer { importingAssets = false }
            do {
                let assets = try await Task.detached(priority: .userInitiated) {
                    try urls.map { try ChatAssetStore.importFile($0, directory: directory) }
                }.value
                var message = BookChatMessage(role: "user", text: "", backend: "local", page: page)
                message.attachments = assets
                if bookID == target {
                    guard persist() else { return }
                    messages.append(message); hasUnsavedChanges = true; _ = persist()
                } else {
                    let saved = try store.conversation(bookID: target)
                    _ = try store.saveConversation(bookID: target, messages: saved.messages + [message], expectedRevision: saved.revision)
                }
            } catch { errorMessage = "자료를 보관하지 못했습니다. " + error.localizedDescription }
        }
    }
    @discardableResult func persist() -> Bool {
        guard hasUnsavedChanges, let bookID else { return true }
        do {
            let result = try store.saveConversation(bookID: bookID, messages: messages, expectedRevision: revision)
            revision = result.revision; hasUnsavedChanges = false; return true
        } catch { errorMessage = "대화를 저장하지 못했습니다. " + error.localizedDescription; return false }
    }
    private func start(_ request: AgentRequest) {
        let id = UUID(); runID = id; errorMessage = nil; busy = true; operation = request.action; activityMessage = ""
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
            flushDelta()
            if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[index].state = receivedAnswer ? "complete" : "failed"; hasUnsavedChanges = true
            }
            assistantID = nil; busy = false; operation = ""; activityMessage = ""; bridge = nil; _ = persist()
        }
    }
    private func receive(_ event: AgentEvent, backend: ChatBackend) {
        switch event.type {
        case "status": if let status = event.status { accounts[backend] = status }
        case "models": if let options = event.models { models[backend] = options }
        case "activity": activityMessage = event.message ?? ""
        case "reading":
            guard let reading = event.reading, reading.bookID == bookID,
                  let index = messages.firstIndex(where: { $0.id == assistantID }), reading.scope == messages[index].scope,
                  (reading.readPages + reading.sourcePages + reading.emptyPages).allSatisfy({ reading.scope.contains($0) }) else { return }
            let old = messages[index].reading
            messages[index].reading = BookReadingCoverage(bookID: reading.bookID, scope: reading.scope,
                readPages: Array(Set((old?.readPages ?? []) + reading.readPages)).sorted(),
                sourcePages: Array(Set((old?.sourcePages ?? []) + reading.sourcePages)).sorted(),
                emptyPages: Array(Set((old?.emptyPages ?? []) + reading.emptyPages)).sorted())
            hasUnsavedChanges = true
        case "attachment":
            guard backend == .codex, let attachment = event.attachment, attachment.kind == "image",
                  let index = messages.firstIndex(where: { $0.id == assistantID }),
                  ChatAssetStore.generatedImageURL(for: attachment, directory: store.directory) != nil else {
                errorMessage = "생성된 이미지를 보관하지 못했습니다."; return
            }
            if !(messages[index].attachments ?? []).contains(where: { $0.id == attachment.id }) {
                messages[index].attachments = (messages[index].attachments ?? []) + [attachment]
                hasUnsavedChanges = true; _ = persist()
            }
        case "usage":
            if let usage = event.usage, let index = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[index].usage = usage; hasUnsavedChanges = true
            }
        case "delta", "answer":
            guard let text = event.text, let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
            if event.type == "answer" {
                deltaTask?.cancel(); deltaTask = nil; pendingDelta = ""
                messages[index].text = text; messages[index].state = "complete"; receivedAnswer = true
            } else {
                pendingDelta += text
                if deltaTask == nil {
                    deltaTask = Task { [weak self] in
                        do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                        self?.flushDelta()
                    }
                }
            }
            hasUnsavedChanges = true
        case "error", "warning": errorMessage = event.message ?? "답변을 완료하지 못했습니다."
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
