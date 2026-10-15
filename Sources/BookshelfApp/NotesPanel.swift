import SwiftUI
import BookshelfCore

struct NotesPanel: View {
    @ObservedObject var model: AppModel
    let book: Book
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                tab("내 메모", id: "notes")
                tab("발췌", id: "quotes", count: model.highlights.count)
                tab("검색", id: "search")
                Spacer(minLength: 0)
            }.padding(.horizontal, 24).frame(height: ReaderStyle.toolbarHeight)
            Divider()
            switch model.panelTab {
            case "quotes": quotes
            case "search": search
            default: notebook
            }
            Divider()
            HStack {
                Button { model.copyContext() } label: { Label("AI로 이어가기", systemImage: "arrow.up.right.square") }.buttonStyle(.borderless).font(.system(size: 12, weight: .medium)).accessibilityLabel("AI로 이어가기")
                Spacer()
                ReaderIconButton(symbol: "square.and.arrow.up", label: "메모 내보내기") { model.exportNotes() }
                ReaderIconButton(symbol: "link", label: "CLI MCP 연결 안내") { model.showSettings = true }
            }.foregroundStyle(.secondary).padding(.horizontal, 22).frame(height: ReaderStyle.footerHeight + 1)
        }.background(ReaderStyle.panel)
    }
    private func tab(_ title: String, id: String, count: Int? = nil) -> some View {
        Button { model.panelTab = id } label: {
            HStack(spacing: 5) {
                Text(title)
                if let count, count > 0 { Text("\(count)").font(.system(size: 10)).monospacedDigit() }
            }.font(.system(size: 13, weight: model.panelTab == id ? .semibold : .regular))
                .foregroundStyle(model.panelTab == id ? .primary : .secondary)
                .frame(height: ReaderStyle.toolbarHeight)
                .overlay(alignment: .bottom) {
                    if model.panelTab == id { Rectangle().fill(ReaderStyle.accent).frame(height: 2) }
                }.contentShape(Rectangle())
        }.buttonStyle(.borderless).accessibilityLabel(title)
            .accessibilityAddTraits(model.panelTab == id ? .isSelected : [])
    }
    private var notebook: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("이 책의 노트").font(.system(size: 20, weight: .medium))
                    Spacer()
                    HStack(spacing: 4) { Image(systemName: model.hasUnsavedChanges ? "circle.dotted" : "checkmark"); Text(model.saveStatus) }
                        .font(.system(size: 10)).foregroundStyle(model.saveStatus == "저장하지 못함" ? .orange : .secondary)
                }
                Text(book.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).lineSpacing(4)
            }.padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 22)
            Divider().padding(.horizontal, 24)
            ZStack(alignment: .topLeading) {
                if model.notebookText.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("내 말로 적어보세요.").font(.system(size: 14))
                        Text("이해한 내용과 아직 남은 질문을\n여기에 기록할 수 있습니다.").font(.system(size: 12)).lineSpacing(6)
                    }.foregroundStyle(.secondary).padding(.horizontal, 29).padding(.top, 26).allowsHitTesting(false)
                }
                TextEditor(text: Binding(get: { model.notebookText }, set: { model.editNotebook($0) }))
                    .font(.system(size: 14)).lineSpacing(8).scrollContentBackground(.hidden).padding(.horizontal, 21).padding(.vertical, 20)
                    .accessibilityLabel("책 메모").accessibilityIdentifier("book-note-editor")
            }.frame(maxHeight: .infinity)
            if model.saveStatus == "저장하지 못함" {
                HStack { Button("다시 저장") { model.flushPendingSave() }; Button("내 내용 복사 후 다시 불러오기") { model.loadNotebookAgain() } }.controlSize(.small).padding(14)
            }
            if !model.bookmarks.isEmpty {
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bookmark").foregroundStyle(.secondary)
                    ScrollView(.horizontal) { HStack { ForEach(model.bookmarks, id: \.self) { n in Button("\(n)쪽") { model.goToPage(n) }.buttonStyle(.bordered).controlSize(.small) } } }
                }.font(.system(size: 11)).padding(16)
            }
        }
    }
    private var quotes: some View {
        ScrollView {
            if model.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "text.quote").font(.system(size: 30, weight: .light)).foregroundStyle(ReaderStyle.accent)
                    Text("다시 읽고 싶은 문장").font(.system(size: 20, weight: .medium))
                    Text("원문에서 문장을 선택하면\n이곳에 발췌와 생각을 함께 남길 수 있습니다.").font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(7)
                    Text("⌘ ⇧ H  선택 문장 담기").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 6)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(26).padding(.top, 24)
            }
            LazyVStack(spacing: 14) {
                ForEach(model.highlights) { highlight in HighlightCard(highlight: highlight, model: model) }
            }.padding(18)
        }
    }
    private var search: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { TextField("이 책의 본문에서 찾기", text: $model.searchQuery).textFieldStyle(.roundedBorder).onSubmit { model.searchBook() }.accessibilityLabel("본문 검색어"); Button { model.searchBook() } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("본문 검색") }.padding(.top, 20)
            if model.isSearching { ProgressView("본문을 찾고 있습니다.").controlSize(.small) }
            else if !model.searchQuery.isEmpty { Text("\(model.searchResults.count)개 페이지").font(.system(size: 11)).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.searchResults) { hit in
                        Button { model.goToPage(hit.page) } label: {
                            VStack(alignment: .leading, spacing: 8) { Text("PDF \(hit.page)쪽").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentColor); Text(hit.text).font(.system(size: 12)).lineSpacing(5).lineLimit(7).foregroundStyle(.primary) }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(.horizontal, 18)
    }
}

struct HighlightCard: View {
    let highlight: Highlight
    @ObservedObject var model: AppModel
    @State private var confirmingDelete = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { model.goToPage(highlight.page) } label: { Label("PDF \(highlight.page)쪽", systemImage: "arrow.up.right") }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Color.accentColor)
                Spacer()
                Button { confirmingDelete = true } label: { Image(systemName: "trash") }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.tertiary).accessibilityLabel("발췌 메모 삭제")
            }
            Text(highlight.quote).font(.system(size: 12)).lineSpacing(6).textSelection(.enabled)
            Divider()
            TextField("이 문장에 대한 내 생각", text: Binding(get: { model.highlights.first(where: { $0.id == highlight.id })?.comment ?? highlight.comment }, set: { model.updateHighlight(highlight, comment: $0) }), axis: .vertical).font(.system(size: 12)).textFieldStyle(.plain).lineLimit(2...8).accessibilityLabel("발췌에 대한 내 생각")
        }.padding(15).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06)))
            .confirmationDialog("이 발췌 메모를 삭제할까요?", isPresented: $confirmingDelete) { Button("삭제", role: .destructive) { model.deleteHighlight(highlight) } }
    }
}
