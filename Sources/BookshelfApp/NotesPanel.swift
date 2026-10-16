import SwiftUI
import BookshelfCore

struct NotesPanel: View {
    @ObservedObject var model: AppModel
    let book: Book
    private var hasAgent: Bool { AgentRuntime.bridgeURL != nil }
    private var choices: [(String, String)] {
        (hasAgent ? [("대화", "chat")] : []) + [("메모", "notes"), (model.highlights.isEmpty ? "발췌" : "발췌 \(model.highlights.count)", "quotes"), ("검색", "search")]
    }

    var body: some View {
        VStack(spacing: 0) {
            ReaderPicker(choices: choices,
                         selection: $model.panelTab, label: "책 패널")
                .frame(height: 28)
                .padding(.horizontal, 16).frame(height: ReaderStyle.toolbarHeight + 8)
            Group {
                switch model.panelTab {
                case "chat": BookChatView(model: model, chat: model.chat, book: book)
                case "quotes": quotes
                case "search": search
                default: notebook
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            ReaderHairline().padding(.horizontal, 16)
            HStack(spacing: 4) {
                Button { if hasAgent { model.panelTab = "chat" } else { model.copyContext() } } label: {
                    Label(hasAgent ? "이 책에 질문" : "AI로 이어가기", systemImage: hasAgent ? "bubble.left.and.bubble.right" : "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                }.buttonStyle(.plain).accessibilityLabel(hasAgent ? "이 책에 질문" : "AI로 이어가기")
                    .help(hasAgent ? "현재 페이지를 바탕으로 앱 안에서 질문할 수 있습니다." : "현재 책과 메모를 외부 AI 클라이언트에 전달할 문맥으로 복사합니다.")
                Spacer()
                ReaderIconButton(symbol: "square.and.arrow.up", label: "메모 내보내기") { model.exportNotes() }
                ReaderIconButton(symbol: "link", label: "CLI MCP 연결 안내") { model.showSettings = true }
            }.padding(.leading, 20).padding(.trailing, 12).frame(height: ReaderStyle.footerHeight + 8)
        }.background(ReaderMaterial(material: .underWindowBackground))
    }

    private var notebook: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label("이 책의 노트", systemImage: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                    NoteCountBadge(count: model.noteCount(book))
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        Image(systemName: model.hasUnsavedChanges ? "circle.dotted" : "checkmark")
                        Text(model.saveStatus)
                    }.font(.system(size: 11)).foregroundStyle(model.saveStatus == "저장하지 못함" ? .orange : .secondary)
                }
                Text(book.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).lineSpacing(4)
            }.padding(18)
            ReaderHairline().padding(.horizontal, 18)
            ZStack(alignment: .topLeading) {
                if model.notebookText.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("내 말로 적어보세요.").font(.system(size: 14))
                        Text("이해한 내용과 아직 남은 질문을\n여기에 기록할 수 있습니다.")
                            .font(.system(size: 12)).lineSpacing(6)
                    }.foregroundStyle(.secondary).padding(.horizontal, 22).padding(.top, 20)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Binding(get: { model.notebookText }, set: { model.editNotebook($0) }))
                    .font(.system(size: ReaderTokens.bodyFont)).lineSpacing(8)
                    .scrollContentBackground(.hidden).padding(.horizontal, 14).padding(.vertical, 14)
                    .accessibilityLabel("책 메모").accessibilityIdentifier("book-note-editor")
            }.frame(maxHeight: .infinity)
            if model.saveStatus == "저장하지 못함" {
                VStack(alignment: .leading, spacing: 8) {
                    Button("다시 저장") { model.flushPendingSave() }
                    Button("내 내용 복사 후 다시 불러오기") { model.loadNotebookAgain() }
                }.controlSize(.small).padding(14)
            }
            if !model.bookmarks.isEmpty {
                ReaderHairline().padding(.horizontal, 18)
                HStack(spacing: 8) {
                    Image(systemName: "bookmark").foregroundStyle(.secondary).accessibilityLabel("책갈피")
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(model.bookmarks, id: \.self) { n in
                                Button("\(n)쪽") { model.goToPage(n) }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }.scrollIndicators(.hidden)
                }.font(.system(size: 11)).padding(14)
            }
        }
        .background(ReaderStyle.panel, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusPanel, style: .continuous))
        .modifier(ReaderSurfaceBorder(radius: ReaderTokens.radiusPanel))
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    private var quotes: some View {
        ScrollView {
            if model.highlights.isEmpty {
                panelPlaceholder(symbol: "text.quote", title: "다시 읽고 싶은 문장",
                                 message: "원문에서 문장을 선택하면 발췌와 생각을 함께 남길 수 있습니다.")
                Text("⌘ ⇧ H  선택 문장 담기").font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
            }
            LazyVStack(spacing: 12) {
                ForEach(model.highlights) { highlight in HighlightCard(highlight: highlight, model: model) }
            }.padding(12)
        }
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ReaderSearchField(prompt: "이 책의 본문에서 찾기", label: "본문 검색어", text: $model.searchQuery) { model.searchBook() }
                ReaderIconButton(symbol: "arrow.turn.down.left", label: "본문 검색") { model.searchBook() }
                    .disabled(model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            VStack(alignment: .leading, spacing: 7) {
                Toggle("띄어쓰기 무시", isOn: $model.ignoreSearchWhitespace)
                    .toggleStyle(.checkbox).font(.system(size: 12))
                    .help("OCR의 글자 사이 공백과 줄바꿈을 무시하고 찾습니다. 원문은 바뀌지 않습니다.")
                    .onChange(of: model.ignoreSearchWhitespace) { _, _ in
                        if !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.searchBook() }
                    }
                Text(model.ignoreSearchWhitespace ? "‘설 득’도 ‘설득’으로 찾습니다." : "입력한 띄어쓰기가 같은 문장을 찾습니다.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 4)
            ReaderHairline()
            if model.isSearching {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("본문을 찾고 있습니다.") }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else if !model.searchQuery.isEmpty {
                Text("\(model.searchResults.count)개 페이지").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ScrollView {
                if model.searchQuery.isEmpty {
                    panelPlaceholder(symbol: "doc.text.magnifyingglass", title: "책 안에서 찾기",
                                     message: "기억나는 단어나 문장을 입력하세요. 결과를 선택하면 해당 페이지로 이동합니다.")
                }
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.searchResults) { hit in
                        Button { model.goToPage(hit.page) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text("PDF \(hit.page)쪽").monospacedDigit()
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                Text(hit.text).font(.system(size: 13)).lineSpacing(5).lineLimit(7).foregroundStyle(.primary)
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(ReaderStyle.panel, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusLarge, style: .continuous))
                                .modifier(ReaderSurfaceBorder())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
            .onChange(of: model.searchQuery) { _, query in
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.searchBook() }
            }
    }

    private func panelPlaceholder(symbol: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
                .frame(width: 50, height: 50).background(ReaderStyle.muted, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusLarge))
            Text(title).font(.system(size: 16, weight: .medium))
            Text(message).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(6)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(24).padding(.top, 12)
    }
}

struct HighlightCard: View {
    let highlight: Highlight
    @ObservedObject var model: AppModel
    @State private var confirmingDelete = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { model.goToPage(highlight.page) } label: {
                    Label("PDF \(highlight.page)쪽", systemImage: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
                Spacer()
                ReaderIconButton(symbol: "trash", label: "발췌 메모 삭제") { confirmingDelete = true }
            }
            Text(highlight.quote).font(.system(size: 13)).lineSpacing(6).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            ReaderHairline()
            TextField("이 문장에 대한 내 생각", text: Binding(get: { model.highlights.first(where: { $0.id == highlight.id })?.comment ?? highlight.comment }, set: { model.updateHighlight(highlight, comment: $0) }), axis: .vertical)
                .font(.system(size: 13)).textFieldStyle(.plain).lineLimit(2...8).accessibilityLabel("발췌에 대한 내 생각")
        }.padding(16).background(ReaderStyle.panel, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusPanel, style: .continuous))
            .modifier(ReaderSurfaceBorder(radius: ReaderTokens.radiusPanel))
            .confirmationDialog("이 발췌 메모를 삭제할까요?", isPresented: $confirmingDelete) {
                Button("삭제", role: .destructive) { model.deleteHighlight(highlight) }
            }
    }
}
