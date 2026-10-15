import SwiftUI
import BookshelfCore

struct NotesPanel: View {
    @ObservedObject var model: AppModel
    let book: Book
    var body: some View {
        VStack(spacing: 0) {
            Picker("메모 보기", selection: $model.panelTab) {
                Text("내 메모").tag("notes")
                Text("발췌 \(model.highlights.count)").tag("quotes")
                Text("검색").tag("search")
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 16).frame(height: 45)
            Divider()
            switch model.panelTab {
            case "quotes": quotes
            case "search": search
            default: notebook
            }
            Divider()
            HStack {
                Button { model.copyContext() } label: { Label("AI로 이어가기", systemImage: "arrow.up.right.square") }.buttonStyle(.plain).font(.system(size: 11)).accessibilityLabel("AI로 이어가기")
                Spacer()
                Button { model.exportNotes() } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(.plain).help("Markdown으로 내보내기").accessibilityLabel("메모 내보내기")
                Button { model.showSettings = true } label: { Image(systemName: "link") }.buttonStyle(.plain).help("CLI/MCP 연결 안내").accessibilityLabel("CLI MCP 연결 안내")
            }.foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 43)
        }.background(Color(nsColor: .controlBackgroundColor))
    }
    private var notebook: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text("이 책에서 남긴 생각").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(book.title).font(.system(size: 19, weight: .medium)).lineLimit(2)
                HStack(spacing: 5) { Image(systemName: model.hasUnsavedChanges ? "circle.dotted" : "checkmark.circle"); Text(model.saveStatus) }.font(.system(size: 10)).foregroundStyle(model.saveStatus == "저장하지 못함" ? .orange : .secondary)
            }.padding(22)
            Divider().padding(.horizontal, 22)
            ZStack(alignment: .topLeading) {
                if model.notebookText.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("내 말로 적어보세요.").font(.system(size: 14))
                        Text("이해한 내용, 떠오른 질문,\n내 일상에 적용할 점을 남길 수 있어요.").font(.system(size: 12)).lineSpacing(6)
                    }.foregroundStyle(.tertiary).padding(.horizontal, 26).padding(.top, 26).allowsHitTesting(false)
                }
                TextEditor(text: Binding(get: { model.notebookText }, set: { model.editNotebook($0) }))
                    .font(.system(size: 14)).lineSpacing(7).scrollContentBackground(.hidden).padding(18)
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
                VStack(spacing: 13) { Image(systemName: "highlighter").font(.system(size: 28, weight: .light)); Text("기억하고 싶은 문장").font(.system(size: 17, weight: .medium)); Text("원문에서 문장을 선택하고\n발췌 메모에 담아보세요.").font(.system(size: 12)).multilineTextAlignment(.center).lineSpacing(6) }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 90)
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
