import SwiftUI
import BookshelfCore

struct BookChatView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var chat: BookChatModel
    let book: Book
    @AppStorage("agent.includeNotes") private var includeNotes = true
    @State private var showingProfile = false
    private var currentText: String { model.document?.page(at: model.page - 1)?.string ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("이 책과 대화").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Picker("대화 실행기", selection: Binding(get: { chat.backend }, set: { chat.chooseBackend($0) })) {
                        ForEach(ChatBackend.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 104).disabled(chat.busy)
                }
                HStack(spacing: 6) {
                    Image(systemName: chat.account?.connected == true ? "checkmark.circle" : "person.crop.circle.badge.questionmark")
                    Text(chat.account?.label ?? "연결 확인 전").lineLimit(2)
                    Spacer(minLength: 4)
                    Button(chat.account?.connected == true ? "다시 연결" : "로그인") { chat.login() }
                        .controlSize(.small).disabled(chat.busy || !AgentRuntime.ready).accessibilityLabel("AI 공식 로그인")
                        .contextMenu { Button("연결 상태 확인") { chat.checkConnection() } }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
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
                                    Text(message.role == "user" ? "나" : (message.harness == "pi" ? "Pi + " : "") + (ChatBackend(rawValue: message.backend)?.title ?? "도우미"))
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                    Spacer()
                                    if message.role == "assistant" && message.state != "complete" {
                                        Text(chat.busy && message.id == chat.messages.last?.id ? "답변 중" : message.state == "failed" ? "완료하지 못함" : "중단됨")
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                }
                                if message.text.isEmpty && chat.busy { ProgressView().controlSize(.small) }
                                else { ChatResponseText(text: message.text).textSelection(.enabled) }
                                if message.role == "assistant" && !message.text.isEmpty {
                                    HStack(spacing: 10) {
                                        Button("질문한 \(message.page)쪽") { model.goToPage(message.page) }
                                            .help("질문할 때 전달한 PDF 페이지로 이동합니다.")
                                        Spacer()
                                        if message.state == "complete" {
                                            Button("메모에 담기") {
                                                guard model.activeBook?.id == book.id else { return }
                                                model.editNotebook(model.notebookText + (model.notebookText.isEmpty ? "" : "\n\n") + "[AI 대화 / PDF \(message.page)쪽]\n" + message.text)
                                            }
                                        }
                                    }.font(.system(size: 11)).buttonStyle(.borderless)
                                }
                            }.padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.role == "user" ? ReaderStyle.muted : ReaderStyle.panel,
                                            in: RoundedRectangle(cornerRadius: ReaderTokens.radiusLarge))
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("conversation-end")
                    }.padding(14)
                }.onChange(of: chat.messages.last?.text) { _, _ in proxy.scrollTo("conversation-end", anchor: .bottom) }
                    .onChange(of: chat.messages.count) { _, _ in proxy.scrollTo("conversation-end", anchor: .bottom) }
                    .onAppear { proxy.scrollTo("conversation-end", anchor: .bottom) }
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
            ReaderHairline()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("PDF \(model.page)쪽").monospacedDigit()
                    Spacer()
                    Toggle("책 노트 포함", isOn: $includeNotes).toggleStyle(.checkbox)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("설명 방식", selection: $chat.skill) {
                    Text("쉽게 설명").tag("explain"); Text("비교표").tag("compare"); Text("흐름으로 설명").tag("visualize")
                }.labelsHidden().controlSize(.small).disabled(chat.busy)
                TextEditor(text: $chat.draft).font(.system(size: 13)).scrollContentBackground(.hidden)
                    .frame(minHeight: 56, maxHeight: 100).padding(6)
                    .background(ReaderStyle.panel, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusMedium))
                    .modifier(ReaderSurfaceBorder(radius: ReaderTokens.radiusMedium))
                    .accessibilityLabel("책에 질문").accessibilityIdentifier("book-chat-composer")
                HStack {
                    Toggle("Pi", isOn: Binding(get: { chat.usePi }, set: { chat.setPi($0) })).toggleStyle(.checkbox)
                        .font(.system(size: 11)).disabled(chat.busy)
                        .help("Pi 대화 계층을 켜거나 공식 실행기에 직접 연결해 비교합니다. 같은 학습 지침을 사용합니다.")
                    Button { showingProfile = true } label: { Image(systemName: "info.circle") }.buttonStyle(.plain)
                        .accessibilityLabel("학습 전용 지침 보기")
                        .popover(isPresented: $showingProfile) { LearningProfileView() }
                    Spacer()
                    if chat.busy { Button("중단") { chat.stop() }.controlSize(.small) }
                    else {
                        Button("질문하기") { send() }.buttonStyle(.borderedProminent).controlSize(.small)
                            .keyboardShortcut(.return, modifiers: [.command])
                            .disabled(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.document == nil || !AgentRuntime.ready || chat.account?.connected != true)
                    }
                }
                Text("현재 페이지와 최근 대화를 선택한 실행기에 전달합니다.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(14)
        }.background(ReaderStyle.canvas)
            .task(id: book.id) {
                guard !Task.isCancelled, model.activeBook?.id == book.id else { return }
                if chat.selectBook(book.id), chat.account == nil, AgentRuntime.ready { chat.checkConnection() }
            }
    }
    private func send() {
        guard model.activeBook?.id == book.id, model.flushPendingSave() else { return }
        chat.send(context: AgentRequest.Context(id: book.id, title: book.title, page: model.page,
                  text: currentText, notes: includeNotes ? model.notebookText : "", selection: model.selection.map(\.quote).joined(separator: "\n")))
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
            Text("공통 지침은 영어로 작성하며 답변은 사용자의 언어를 따릅니다. 설명, 비교표, 흐름 설명만 제공합니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView { Text(text).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(20).frame(width: 440, height: 420)
    }
}

private struct ChatResponseText: View {
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
                } else { Text(inline(block.text)).font(.system(size: 13)).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
    }
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
