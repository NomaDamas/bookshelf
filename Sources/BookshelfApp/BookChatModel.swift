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
    /// A chat reply or sign-in owns the bridge. Account status checks run separately and never lock the panel.
    @Published private(set) var busy = false
    @Published private(set) var operation = ""
    @Published private var statusChecks = 0
    var checkingStatus: Bool { statusChecks > 0 }
    /// Executors whose status was read at least once; before that the panel treats the account as being checked.
    @Published private(set) var checkedBackends: Set<ChatBackend> = []
    @Published private(set) var loginBackend: ChatBackend?
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
    private var statusTask: Task<Void, Never>?
    private var bridge: AgentBridge?
    private var drafts: [String: String] = [:]
    private var assistantID: String?
    private var receivedAnswer = false
    private var pendingDelta = ""
    private var deltaTask: Task<Void, Never>?
    private var guessTask: Task<Void, Never>?
    /// The open book's page as the reader view last reported it. Pre-reading answers open from it.
    private(set) var readerPage = 0
    /// Pre-reading offers in this app run, per book. One dismissal or two finished question sets ends them.
    @Published private var pretestDeclined: Set<String> = []
    @Published private var pretestSets: [String: Int] = [:]
    static let pretestSetLimit = 2

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
            scopeMode = "book"; pageRange = nil; readerPage = 0; endTutoring()
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
    /// Signs in to one executor without changing the engine the current conversation uses.
    func login(using target: ChatBackend) {
        guard !busy else { return }
        loginURL = nil; loginBackend = target
        start(AgentRequest(action: "login", backend: target, directory: store.directory))
    }
    func refreshConnections() async {
        guard !busy else { return }
        for backend in ChatBackend.allCases {
            guard !Task.isCancelled else { return }
            await readStatus(of: backend)
        }
    }
    private func readStatus(of backend: ChatBackend) async {
        statusChecks += 1; defer { statusChecks -= 1; checkedBackends.insert(backend) }
        let connection = bridgeFactory()
        do {
            for try await event in connection.events(for: AgentRequest(action: "status", backend: backend, directory: store.directory)) {
                guard !Task.isCancelled else { connection.cancel(); return }
                if event.type == "status", let status = event.status { accounts[backend] = status }
                if event.type == "models", let options = event.models { models[backend] = options }
            }
        } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
    func setPi(_ enabled: Bool) {
        guard enabled != usePi else { return }
        stop(); usePi = enabled
        do { try store.setSetting("agent.usePi", value: enabled ? "true" : "false") } catch { errorMessage = error.localizedDescription }
    }
    func checkConnection() {
        guard !busy else { return }
        statusTask?.cancel()
        let target = backend
        statusTask = Task { [weak self] in await self?.readStatus(of: target) }
    }
    func login() { login(using: backend) }
    func send(context: AgentRequest.Context) {
        guard !busy, selectBook(context.id), persist() else { return }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        guard question.utf16.count <= 10000 else { errorMessage = "질문은 10000자 이내로 입력해 주세요."; return }
        let history = messages.filter {
            $0.state == "complete" && !$0.conversationText.isEmpty && $0.backend != "local" &&
            (context.scope == nil || context.scope?.mode == "book" || $0.scope == context.scope)
        }.suffix(12).map { AgentRequest.Message(role: $0.role, text: String($0.conversationText.prefix(6000))) }
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
            finishTurn(at: index, openSteps: "interrupted")
        }
        assistantID = nil; busy = false; operation = ""; activityMessage = ""; _ = persist()
    }
    /// Records when a reply stopped and settles steps that never reported an end.
    private func finishTurn(at index: Int, openSteps state: String) {
        let now = Date().timeIntervalSince1970
        messages[index].finished = now
        if var steps = messages[index].steps {
            for i in steps.indices where steps[i].state == "running" { steps[i].state = state; steps[i].finished = now }
            messages[index].steps = steps
        }
        if messages[index].skill == PiExplanation.pretest.rawValue { settlePretest(at: index) }
        hasUnsavedChanges = true
    }
    /// Moves a `pretest` block out of the reply into checked questions. It runs for every ending,
    /// so a stopped or failed reply never keeps the answers in its visible text.
    private func settlePretest(at index: Int) {
        let message = messages[index]
        let result = PretestBlock.extract(message.text, askedOn: message.page, scope: message.scope, sourcePages: message.reading?.sourcePages ?? [])
        messages[index].text = result.text
        guard message.state == "complete", let set = result.set else { return }
        messages[index].pretest = set
        if !set.questions.isEmpty, let bookID { pretestSets[bookID, default: 0] += 1 }
        reveal(through: readerPage)
    }
    /// Whether to offer pre-reading questions for a chapter that starts on `page`. The offer stops
    /// after one dismissal or two finished sets for this book, and once the chapter already has a set.
    func offersPretest(at page: Int) -> Bool {
        guard let bookID, !busy, !pretestDeclined.contains(bookID), (pretestSets[bookID] ?? 0) < Self.pretestSetLimit else { return false }
        return !messages.contains { $0.pretest != nil && $0.page == page }
    }
    func declinePretest() { if let bookID { pretestDeclined.insert(bookID) } }
    /// The reader view reports each page change. Reaching a page opens the answers that page holds;
    /// moving back never hides them again. No request runs: the answers arrived with the questions.
    func reachPage(_ page: Int, bookID id: String) {
        guard id == bookID, page != readerPage else { return }
        readerPage = page
        if reveal(through: page) { _ = persist() }
    }
    @discardableResult private func reveal(through page: Int) -> Bool {
        let now = Date().timeIntervalSince1970
        var changed = false
        for i in messages.indices {
            guard var set = messages[i].pretest, set.questions.contains(where: { $0.revealed == nil && $0.answerPage <= page }) else { continue }
            for q in set.questions.indices where set.questions[q].revealed == nil && set.questions[q].answerPage <= page { set.questions[q].revealed = now }
            messages[i].pretest = set; changed = true
        }
        if changed { hasUnsavedChanges = true }
        return changed
    }
    /// Keeps the reader's guess with the conversation. Typing saves after a short pause and adds no undo step.
    func setGuess(_ guess: String, question id: String) {
        guard let i = messages.firstIndex(where: { $0.pretest?.questions.contains { $0.id == id } == true }),
              var set = messages[i].pretest, let q = set.questions.firstIndex(where: { $0.id == id }), set.questions[q].revealed == nil else { return }
        let value: String? = guess.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : String(guess.prefix(1000))
        guard set.questions[q].guess != value else { return }
        set.questions[q].guess = value; messages[i].pretest = set; hasUnsavedChanges = true
        guessTask?.cancel()
        guessTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            self?.persist()
        }
    }
    private func updateSteps(_ change: (inout [ChatStep]) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        var steps = messages[index].steps ?? []
        change(&steps)
        messages[index].steps = steps; hasUnsavedChanges = true
    }
    /// The bridge opens a step with a non-empty activity and closes the oldest open one with an empty activity.
    private func recordActivity(_ message: String) {
        if message.isEmpty {
            updateSteps { steps in
                guard let i = steps.firstIndex(where: { $0.state == "running" }) else { return }
                if steps[i].kind == "image" && steps[i].result == nil { steps[i].state = "failed"; steps[i].result = "그림을 만들지 못했습니다" }
                else { steps[i].state = "done" }
                steps[i].finished = Date().timeIntervalSince1970
            }
        } else {
            updateSteps { $0.append(PiStepWording.step(for: message)) }
        }
    }
    private func flushDelta() {
        deltaTask?.cancel(); deltaTask = nil
        if !pendingDelta.isEmpty, let index = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[index].text += pendingDelta; hasUnsavedChanges = true
        }
        pendingDelta = ""
    }
    func clearConversation() { stop(); _ = replaceConversation(with: []); endTutoring() }
    /// A trace or explanation check lives in one conversation's history, so it does not carry
    /// over to another book or an emptied conversation. Plain explanation formats do.
    private func endTutoring() { if PiExplanation(skill: skill).isTutoring { skill = "auto" } }
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
    /// Plain-text copy of the whole conversation, in the order shown in the panel.
    func transcript() -> String {
        messages.compactMap { message -> String? in
            if message.backend == "local" {
                let names = (message.attachments ?? []).map(\.name)
                return names.isEmpty ? nil : "자료: " + names.joined(separator: ", ")
            }
            guard !message.transcriptText.isEmpty else { return nil }
            return (message.role == "user" ? "질문 (\(message.page)쪽)" : speaker(of: message)) + "\n" + message.transcriptText
        }.joined(separator: "\n\n")
    }
    /// Executor and model that produced a reply, named as in the model menu, e.g. "Claude / Sonnet".
    func speaker(of message: BookChatMessage) -> String {
        let backend = ChatBackend(rawValue: message.backend)
        guard let model = message.model, !model.isEmpty else { return (backend?.title ?? "Pi") + " / 자동" }
        let label = backend.flatMap { models[$0] }?.first(where: { $0.id == model })?.label ?? model
        return (backend?.title ?? "Pi") + " / " + label
    }
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
                messages[index].state = receivedAnswer ? "complete" : "failed"
                finishTurn(at: index, openSteps: receivedAnswer ? "done" : "failed")
            }
            assistantID = nil; busy = false; operation = ""; activityMessage = ""; bridge = nil; _ = persist()
        }
    }
    private func receive(_ event: AgentEvent, backend: ChatBackend) {
        switch event.type {
        case "status": if let status = event.status { accounts[backend] = status }
        case "models": if let options = event.models { models[backend] = options }
        case "activity":
            activityMessage = event.message ?? ""
            if operation == "chat" { recordActivity(activityMessage) }
        case "reading":
            guard let reading = event.reading, reading.bookID == bookID,
                  let index = messages.firstIndex(where: { $0.id == assistantID }), reading.scope == messages[index].scope,
                  (reading.readPages + reading.sourcePages + reading.emptyPages).allSatisfy({ reading.scope.contains($0) }) else { return }
            let old = messages[index].reading
            let merged = BookReadingCoverage(bookID: reading.bookID, scope: reading.scope,
                readPages: Array(Set((old?.readPages ?? []) + reading.readPages)).sorted(),
                sourcePages: Array(Set((old?.sourcePages ?? []) + reading.sourcePages)).sorted(),
                emptyPages: Array(Set((old?.emptyPages ?? []) + reading.emptyPages)).sorted())
            messages[index].reading = merged
            hasUnsavedChanges = true
            // The oldest open step without a result owns this tool's coverage report.
            updateSteps { steps in
                guard let i = steps.firstIndex(where: { $0.state == "running" && $0.result == nil }) else { return }
                steps[i].result = PiStepWording.result(for: steps[i], before: old, after: merged)
            }
        case "attachment":
            guard backend == .codex, let attachment = event.attachment, attachment.kind == "image",
                  let index = messages.firstIndex(where: { $0.id == assistantID }),
                  ChatAssetStore.generatedImageURL(for: attachment, directory: store.directory) != nil else {
                errorMessage = "생성된 이미지를 보관하지 못했습니다."; return
            }
            if !(messages[index].attachments ?? []).contains(where: { $0.id == attachment.id }) {
                messages[index].attachments = (messages[index].attachments ?? []) + [attachment]
                let count = messages[index].attachments?.filter { $0.kind == "image" }.count ?? 1
                updateSteps { steps in
                    if let i = steps.lastIndex(where: { $0.kind == "image" && $0.state == "running" }) { steps[i].result = "그림 \(count)장 만듦" }
                }
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

/// Why the composer cannot send yet. An empty draft is not a reason: the empty field already shows it.
enum PiComposerBlock: Equatable {
    case nodeMissing, bridgeMissing
    case checkingAccount(ChatBackend), signingIn(ChatBackend)
    case accountDisconnected(ChatBackend), accountUnknown(ChatBackend)
    case documentLoading, choosingRange, editingQuestion, tooLong

    static func evaluate(nodeFound: Bool, bridgeFound: Bool, backend: ChatBackend, connected: Bool?, checking: Bool,
                         operation: String, documentReady: Bool, choosingRange: Bool, editing: Bool, draft: String) -> PiComposerBlock? {
        if !bridgeFound { return .bridgeMissing }
        if !nodeFound { return .nodeMissing }
        if connected != true {
            if operation == "login" { return .signingIn(backend) }
            if checking { return .checkingAccount(backend) }
            return connected == false ? .accountDisconnected(backend) : .accountUnknown(backend)
        }
        if !documentReady { return .documentLoading }
        if choosingRange { return .choosingRange }
        if editing { return .editingQuestion }
        if draft.utf16.count > 10000 { return .tooLong }
        return nil
    }
    /// Runtime and account problems replace the suggestions with a card that opens the Pi settings.
    var needsConnection: Bool {
        switch self {
        case .nodeMissing, .bridgeMissing, .accountDisconnected, .accountUnknown: return true
        default: return false
        }
    }
    var message: String {
        switch self {
        case .nodeMissing: return "Pi를 실행하려면 Node.js 22.19 이상이 필요합니다."
        case .bridgeMissing: return "이 앱에는 Pi 실행 모듈이 없습니다."
        case .checkingAccount(let backend): return "\(backend.title) 연결을 확인하고 있습니다."
        case .signingIn(let backend): return "\(backend.title) 로그인을 마치면 질문할 수 있습니다."
        case .accountDisconnected(let backend): return "\(backend.title) 계정이 연결되지 않았습니다."
        case .accountUnknown(let backend): return "\(backend.title) 연결 상태를 확인하지 못했습니다."
        case .documentLoading: return "PDF를 불러오고 있습니다."
        case .choosingRange: return "페이지 범위를 고르는 중입니다."
        case .editingQuestion: return "수정 중인 질문을 먼저 마쳐 주세요."
        case .tooLong: return "질문은 10000자 이내로 입력해 주세요."
        }
    }
}

extension BookReadingCoverage {
    /// The same coverage without source pages after `page`, for a reader who has not got there yet.
    func sources(through page: Int) -> BookReadingCoverage {
        var copy = self; copy.sourcePages.removeAll { $0 > page }; return copy
    }
}

extension BookReadingScope {
    /// Composer label: the scope and the reader's page together, matching the scope menu's item names.
    func composerLabel(currentPage: Int) -> String {
        if mode == "book" { return "이 책 전체, \(currentPage)쪽에서" }
        if mode == "page" { return "현재 쪽(\(startPage)쪽)" }
        return "\(startPage)~\(endPage)쪽"
    }
}

/// Turns the bridge's activity sentences (`bookToolActivity` in book-tools.ts, image generation in
/// codex.ts) and coverage reports into transcript step lines. Unknown sentences stay readable as is.
enum PiStepWording {
    static func step(for activity: String) -> ChatStep {
        if activity.hasPrefix("책에서 관련 내용을 찾") { return ChatStep(kind: "search", title: "책 검색") }
        if activity.hasPrefix("읽은 범위를 확인") { return ChatStep(kind: "coverage", title: "읽은 범위 확인") }
        if activity.hasPrefix("책의 목차를 확인") { return ChatStep(kind: "outline", title: "목차 확인") }
        if activity.hasPrefix("이미지를 만들") { return ChatStep(kind: "image", title: "그림 만들기") }
        if let range = activity.range(of: "쪽을 읽고 있습니다") {
            let pages = String(activity[..<range.lowerBound])
            if !pages.isEmpty, pages.allSatisfy({ $0.isNumber || $0 == "~" }) { return ChatStep(kind: "read", title: "책 읽기", detail: pages + "쪽") }
        }
        return ChatStep(kind: "other", title: activity.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))
    }
    /// Child line from the reply's coverage after this tool call. Empty means nothing to report.
    /// Coverage is cumulative, so a page read counts the pages the call asked for and other tools count what they added.
    static func result(for step: ChatStep, before: BookReadingCoverage?, after: BookReadingCoverage) -> String {
        let asked = step.kind == "read" ? pages(in: step.detail) : nil
        func count(_ path: KeyPath<BookReadingCoverage, [Int]>) -> Int {
            let pages = Set(after[keyPath: path])
            return asked.map { pages.intersection($0).count } ?? pages.subtracting(before?[keyPath: path] ?? []).count
        }
        let read = count(\.readPages), seen = count(\.sourcePages), empty = count(\.emptyPages)
        switch step.kind {
        case "read":
            let blank = empty > 0 ? ", 글자 없는 쪽 \(empty)" : ""
            return (read > 0 ? "\(read)쪽 읽음" : seen > 0 ? "\(seen)쪽 일부 읽음" : "읽은 쪽 없음") + blank
        case "search": return seen > 0 ? "관련 쪽 \(seen)곳 찾음" : "새로 찾은 쪽 없음"
        case "coverage": return "본문 \(after.readPages.count)/\(after.scope.pageCount)쪽 확인"
        default: return ""
        }
    }
    /// Pages named in a read step's detail, "27~29쪽" or "5쪽".
    private static func pages(in detail: String?) -> ClosedRange<Int>? {
        guard let bounds = detail?.replacingOccurrences(of: "쪽", with: "").split(separator: "~").map({ Int($0) }),
              let first = bounds.first ?? nil, let last = bounds.last ?? nil, bounds.count <= 2, first <= last else { return nil }
        return first...last
    }
}
