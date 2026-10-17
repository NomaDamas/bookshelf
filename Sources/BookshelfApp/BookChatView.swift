import SwiftUI
import BookshelfCore
import UniformTypeIdentifiers

struct BookChatView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var chat: BookChatModel
    let book: Book
    @AppStorage("agent.includeNotes") private var includeNotes = true
    @State private var showingProfile = false
    @State private var followTail = true
    @State private var confirmingClear = false
    @State private var editingQuestion: BookChatMessage?
    @FocusState private var composerFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var currentText: String { model.document?.page(at: model.page - 1)?.string ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("AI와 읽기", systemImage: "bubble.left.and.bubble.right").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    ReaderIconButton(symbol: "arrow.uturn.backward", label: "대화 변경 되돌리기") { chat.undoEdit() }
                        .disabled(!chat.canUndoEdit || chat.busy)
                    ReaderIconButton(symbol: "trash", label: "이 책의 대화 비우기") { confirmingClear = true }
                        .disabled(chat.messages.isEmpty || chat.busy)
                }
                HStack(spacing: 6) {
                    Image(systemName: chat.account?.connected == true ? "checkmark.circle" : "person.crop.circle.badge.questionmark")
                    Text(chat.account?.label ?? "연결 확인 전").lineLimit(2)
                    Spacer(minLength: 4)
                    Button("연결 설정") { openConnectionSettings() }.controlSize(.small).accessibilityLabel("AI 연결 설정")
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                ContextUsageView(usage: chat.contextUsage)
                if !AgentRuntime.ready {
                    Text("Node.js와 AI 연결 모듈이 필요합니다. 실험용 앱으로 실행해 주세요.")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
            }.padding(16)
            ReaderHairline()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if chat.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("읽다가 막힌 부분을 물어보세요.").font(.system(size: 16, weight: .medium))
                                Text("현재 페이지와 선택한 문장을 바탕으로 설명합니다. 대화는 이 책에 저장됩니다.")
                                    .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5)
                                Button("이 페이지를 쉽게 설명해줘") { chat.draft = "이 페이지의 핵심 내용을 작은 예시와 함께 쉽게 설명해줘." }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }.padding(.vertical, 14)
                        }
                        ForEach(chat.messages) { message in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(message.attachments?.isEmpty == false ? "이 책의 자료" : message.role == "user" ? "나" : (message.harness == "pi" ? "Pi + " : "") + (ChatBackend(rawValue: message.backend)?.title ?? "도우미"))
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                    Spacer()
                                    if message.role == "user" && (message.attachments?.isEmpty ?? true) {
                                        Button { editingQuestion = message } label: { Image(systemName: "pencil") }
                                            .buttonStyle(.plain).accessibilityLabel("질문 수정").help("질문 수정").disabled(chat.busy)
                                    }
                                    Button { chat.deleteFrom(message.id) } label: { Image(systemName: "trash") }
                                        .buttonStyle(.plain).accessibilityLabel("이 메시지부터 지우기").help("이 메시지부터 지우기").disabled(chat.busy)
                                    if message.role == "assistant" && message.state != "complete" {
                                        Text(chat.busy && message.id == chat.messages.last?.id ? "답변 중" : message.state == "failed" ? "완료하지 못함" : "중단됨")
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                }
                                if let attachments = message.attachments {
                                    ForEach(attachments) { ChatAttachmentView(attachment: $0, directory: model.store.directory) }
                                }
                                if message.text.isEmpty && message.role == "assistant" && chat.busy && message.id == chat.messages.last?.id {
                                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("답변을 준비하고 있습니다.").font(.system(size: 12)).foregroundStyle(.secondary) }
                                }
                                else if !message.text.isEmpty { ChatResponseView(text: message.text, streaming: chat.busy && message.id == chat.messages.last?.id) }
                                if message.role == "assistant" && !message.text.isEmpty {
                                    HStack(spacing: 10) {
                                        Button("질문한 \(message.page)쪽") { model.goToPage(message.page) }
                                            .help("질문할 때 전달한 PDF 페이지로 이동합니다.")
                                        Spacer()
                                        if message.id == chat.messages.last?.id {
                                            Button { retry() } label: { Image(systemName: "arrow.clockwise") }
                                                .accessibilityLabel("답변 다시 생성").disabled(chat.busy || chat.lastQuestion == nil)
                                        }
                                        Button { copy(message.text) } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("답변 복사")
                                        if message.state == "complete" {
                                            Button("메모에 담기") {
                                                guard model.activeBook?.id == book.id else { return }
                                                model.editNotebook(model.notebookText + (model.notebookText.isEmpty ? "" : "\n\n") + "[AI 대화 / PDF \(message.page)쪽]\n" + message.text)
                                                model.sidebarVisible = true; model.panelTab = "notes"
                                            }
                                        }
                                    }.font(.system(size: 11)).buttonStyle(.borderless)
                                }
                                if message.role == "assistant" && message.text.isEmpty && !chat.busy && message.id == chat.messages.last?.id {
                                    Button("다시 시도") { retry() }.buttonStyle(.bordered).controlSize(.small)
                                }
                            }.padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.role == "user" ? ReaderStyle.muted : .clear,
                                            in: RoundedRectangle(cornerRadius: ReaderTokens.radiusLarge))
                                .id(message.id)
                                .transition(.opacity.combined(with: .offset(y: 6)))
                        }
                        Color.clear.frame(height: 1).id("conversation-end")
                            .background(ChatScrollObserver(nearBottom: { if $0 && !followTail { followTail = true } }, scrolledAway: { if followTail { followTail = false } }))
                    }.padding(14).animation(reduceMotion ? nil : ReaderMotion.ease(ReaderTokens.messageDuration), value: chat.messages.count)
                }.onChange(of: chat.messages.last?.text) { _, _ in if followTail { proxy.scrollTo("conversation-end", anchor: .bottom) } }
                    .onChange(of: chat.messages.count) { _, _ in
                        if chat.messages.last?.backend == "local" { followTail = true }
                        if followTail { withAnimation(reduceMotion ? nil : ReaderMotion.ease(ReaderTokens.messageDuration)) { proxy.scrollTo("conversation-end", anchor: .bottom) } }
                    }
                    .onAppear { proxy.scrollTo("conversation-end", anchor: .bottom) }
                    .overlay(alignment: .bottom) {
                        if !followTail {
                            Button { followTail = true; withAnimation(reduceMotion ? nil : ReaderMotion.ease(ReaderTokens.messageDuration)) { proxy.scrollTo("conversation-end", anchor: .bottom) } } label: { Label("최신 답변", systemImage: "arrow.down") }
                                .buttonStyle(.bordered).controlSize(.small).padding(.bottom, 10).transition(.opacity)
                        }
                    }
            }
            if let error = chat.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).textSelection(.enabled)
                    Spacer(minLength: 0)
                    if chat.hasUnsavedChanges { Button("저장 재시도") { chat.persist() } }
                }.font(.system(size: 11)).foregroundStyle(.orange).padding(12)
            }
            if chat.operation == "login" {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("브라우저에서 공식 로그인을 완료해 주세요.")
                    if let url = chat.loginURL { Link("열기", destination: url) }
                }.font(.system(size: 11)).padding(12)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("PDF \(model.page)쪽").monospacedDigit()
                    Menu {
                        Button("쉽게 설명") { chat.skill = "explain" }
                        Button("비교표") { chat.skill = "compare" }
                        Button("시각 자료로 설명") { chat.skill = "visualize" }
                    } label: { Text(chat.skill == "visualize" ? "시각 자료" : chat.skill == "compare" ? "비교표" : "쉽게 설명") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("설명 방식").disabled(chat.busy)
                    Spacer()
                    Toggle("노트 포함", isOn: $includeNotes).toggleStyle(.checkbox)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                TextEditor(text: $chat.draft).font(.system(size: 14)).scrollContentBackground(.hidden)
                    .focused($composerFocused)
                    .frame(minHeight: 56, maxHeight: 100).padding(.vertical, 4)
                    .overlay(alignment: .topLeading) {
                        if chat.draft.isEmpty { Text("이 페이지에서 궁금한 점을 물어보세요.").font(.system(size: 13)).foregroundStyle(.tertiary).padding(.leading, 5).padding(.top, 12).allowsHitTesting(false) }
                    }
                    .accessibilityLabel("책에 질문").accessibilityIdentifier("book-chat-composer")
                HStack {
                    ReaderIconButton(symbol: "paperclip", label: "시각 및 음성 자료 열기", action: chooseAssets)
                        .help("파일을 이 책에 보관하고 재생합니다. 자료 내용은 AI에 전송하지 않습니다.")
                        .disabled(chat.importingAssets || chat.busy)
                    if chat.importingAssets { ProgressView().controlSize(.mini) }
                    ChatModelMenu(chat: chat, openSettings: openConnectionSettings)
                    Spacer()
                    ReaderIconButton(symbol: "info.circle", label: "학습 전용 지침 보기") { showingProfile = true }
                        .popover(isPresented: $showingProfile) { LearningProfileView() }
                    if chat.busy {
                        Button { chat.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 11)).frame(width: 28, height: 28) }
                            .buttonStyle(.bordered).clipShape(Circle()).accessibilityLabel("답변 중단")
                    }
                    else {
                        Button { send() } label: { Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).frame(width: 28, height: 28) }
                            .buttonStyle(.borderedProminent).clipShape(Circle()).accessibilityLabel("질문하기").help("질문하기 (\(model.shortcuts[.sendMessage].label))")
                            .keyboardShortcut(model.shortcuts[.sendMessage].value)
                            .disabled(editingQuestion != nil || chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.document == nil || !AgentRuntime.ready || chat.account?.connected != true)
                    }
                }
            }.padding(14)
                .background(ReaderStyle.panel, in: RoundedRectangle(cornerRadius: ReaderTokens.composerRadius, style: .continuous))
                .modifier(ReaderSurfaceBorder(radius: ReaderTokens.composerRadius))
                .overlay { RoundedRectangle(cornerRadius: ReaderTokens.composerRadius, style: .continuous).strokeBorder(composerFocused ? ReaderStyle.accent.opacity(0.45) : .clear, lineWidth: 1).allowsHitTesting(false) }
                .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
                .animation(reduceMotion ? nil : ReaderMotion.ease(ReaderTokens.controlDuration), value: composerFocused)
                .padding(12)
        }.background(ReaderStyle.canvas)
            .confirmationDialog("이 책의 대화를 비울까요?", isPresented: $confirmingClear) {
                Button("대화 비우기") { chat.clearConversation() }
                Button("취소", role: .cancel) { }
            } message: { Text("삭제 후에도 되돌리기로 복원할 수 있습니다. 책 메모와 발췌는 보존됩니다.") }
            .sheet(item: $editingQuestion) { message in
                ChatQuestionEditor(message: message, shortcut: model.shortcuts[.sendMessage].value) { text in
                    guard model.activeBook?.id == book.id else { return }
                    followTail = true; chat.reviseQuestion(message.id, text: text, context: context(page: message.page))
                }
            }
            .task(id: book.id) {
                guard !Task.isCancelled, model.activeBook?.id == book.id else { return }
                if chat.selectBook(book.id), chat.account == nil, AgentRuntime.ready { chat.checkConnection() }
            }
    }
    private func send() {
        if NSApp.currentEvent?.type == .keyDown, let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return }
        guard model.activeBook?.id == book.id, model.flushPendingSave() else { return }
        followTail = true; composerFocused = true
        chat.send(context: AgentRequest.Context(id: book.id, title: book.title, page: model.page,
                  text: currentText, notes: includeNotes ? model.notebookText : "", selection: model.selection.map(\.quote).joined(separator: "\n")))
    }
    private func context(page: Int) -> AgentRequest.Context {
        AgentRequest.Context(id: book.id, title: book.title, page: page, text: model.document?.page(at: page - 1)?.string ?? "",
                             notes: includeNotes ? model.notebookText : "", selection: "")
    }
    private func retry() {
        guard model.activeBook?.id == book.id, let question = chat.lastQuestion, !chat.busy else { return }
        followTail = true; chat.reviseQuestion(question.id, text: question.text, context: context(page: question.page))
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    private func openConnectionSettings() { model.settingsTab = "ai"; model.showSettings = true }
    private func chooseAssets() {
        let target = book.id, page = model.page
        let panel = NSOpenPanel(); panel.title = "이 책에서 볼 자료 선택"
        panel.message = "자료는 이 Mac에 보관됩니다. 파일 내용은 AI에 전송하지 않습니다."
        panel.allowedContentTypes = ChatAssetStore.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, model.activeBook?.id == target else { return }
            chat.addAttachments(panel.urls, bookID: target, page: page)
        }
    }
}

