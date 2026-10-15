import SwiftUI
import PDFKit
import BookshelfCore

struct ReaderWindow: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            if let message = model.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    Text(message).font(.system(size: 12)).textSelection(.enabled)
                    Spacer()
                    Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("오류 닫기")
                }.padding(12).background(Color.orange.opacity(0.08))
                Divider()
            }
            if model.ocrRunning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.ocrMessage).font(.system(size: 12))
                    Spacer()
                    Button("취소") { model.cancelOCR() }.controlSize(.small)
                }.padding(.horizontal, 18).padding(.vertical, 10).background(Color.accentColor.opacity(0.06))
                Divider()
            }
            HSplitView {
                if model.sidebarVisible { BookSidebar(model: model).frame(minWidth: 215, idealWidth: 245, maxWidth: 320) }
                if let book = model.activeBook {
                    ReaderSurface(model: model, book: book).frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)
                    if model.notesVisible { NotesPanel(model: model, book: book).frame(minWidth: 285, idealWidth: 350, maxWidth: 420) }
                } else { EmptyLibraryView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            Divider()
            HStack(spacing: 12) {
                Label(model.activeBook?.displayCategory ?? "내 서재", systemImage: "book.closed").lineLimit(1)
                Spacer()
                if let information = model.information { Text(information).lineLimit(1); Button { model.information = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                else { Text("책과 메모는 이 Mac에 저장됩니다.") }
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 28)
        }
        .frame(minWidth: 1000, minHeight: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { withAnimation(.easeInOut(duration: 0.15)) { model.sidebarVisible.toggle() } } label: { Image(systemName: "sidebar.left") }.help("책장 표시").accessibilityLabel("책장 표시")
                Menu { Button("PDF 추가…") { model.chooseFiles() }; Button("폴더 추가…") { model.chooseFiles(folder: true) } } label: { Image(systemName: "plus") }.help("서재에 추가")
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 9) { Image(systemName: "book.pages").foregroundStyle(.secondary); Text(model.activeBook?.title ?? "서재").font(.system(size: 13, weight: .semibold)).lineLimit(1) }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.help("OCR와 AI 연결 설정").accessibilityLabel("설정")
                Button { withAnimation(.easeInOut(duration: 0.15)) { model.notesVisible.toggle() } } label: { Image(systemName: "sidebar.right") }.help("책별 메모 표시").accessibilityLabel("메모 패널 표시")
            }
        }
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model).padding(10) }
        .onDisappear { model.flushPendingSave(); model.savePositionNow() }
    }
}

