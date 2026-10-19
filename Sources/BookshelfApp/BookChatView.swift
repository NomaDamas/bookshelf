import SwiftUI
import BookshelfCore
import UniformTypeIdentifiers

struct BookChatView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var chat: BookChatModel
    let book: Book
    @AppStorage("agent.includeNotes") private var includeNotes = true
    @State private var showingProfile = false
    @State private var showingUsage = false
    @State private var followTail = true
    @State private var confirmingClear = false
    @State private var pendingDelete: BookChatMessage?
    @State private var editingID: String?
    @State private var editText = ""
    @State private var choosingRange = false
    @FocusState private var composerFocused: Bool
    @FocusState private var editorFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var currentText: String { model.document?.page(at: model.page - 1)?.string ?? "" }
    private var pageCount: Int { model.document?.pageCount ?? book.pageCount }
    private var scope: BookReadingScope { chat.readingScope(page: model.page, pageCount: pageCount) }
    private var composerBlock: PiComposerBlock? {
        PiComposerBlock.evaluate(nodeFound: AgentRuntime.findExecutable("node") != nil, bridgeFound: AgentRuntime.bridgeURL != nil,
                                 backend: chat.backend, connected: chat.account?.connected,
                                 checking: chat.checkingStatus || !chat.checkedBackends.contains(chat.backend),
                                 operation: chat.operation, documentReady: model.document != nil,
                                 choosingRange: choosingRange, editing: editingID != nil, draft: chat.draft)
    }
    private var motion: Animation? { reduceMotion ? nil : ReaderMotion.ease(ReaderTokens.messageDuration) }

    var body: some View {
        let block = composerBlock
        VStack(spacing: 0) {
            header
            ReaderHairline()
            conversation(block)
            // With a conversation on screen the card stays pinned above the composer instead of scrolling with replies.
            if !chat.messages.isEmpty, let block, block.needsConnection {
                connectionNotice(block).padding(.horizontal, 16).padding(.top, 10).transition(.opacity)
            }
            if let error = chat.errorMessage { errorBanner(error) }
            if chat.operation == "login" { loginStrip }
            composer(block)
        }.background(ReaderStyle.canvas)
            .confirmationDialog("이 책의 대화를 비울까요?", isPresented: $confirmingClear) {
                Button("대화 비우기", role: .destructive) { chat.clearConversation() }
                Button("취소", role: .cancel) { }
            } message: { Text("Pi 메뉴의 되돌리기로 복원할 수 있습니다. 책 메모와 발췌는 보존됩니다.") }
            .confirmationDialog("이 메시지부터 끝까지 지울까요?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { message in
                Button("여기부터 지우기", role: .destructive) { chat.deleteFrom(message.id) }
                Button("취소", role: .cancel) { }
            } message: { _ in Text("Pi 메뉴의 되돌리기로 복원할 수 있습니다.") }
            .sheet(isPresented: $choosingRange) {
                ChatPageRangeEditor(pageCount: pageCount, currentPage: model.page, selected: chat.pageRange) { range in
                    chat.pageRange = range; chat.scopeMode = "range"
                }
            }
            .task(id: book.id) {
                guard !Task.isCancelled, model.activeBook?.id == book.id else { return }
                if chat.selectBook(book.id), chat.account == nil, AgentRuntime.ready { chat.checkConnection() }
            }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            // The window toolbar already shows the book title, so the header keeps only the page.
            Text("Pi").font(.system(size: 14, weight: .bold)).accessibilityAddTraits(.isHeader)
            Text("\(model.page)쪽").foregroundStyle(.secondary).monospacedDigit().fixedSize()
            Spacer(minLength: 4)
            Menu {
                Button("되돌리기") { chat.undoEdit() }.disabled(!chat.canUndoEdit || chat.busy)
                Button("대화 복사") { copy(chat.transcript()) }.disabled(chat.messages.isEmpty)
                Button("대화 비우기…") { confirmingClear = true }.disabled(chat.messages.isEmpty || chat.busy)
                Divider()
                Button(ContextUsageDetails.summary(chat.contextUsage).map { "컨텍스트 사용량 \($0)…" } ?? "컨텍스트 사용량…") {
                    DispatchQueue.main.async { showingUsage = true }
                }
                Button("학습 지침 보기…") { DispatchQueue.main.async { showingProfile = true } }
                Divider()
                Button("연결 설정…") { openConnectionSettings() }
            } label: { Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Pi 메뉴").help("되돌리기, 대화 복사와 비우기, 연결 설정")
                .popover(isPresented: $showingUsage, arrowEdge: .bottom) { ContextUsageDetails(usage: chat.contextUsage) }
                .background { Color.clear.popover(isPresented: $showingProfile, arrowEdge: .bottom) { LearningProfileView() } }
        }.font(.system(size: 13)).padding(.horizontal, 16).frame(height: ReaderStyle.toolbarHeight)
    }

    // MARK: Conversation

    private func conversation(_ block: PiComposerBlock?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if chat.messages.isEmpty {
                        if let block, block.needsConnection { connectionNotice(block).padding(.vertical, 14) } else { emptyState }
                    }
                    ForEach(chat.messages) { message in messageView(message) }
                    if !chat.messages.isEmpty && block?.needsConnection != true && showsFollowUps {
                        PiSuggestions(choose: suggest).padding(.leading, PiTranscript.gutter).transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id("conversation-end")
                        .background(ChatScrollObserver(nearBottom: { if $0 && !followTail { followTail = true } }, scrolledAway: { if followTail { followTail = false } }))
                }.padding(16).animation(motion, value: chat.messages.count).animation(motion, value: showsFollowUps)
            }.onChange(of: chat.messages.last?.text) { _, _ in if followTail { proxy.scrollTo("conversation-end", anchor: .bottom) } }
                .onChange(of: chat.messages.last?.attachments?.count) { _, _ in if followTail { proxy.scrollTo("conversation-end", anchor: .bottom) } }
                // Steps and their result lines grow the turn before any answer text arrives.
                .onChange(of: chat.messages.last?.steps) { _, _ in if followTail { proxy.scrollTo("conversation-end", anchor: .bottom) } }
                .onChange(of: chat.messages.count) { _, _ in
                    if chat.messages.last?.backend == "local" { followTail = true }
                    if followTail { withAnimation(motion) { proxy.scrollTo("conversation-end", anchor: .bottom) } }
                }
                // Follow-up suggestions arrive when a reply completes; scroll once they are laid out.
                .onChange(of: showsFollowUps) { _, shown in
                    guard shown && followTail else { return }
                    DispatchQueue.main.async { withAnimation(motion) { proxy.scrollTo("conversation-end", anchor: .bottom) } }
                }
                .onAppear { proxy.scrollTo("conversation-end", anchor: .bottom) }
                .overlay(alignment: .bottom) {
                    if !followTail {
                        Button { followTail = true; withAnimation(motion) { proxy.scrollTo("conversation-end", anchor: .bottom) } } label: { Label("최신 답변", systemImage: "arrow.down") }
                            .buttonStyle(.bordered).controlSize(.small).padding(.bottom, 10).transition(.opacity)
                    }
                }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("읽다가 막힌 부분을 Pi에게 물어보세요.").font(.system(size: 16, weight: .medium))
            Text("Pi는 이 책에서 필요한 쪽을 찾아 읽고 설명합니다. 지금 보는 쪽과 선택한 문장도 함께 참고합니다. 질문 범위와 설명 방식은 입력창 위에서 고를 수 있습니다.")
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            PiSuggestions(choose: suggest)
        }.padding(.vertical, 14)
    }

    private func connectionNotice(_ block: PiComposerBlock) -> some View {
        PiConnectionNotice(block: block, connect: openConnectionSettings, recheck: { chat.checkConnection() })
    }

    private var showsFollowUps: Bool {
        guard !chat.busy, editingID == nil, let last = chat.messages.last else { return false }
        return last.role == "assistant" && last.state == "complete" && !last.text.isEmpty
    }

    /// Transcript turn: "❯ question", tool steps, the answer as plain text, then a muted summary line.
    /// Turns are told apart by space and type weight rather than bubbles or borders.
    @ViewBuilder private func messageView(_ message: BookChatMessage) -> some View {
        let question = message.role == "user" && message.backend != "local"
        VStack(alignment: .leading, spacing: 10) {
            if question { questionContent(message) }
            else if message.backend == "local" { assetContent(message) }
            else { replyContent(message) }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, message.role == "user" && message.id != chat.messages.first?.id ? 14 : 0)
            .contentShape(Rectangle())
            .contextMenu { messageMenu(message, question: question) }
            .id(message.id)
            .transition(.opacity.combined(with: .offset(y: 6)))
    }

    @ViewBuilder private func questionContent(_ message: BookChatMessage) -> some View {
        let editing = editingID == message.id
        PiGutterRow(alignment: editing ? .top : .firstTextBaseline) {
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                .padding(.top, editing ? 11 : 0).accessibilityHidden(true)
        } content: {
            if editing { questionEditor(message) }
            else {
                VStack(alignment: .leading, spacing: 5) {
                    Text(message.text).font(.system(size: ReaderTokens.bodyFont, weight: .medium)).lineSpacing(4)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("질문: " + message.text)
                    HStack(spacing: 6) {
                        Button(questionMeta(message)) { openPage(message.page) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .help("질문할 때 보던 \(message.page)쪽으로 이동합니다.")
                        Spacer(minLength: 4)
                        if message.attachments?.isEmpty ?? true {
                            ReaderIconButton(symbol: "pencil", label: "질문 수정", compact: true) { beginEdit(message) }
                                .disabled(chat.busy || editingID != nil)
                        }
                    }.font(.system(size: 11)).padding(.top, -3)
                }
            }
        }
    }

    private func questionEditor(_ message: BookChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $editText).font(.system(size: 14)).scrollContentBackground(.hidden)
                .focused($editorFocused).frame(minHeight: 56, maxHeight: 160).padding(6)
                .background(ReaderStyle.panel, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusMedium, style: .continuous))
                .modifier(ReaderSurfaceBorder(radius: ReaderTokens.radiusMedium))
                .accessibilityLabel("수정할 질문")
            Text("수정한 질문부터 다시 답합니다. 이전 대화는 Pi 메뉴의 되돌리기로 복원할 수 있습니다.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("취소") { editingID = nil }.keyboardShortcut(.cancelAction)
                Button("다시 질문") { submitEdit(message) }.buttonStyle(.borderedProminent)
                    .keyboardShortcut(model.shortcuts[.sendMessage].value)
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editText.utf16.count > 10000 || chat.busy)
            }.controlSize(.small)
        }
    }

    @ViewBuilder private func assetContent(_ message: BookChatMessage) -> some View {
        PiGutterRow { Image(systemName: "doc").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) } content: {
            Text("이 책의 자료").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
        }
        ForEach(message.attachments ?? []) { ChatAttachmentView(attachment: $0, directory: model.store.directory) }
            .padding(.leading, PiTranscript.gutter)
    }

    @ViewBuilder private func replyContent(_ message: BookChatMessage) -> some View {
        let isLast = message.id == chat.messages.last?.id
        let streaming = chat.busy && isLast && message.role == "assistant"
        if let steps = message.steps, !steps.isEmpty {
            VStack(alignment: .leading, spacing: 8) { ForEach(steps) { PiStepRow(step: $0) } }
                .padding(.bottom, 4).animation(motion, value: steps.count)
        }
        Group {
            if let attachments = message.attachments {
                ForEach(attachments) { ChatAttachmentView(attachment: $0, directory: model.store.directory) }
            }
            if !message.text.isEmpty {
                ChatResponseView(text: message.text, streaming: streaming, sourcePages: Set(message.sourcePages)) { page in openPage(page) }
            }
            if !streaming, let reading = message.reading, !message.text.isEmpty {
                ChatReadingSources(reading: reading) { page in openPage(page) }
            }
        }.padding(.leading, PiTranscript.gutter)
        if streaming { runningLine(message) } else { turnLine(message, isLast: isLast) }
    }

    private var turnMark: some View {
        Image(systemName: "asterisk").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
    }

    /// "✻ 생각하는 중, 8초" while the reply streams; the clock ticks once a second.
    private func runningLine(_ message: BookChatMessage) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            PiGutterRow { turnMark } content: {
                Text(PiTurnWording.running(started: message.created, writing: !message.text.isEmpty, now: context.date))
                    .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
            }
        }.accessibilityIdentifier("pi-turn-running")
    }

    /// "✻ 12초 동안 작업, 오후 9:41 완료, Claude / Sonnet" with copy, regenerate and save-to-notes on the same line.
    private func turnLine(_ message: BookChatMessage, isLast: Bool) -> some View {
        let hasText = !message.text.isEmpty
        return HStack(alignment: .center, spacing: 6) {
            PiGutterRow {
                if message.state == "failed" { PiStatusMark(kind: .needsYou) } else { turnMark }
            } content: {
                Text(PiTurnWording.finished(message, speaker: chat.speaker(of: message)))
                    .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .help(message.harness == "pi" ? "Pi가 이 실행기로 답했습니다." : "Pi 계층 없이 실행기에 직접 요청했습니다.")
            }
            HStack(spacing: 2) {
                if hasText { ReaderIconButton(symbol: "doc.on.doc", label: "답변 복사", compact: true) { copy(message.text) } }
                if isLast {
                    ReaderIconButton(symbol: "arrow.clockwise", label: message.state == "complete" ? "다시 생성" : "다시 시도", compact: true, action: retry)
                        .disabled(!canRetry)
                }
                if hasText && message.state == "complete" {
                    ReaderIconButton(symbol: "note.text.badge.plus", label: "메모에 담기", compact: true) { saveToNotes(message) }
                }
            }.fixedSize().padding(.trailing, -5)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("pi-turn-summary")
    }

    @ViewBuilder private func messageMenu(_ message: BookChatMessage, question: Bool) -> some View {
        if question {
            if message.attachments?.isEmpty ?? true {
                Button("질문 수정") { beginEdit(message) }.disabled(chat.busy || editingID != nil)
            }
            Button("질문 복사") { copy(message.text) }.disabled(message.text.isEmpty)
        } else if message.role == "assistant" {
            Button("답변 복사") { copy(message.text) }.disabled(message.text.isEmpty)
            if message.state == "complete" && !message.text.isEmpty { Button("메모에 담기") { saveToNotes(message) } }
        }
        Divider()
        Button("여기부터 지우기…") { pendingDelete = message }.disabled(chat.busy)
    }

    private func questionMeta(_ message: BookChatMessage) -> String {
        let page = "\(message.page)쪽에서 질문"
        guard let scope = message.scope, scope.mode != "book" else { return page }
        return page + ", " + (scope.mode == "page" ? "현재 쪽만" : "\(scope.startPage)~\(scope.endPage)쪽 안에서")
    }

    // MARK: Status strips

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(error).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if chat.hasUnsavedChanges { Button("저장 재시도") { chat.persist() }.controlSize(.small) }
            Button { chat.errorMessage = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("오류 닫기").help("오류 닫기")
        }.font(.system(size: 11)).padding(12).background(Color.orange.opacity(0.08))
    }

    /// Sign-in waits on the reader in the browser, so it carries the orange "needs you" ring.
    private var loginStrip: some View {
        PiGutterRow { PiStatusMark(kind: .needsYou) } content: {
            HStack(spacing: 8) {
                Text("브라우저에서 \((chat.loginBackend ?? chat.backend).title) 공식 로그인을 완료해 주세요.")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let url = chat.loginURL { Link("열기", destination: url) }
                Button("취소") { chat.stop() }.controlSize(.small)
            }
        }.font(.system(size: 12)).padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: Composer

    private func composer(_ block: PiComposerBlock?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { scopeMenu; notesToggle; explanationMenu }
                VStack(alignment: .leading, spacing: 6) { scopeMenu; HStack(spacing: 6) { notesToggle; explanationMenu } }
            }.frame(maxWidth: .infinity, alignment: .leading).disabled(chat.busy)
            TextEditor(text: $chat.draft).font(.system(size: 14)).scrollContentBackground(.hidden)
                .focused($composerFocused)
                .frame(minHeight: 56, maxHeight: 100).padding(.vertical, 2)
                .overlay(alignment: .topLeading) {
                    if chat.draft.isEmpty { Text("이 책에 대해 Pi에게 물어보세요.").font(.system(size: 13)).foregroundStyle(.tertiary).padding(.leading, 5).padding(.top, 10).allowsHitTesting(false) }
                }
                .accessibilityLabel("Pi에게 질문").accessibilityIdentifier("book-chat-composer")
            HStack(spacing: 4) {
                ReaderIconButton(symbol: "doc", label: "자료 열기", action: chooseAssets)
                    .help("자료 열기: 영상, 음성, 그림 파일을 이 책의 대화에 보관하고 재생합니다. 파일 내용은 AI에게 보내지 않습니다.")
                    .disabled(chat.importingAssets || chat.busy)
                if chat.importingAssets { ProgressView().controlSize(.mini) }
                ChatModelMenu(chat: chat)
                Spacer(minLength: 4)
                sendControl(block)
            }
            if let block {
                Text(block.message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("pi-send-blocked")
                    .transition(.opacity)
            }
        }.padding(14)
            .animation(motion, value: block)
            .background(ReaderStyle.panel, in: RoundedRectangle(cornerRadius: ReaderTokens.composerRadius, style: .continuous))
            .modifier(ReaderSurfaceBorder(radius: ReaderTokens.composerRadius))
            .overlay { RoundedRectangle(cornerRadius: ReaderTokens.composerRadius, style: .continuous).strokeBorder(composerFocused ? ReaderStyle.accent.opacity(0.45) : .clear, lineWidth: 1).allowsHitTesting(false) }
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
            .animation(reduceMotion ? nil : ReaderMotion.ease(ReaderTokens.controlDuration), value: composerFocused)
            .padding(12)
    }

    private var scopeMenu: some View {
        let scope = self.scope
        return Menu {
            PiMenuChoice(title: "이 책 전체", selected: scope.mode == "book") { chat.scopeMode = "book" }
            PiMenuChoice(title: "현재 쪽", selected: scope.mode == "page") { chat.scopeMode = "page" }
            PiMenuChoice(title: "페이지 범위…", selected: scope.mode == "range") { choosingRange = true }
        } label: { Text(scope.composerLabel(currentPage: model.page)).monospacedDigit() }
            .menuStyle(.button).buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small).fixedSize()
            .accessibilityLabel("질문 범위").accessibilityValue(scope.composerLabel(currentPage: model.page))
            .help("Pi가 본문을 찾고 읽을 범위")
    }

    private var notesToggle: some View {
        Toggle("노트 포함", isOn: $includeNotes).toggleStyle(.checkbox).controlSize(.small).fixedSize()
            .help("이 책의 노트를 참고 자료로 함께 보냅니다.")
    }

    private var explanationMenu: some View {
        let current = PiExplanation(skill: chat.skill)
        return Menu {
            ForEach(PiExplanation.allCases) { option in
                PiMenuChoice(title: option.title, selected: option == current) { chat.skill = option.rawValue }
                if option == .auto { Divider() }
            }
        } label: { Text(current.title) }
            .menuStyle(.button).buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small).fixedSize()
            .accessibilityLabel("설명 방식").accessibilityValue(current.title)
            .help("설명 방식. 자동은 질문에 맞게 글, 표, 다이어그램을 고릅니다. Codex는 이미지도 만들 수 있습니다.")
    }

    @ViewBuilder private func sendControl(_ block: PiComposerBlock?) -> some View {
        if chat.busy && chat.operation == "chat" {
            Button { chat.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 11)).frame(width: 28, height: 28) }
                .buttonStyle(.bordered).clipShape(Circle()).accessibilityLabel("답변 중단").help("답변 중단")
        } else {
            Button { send() } label: { Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).frame(width: 28, height: 28) }
                .buttonStyle(.borderedProminent).clipShape(Circle()).accessibilityLabel("질문하기")
                .help("질문하기 (\(model.shortcuts[.sendMessage].label))")
                .keyboardShortcut(model.shortcuts[.sendMessage].value)
                .disabled(block != nil || chat.busy || chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: Actions

    private var canRetry: Bool {
        !chat.busy && editingID == nil && chat.lastQuestion != nil && AgentRuntime.ready && chat.account?.connected == true
    }
    private func send() {
        if NSApp.currentEvent?.type == .keyDown, let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return }
        guard !choosingRange, editingID == nil, model.activeBook?.id == book.id, model.flushPendingSave() else { return }
        followTail = true; composerFocused = true
        let scope = self.scope
        chat.send(context: AgentRequest.Context(id: book.id, title: book.title, page: model.page,
                  text: currentText, notes: includeNotes ? model.notebookText : "", selection: model.selection.filter { scope.contains($0.page) }.map(\.quote).joined(separator: "\n"), scope: scope))
    }
    private func suggest(_ prompt: String) { chat.draft = prompt; composerFocused = true }
    private func beginEdit(_ message: BookChatMessage) {
        guard !chat.busy else { return }
        editText = message.text; editingID = message.id
        DispatchQueue.main.async { editorFocused = true }
    }
    private func submitEdit(_ message: BookChatMessage) {
        if NSApp.currentEvent?.type == .keyDown, let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return }
        guard model.activeBook?.id == book.id else { return }
        let text = editText
        editingID = nil; followTail = true
        chat.reviseQuestion(message.id, text: text, context: context(page: message.page, scope: message.scope))
    }
    private func context(page: Int, scope: BookReadingScope? = nil) -> AgentRequest.Context {
        AgentRequest.Context(id: book.id, title: book.title, page: page, text: model.document?.page(at: page - 1)?.string ?? "",
                             notes: includeNotes ? model.notebookText : "", selection: "", scope: scope ?? BookReadingScope(mode: "page", startPage: page, endPage: page))
    }
    private func retry() {
        guard model.activeBook?.id == book.id, let question = chat.lastQuestion, !chat.busy else { return }
        followTail = true; chat.reviseQuestion(question.id, text: question.text, context: context(page: question.page, scope: question.scope))
    }
    private func openPage(_ page: Int) { guard model.activeBook?.id == book.id else { return }; model.goToPage(page) }
    private func saveToNotes(_ message: BookChatMessage) {
        guard model.activeBook?.id == book.id else { return }
        let sourceLabel = message.scope?.title ?? "PDF \(message.page)쪽"
        model.editNotebook(model.notebookText + (model.notebookText.isEmpty ? "" : "\n\n") + "[Pi 답변 / \(sourceLabel)]\n" + message.text)
        model.sidebarVisible = true; model.panelTab = "notes"
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    private func openConnectionSettings() { model.settingsTab = "ai"; model.showSettings = true }
    private func chooseAssets() {
        let target = book.id, page = model.page
        let panel = NSOpenPanel(); panel.title = "이 책에서 볼 자료 선택"
        panel.message = "자료는 이 Mac에 보관됩니다. 파일 내용은 AI에게 보내지 않습니다."
        panel.allowedContentTypes = ChatAssetStore.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, model.activeBook?.id == target else { return }
            chat.addAttachments(panel.urls, bookID: target, page: page)
        }
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
            Text("Pi 학습 지침").font(.headline)
            Text("공통 지침은 영어로 작성하며 답변은 질문한 언어를 따릅니다. 자동 설명 방식이 글, 표와 시각 자료를 고릅니다. Codex는 이미지도 만들 수 있습니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView { Text(text).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(20).frame(width: 440, height: 420)
    }
}

struct ChatMarkdownText: View {
    let text: String
    var sourcePages: Set<Int> = []
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
        (try? AttributedString(markdown: ChatCitations.linkedMarkdown(ChatContent.markdownProse(text), pages: sourcePages), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