private struct ChatQuestionEditor: View {
    let message: BookChatMessage
    let shortcut: KeyboardShortcut
    let submit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("질문 수정").font(.headline)
            Text("수정한 질문부터 다시 답합니다. 이전 대화는 되돌리기로 복원할 수 있습니다.").font(.system(size: 12)).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(size: 14)).frame(minHeight: 140).accessibilityLabel("수정할 질문")
            HStack { Spacer(); Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("수정하고 다시 질문") { submit(text); dismiss() }.keyboardShortcut(shortcut).buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.utf16.count > 10000)
            }
        }.padding(22).frame(width: 520, height: 300).onAppear { text = message.text }
    }
}

private struct LearningProfileView: View {
    private var text: String {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Agent/profile.json"),
              let data = try? Data(contentsOf: url), let profile = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let instructions = profile["systemPrompt"] as? String else { return "학습 지침을 불러오지 못했습니다." }
        return instructions
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("학습 전용 지침").font(.headline)
            Text("공통 지침은 영어로 작성하며 답변은 사용자의 언어를 따릅니다. 설명, 비교표와 시각 자료를 제공합니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView { Text(text).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(20).frame(width: 440, height: 420)
    }
}

struct ChatMarkdownText: View {
    let text: String
    private struct Block: Identifiable { let id: Int; let text: String; let table: [[String]]? }
    private var blocks: [Block] {
        let lines = text.components(separatedBy: "\n"); var result: [Block] = [], index = 0
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                var rows: [[String]] = []
                while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let line = lines[index]; index += 1
                    if line.allSatisfy({ "|:- \t".contains($0) }) { continue }
                    rows.append(line.trimmingCharacters(in: CharacterSet(charactersIn: "| ")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) })
                }
                result.append(Block(id: result.count, text: "", table: rows))
            } else {
                var paragraph: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") { paragraph.append(lines[index]); index += 1 }
                result.append(Block(id: result.count, text: paragraph.joined(separator: "\n"), table: nil))
            }
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                if let rows = block.table {
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { row, cells in
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                                        Text(inline(cell)).font(.system(size: 12, weight: row == 0 ? .semibold : .regular))
                                            .frame(width: 128, alignment: .leading)
                                    }
                                }.padding(.vertical, 8)
                                ReaderHairline()
                            }
                        }
                    }
                } else { Text(inline(block.text)).font(.system(size: ReaderTokens.bodyFont)).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
    }
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