struct ReaderSurface: View {
    @ObservedObject var model: AppModel
    let book: Book
    @State private var pageEntry = "1"
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("보기 방식", selection: $model.textMode) { Text("원문").tag(false); Text("텍스트").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 130)
                Spacer()
                if model.isInspecting { ProgressView().controlSize(.mini); Text("텍스트 확인 중").font(.system(size: 10)).foregroundStyle(.secondary) }
                else { Text(book.textStatus).font(.system(size: 10)).foregroundStyle(.secondary) }
                Button { model.startOCR() } label: { Label("텍스트 인식", systemImage: "text.viewfinder") }.controlSize(.small).disabled(model.ocrRunning || !book.isAvailable || (book.pageCount > 0 && book.textPages == book.pageCount)).accessibilityLabel("텍스트 인식")
                Divider().frame(height: 16)
                Button { model.pdfView?.zoomOut(nil) } label: { Image(systemName: "minus.magnifyingglass") }.buttonStyle(.plain).accessibilityLabel("축소")
                Button { model.pdfView?.autoScales = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.buttonStyle(.plain).accessibilityLabel("페이지에 맞추기")
                Button { model.pdfView?.zoomIn(nil) } label: { Image(systemName: "plus.magnifyingglass") }.buttonStyle(.plain).accessibilityLabel("확대")
            }.padding(.horizontal, 17).frame(height: 45)
            Divider()
            ZStack(alignment: .bottom) {
                if model.isOpening { ProgressView("책을 펼치고 있습니다.").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if model.document != nil {
                    if model.textMode {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                Text("\(book.title) / PDF \(model.page)쪽").font(.system(size: 11)).foregroundStyle(.secondary)
                                Text(model.document?.page(at: model.page - 1)?.string ?? "이 페이지에는 텍스트가 없습니다.")
                                    .font(.system(size: 17)).lineSpacing(8).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(45).frame(maxWidth: 800).background(Color(nsColor: .textBackgroundColor)).padding(24).frame(maxWidth: .infinity)
                        }
                    } else { PDFReaderView(model: model) }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: book.isAvailable ? "doc.questionmark" : "icloud.and.arrow.down").font(.system(size: 35)).foregroundStyle(.secondary)
                        Text(book.title).font(.title3)
                        Text(book.isAvailable ? "파일을 다시 열어보세요." : "이 책은 iCloud에서 다운로드해야 합니다.").foregroundStyle(.secondary)
                        HStack { if !book.isAvailable { Button("다운로드 요청") { model.downloadBook() } }; Button("다시 열기") { model.selectBook(book) }; Button("Finder에서 보기") { model.revealSource() } }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if !model.selection.isEmpty && !model.textMode {
                    HStack(spacing: 15) {
                        Image(systemName: "text.quote")
                        Text("\(model.selection.reduce(0) { $0 + $1.quote.count })자 선택").font(.system(size: 11))
                        Divider().frame(height: 17)
                        Button("발췌 메모에 담기") { model.saveSelection() }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).accessibilityLabel("발췌 메모에 담기")
                        Button { model.selection = []; model.pdfView?.clearSelection() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("선택 닫기")
                    }.padding(.horizontal, 17).padding(.vertical, 12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary)).shadow(color: .black.opacity(0.1), radius: 10, y: 4).padding(.bottom, 22)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Button { model.toggleBookmark() } label: { Label(model.bookmarks.contains(model.page) ? "책갈피 해제" : "책갈피", systemImage: model.bookmarks.contains(model.page) ? "bookmark.fill" : "bookmark") }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(model.bookmarks.contains(model.page) ? Color.accentColor : .secondary).accessibilityLabel(model.bookmarks.contains(model.page) ? "책갈피 해제" : "책갈피 추가")
                Spacer()
                Button { model.goToPage(model.page - 1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).disabled(model.page <= 1).accessibilityLabel("이전 페이지")
                TextField("페이지", text: $pageEntry).textFieldStyle(.roundedBorder).frame(width: 45).multilineTextAlignment(.center).onSubmit { if let n = Int(pageEntry) { model.goToPage(n) }; pageEntry = String(model.page) }.accessibilityLabel("페이지 번호")
                Text("/ \(model.document?.pageCount ?? book.pageCount)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                Button { model.goToPage(model.page + 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).disabled(model.page >= (model.document?.pageCount ?? 1)).accessibilityLabel("다음 페이지")
                Spacer()
                Text("PDF 원문").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).frame(height: 43)
        }.onChange(of: model.page) { _, n in pageEntry = String(n) }.onAppear { pageEntry = String(model.page) }
    }
}

struct EmptyLibraryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "book.pages").font(.system(size: 55, weight: .ultraLight)).foregroundStyle(.secondary)
            Text("책에서 시작되는 생각").font(.system(size: 28, weight: .medium))
            Text("PDF를 읽고, 문장을 남기고, 내 말로 정리해보세요.").font(.system(size: 13)).foregroundStyle(.secondary)
            HStack(spacing: 12) { Button("PDF 추가…") { model.chooseFiles() }.buttonStyle(.borderedProminent); Button("폴더 연결…") { model.chooseFiles(folder: true) } }.padding(.top, 10)
            if !model.books.isEmpty { Text("왼쪽 책장에서 읽을 책을 선택할 수 있습니다.").font(.system(size: 12)).foregroundStyle(.secondary) }
            Text("원본은 제자리에. 메모는 이 Mac에.").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 35)
        }
    }
}
