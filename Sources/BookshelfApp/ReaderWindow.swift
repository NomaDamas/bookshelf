import SwiftUI
import PDFKit
import BookshelfCore

struct ReaderWindow: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                if model.sidebarVisible { BookSidebar(model: model).frame(minWidth: 220, idealWidth: ReaderTokens.sidebarWidth, maxWidth: 340) }
                if model.readingShelfVisible {
                    ReadingShelfView(model: model).frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)
                } else if let book = model.activeBook {
                    ReaderSurface(model: model, book: book)
                        .padding(8).frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    if model.notesVisible { NotesPanel(model: model, book: book).frame(minWidth: 300, idealWidth: 340, maxWidth: 440) }
                } else { EmptyLibraryView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            if let information = model.information {
                Divider()
                HStack(spacing: 12) {
                    Text(information).lineLimit(2)
                    Spacer()
                    Button { model.information = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).accessibilityLabel("알림 닫기")
                }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 8)
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
        .background(ReaderMaterial(material: .underWindowBackground))
        .tint(ReaderStyle.accent)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { model.sidebarVisible.toggle() } } label: { Image(systemName: "sidebar.left") }.help("책장 표시 (⌘0)").accessibilityLabel("책장 표시")
                Button { model.showReadingShelf() } label: { Image(systemName: "books.vertical") }
                    .help("읽는 중인 책 모아보기 (⌘⇧L)").accessibilityLabel("읽는 중인 책 모아보기")
                Menu { Button("PDF 추가…") { model.chooseFiles() }; Button("폴더 추가…") { model.chooseFiles(folder: true) } } label: { Image(systemName: "plus") }.help("서재에 추가")
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 9) { Image(systemName: model.readingShelfVisible ? "books.vertical" : "book.pages").foregroundStyle(.secondary); Text(model.readingShelfVisible ? "읽는 중" : model.activeBook?.title ?? "서재").font(.system(size: 13, weight: .semibold)).lineLimit(1) }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.help("OCR와 AI 연결 설정").accessibilityLabel("설정")
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { model.toggleNotesPanel() } } label: { Image(systemName: "sidebar.right") }.help("책별 메모 표시 (⌘⇧M)").accessibilityLabel("메모 패널 표시")
            }
        }
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
        .sheet(item: $model.ocrReview) { review in OCRReviewView(model: model, review: review) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.reloadLibrary() }
        .onDisappear { model.flushPendingSave(); model.savePositionNow() }
    }
}

struct ReaderSurface: View {
    @ObservedObject var model: AppModel
    let book: Book
    @State private var pageEntry = "1"
    @State private var showKeyboardHelp = false
    @FocusState private var textReaderFocused: Bool
    @State private var textScrollTarget = TextScrollTarget()
    private var pageCount: Int { model.document?.pageCount ?? book.pageCount }
    private var progress: Double { pageCount > 0 ? min(Double(model.page) / Double(pageCount), 1) : 0 }

    var body: some View {
        VStack(spacing: 0) {
            currentBookHeading
            ReaderHairline()
            readingTools
            ReaderHairline()
            ZStack(alignment: .bottom) {
                if model.isOpening {
                    ProgressView("책을 펼치고 있습니다.").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.document != nil {
                    if model.textMode { readableText } else { PDFReaderView(model: model) }
                } else { unavailableBook }
                if !model.selection.isEmpty && !model.textMode { selectionActions }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            pageControls
        }.background(ReaderStyle.panel)
        .clipShape(RoundedRectangle(cornerRadius: ReaderTokens.radiusPanel, style: .continuous))
        .modifier(ReaderSurfaceBorder(radius: ReaderTokens.radiusPanel))
        .onChange(of: model.page) { _, number in pageEntry = String(number) }
        .onAppear { pageEntry = String(model.page) }
    }

    private var currentBookHeading: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("읽는 중").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Text(book.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    .accessibilityIdentifier("current-book-title").help(book.title)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { model.revealCurrentBook() } label: {
                Label("책장에서 보기", systemImage: "books.vertical")
                    .font(.system(size: 11)).foregroundStyle(.primary)
                    .padding(.horizontal, 10).frame(height: ReaderTokens.controlSize)
                    .background(ReaderStyle.muted, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusMedium))
            }.buttonStyle(.plain).accessibilityLabel("책장에서 현재 책 보기")
        }.padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var readingTools: some View {
        HStack(spacing: 12) {
            ReaderPicker(choices: [("원문", false), ("텍스트", true)], selection: $model.textMode, label: "보기 방식")
                .frame(width: 128, height: 28)
            Spacer(minLength: 4)
            if !model.textMode {
                Menu {
                    Picker("페이지 표시", selection: $model.continuousReading) {
                        Text("한 쪽씩 보기").tag(false)
                        Text("연속 스크롤").tag(true)
                    }.pickerStyle(.inline)
                } label: {
                    Label(model.continuousReading ? "연속" : "한 쪽씩", systemImage: model.continuousReading ? "rectangle.stack" : "rectangle.portrait")
                        .font(.system(size: 12))
                }.menuStyle(.borderlessButton).fixedSize().help("페이지 표시 방식")
                Divider().frame(height: 18)
                HStack(spacing: 2) {
                    ReaderIconButton(symbol: "minus.magnifyingglass", label: "축소") { model.pdfView?.zoomOut(nil) }
                    ReaderIconButton(symbol: "arrow.up.left.and.arrow.down.right", label: "페이지에 맞추기") { model.pdfView?.autoScales = true }
                    ReaderIconButton(symbol: "plus.magnifyingglass", label: "확대") { model.pdfView?.zoomIn(nil) }
                }
            }
            Menu {
                Button(model.isInReadingShelf(book) ? "읽는 중 목록에서 제외" : "읽는 중 목록에 추가", systemImage: "books.vertical") {
                    model.setReadingMembership(book, included: !model.isInReadingShelf(book))
                }
                Divider()
                Text(model.isInspecting ? "텍스트 확인 중" : book.textStatus)
                Button("텍스트 인식…", systemImage: "text.viewfinder") { model.startOCR() }
                    .disabled(model.ocrRunning || !book.isAvailable || (book.pageCount > 0 && book.textPages == book.pageCount))
                Button("기존 OCR 개선…", systemImage: "text.badge.checkmark") { model.startOCR(mode: .replaceText) }
                    .disabled(model.ocrRunning || !book.isAvailable)
                Button("생성한 OCR 사본 검토…", systemImage: "doc.text.magnifyingglass") { model.reviewLatestOCR() }.disabled(model.ocrRunning)
                Button("원본 PDF 사용", systemImage: "arrow.uturn.backward") { model.useOriginalPDF() }.disabled(model.ocrRunning || book.ocrPath == nil)
                Divider()
                Button("Finder에서 보기", systemImage: "folder") { model.revealSource() }
                Button("키보드 조작 안내", systemImage: "keyboard") { showKeyboardHelp = true }
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 16)) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("책 옵션")
        }.padding(.horizontal, 18).frame(height: ReaderStyle.toolbarHeight)
    }

    private var readableText: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("PDF \(model.page)쪽").font(.system(size: 12, weight: .medium)).foregroundStyle(ReaderStyle.accent)
                    Text(pageText).font(.system(size: 17)).lineSpacing(9).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(32).frame(maxWidth: 720)
                    .background(ReaderStyle.panel, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusLarge, style: .continuous))
                    .modifier(ReaderSurfaceBorder())
                    .padding(24).frame(maxWidth: .infinity).id("text-page-top")
                    .background(TextScrollAnchor(target: textScrollTarget).frame(width: 0, height: 0))
            }.background(ReaderStyle.canvas)
                .focusable().focused($textReaderFocused)
                .focusEffectDisabled()
                .overlay(alignment: .top) {
                    if textReaderFocused { Rectangle().fill(ReaderStyle.accent.opacity(0.55)).frame(height: 1).allowsHitTesting(false) }
                }
                .onKeyPress(phases: [.down, .repeat], action: turnTextPage)
                .simultaneousGesture(TapGesture().onEnded { textReaderFocused = true })
                .task {
                    // The segmented control finishes its own focus update after mounting this view.
                    await Task.yield()
                    guard !Task.isCancelled, model.textMode else { return }
                    textReaderFocused = true
                }
                .onChange(of: model.readerFocusRequest) { _, _ in textReaderFocused = true }
                .onChange(of: model.page) { _, _ in proxy.scrollTo("text-page-top", anchor: .top) }
        }
    }

    private var pageText: String {
        let text = model.document?.page(at: model.page - 1)?.string ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "이 페이지에는 텍스트가 없습니다. 책 옵션에서 텍스트를 인식할 수 있습니다." : text
    }

    private func turnTextPage(_ press: KeyPress) -> KeyPress.Result {
        let modifiers = press.modifiers.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty || (press.key == .space && modifiers == .shift) else { return .ignored }
        let target: Int
        switch press.key {
        case .leftArrow, .pageUp: target = model.page - 1
        case .rightArrow, .pageDown: target = model.page + 1
        case .space: target = model.page + (modifiers == .shift ? -1 : 1)
        case .home: target = 1
        case .end: target = pageCount
        case .upArrow: textScrollTarget.scroll(by: -48); return .handled
        case .downArrow: textScrollTarget.scroll(by: 48); return .handled
        default: return .ignored
        }
        model.goToPage(target)
        return .handled
    }

    private var unavailableBook: some View {
        VStack(spacing: 16) {
            Image(systemName: book.isAvailable ? "doc.questionmark" : "icloud.and.arrow.down").font(.system(size: 35, weight: .light)).foregroundStyle(.secondary)
            Text(book.title).font(.title3)
            Text(book.isAvailable ? "파일을 다시 열어보세요." : "이 책은 iCloud에서 다운로드해야 합니다.").foregroundStyle(.secondary)
            HStack {
                if !book.isAvailable { Button("다운로드 요청") { model.downloadBook() } }
                Button("다시 열기") { model.selectBook(book) }
                Button("Finder에서 보기") { model.revealSource() }
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectionActions: some View {
        HStack(spacing: 14) {
            Image(systemName: "text.quote").foregroundStyle(ReaderStyle.accent)
            Text("\(model.selection.reduce(0) { $0 + $1.quote.count })자 선택").font(.system(size: 12))
            Divider().frame(height: 18)
            Button("발췌 메모에 담기") { model.saveSelection() }
                .buttonStyle(.borderless).font(.system(size: 12, weight: .semibold)).accessibilityLabel("발췌 메모에 담기")
            ReaderIconButton(symbol: "xmark", label: "선택 닫기") { model.selection = []; model.pdfView?.clearSelection() }
        }.padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusPanel, style: .continuous))
            .modifier(ReaderSurfaceBorder(radius: ReaderTokens.radiusPanel))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 4).padding(.bottom, 20)
    }

    private var pageControls: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                Rectangle().fill(ReaderStyle.muted)
                    .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.25)).frame(width: geometry.size.width * progress) }
            }.frame(height: 2).accessibilityHidden(true)
            HStack(spacing: 12) {
                ReaderIconButton(symbol: model.bookmarks.contains(model.page) ? "bookmark.fill" : "bookmark",
                                 label: model.bookmarks.contains(model.page) ? "책갈피 해제" : "책갈피 추가",
                                 selected: model.bookmarks.contains(model.page)) { model.toggleBookmark() }
                    .disabled(model.document == nil)
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    HStack(spacing: 12) {
                        pageButton(forward: false)
                        HStack(spacing: 6) {
                            TextField("페이지", text: $pageEntry)
                                .textFieldStyle(.plain).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                                .multilineTextAlignment(.center).frame(width: 48, height: 28)
                                .background(ReaderStyle.muted, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusMedium))
                                .onSubmit { if let number = Int(pageEntry) { model.goToPage(number, focusReader: true) }; pageEntry = String(model.page) }
                                .accessibilityLabel("페이지 번호").help("페이지 번호를 입력하고 Return")
                            Text("/ \(pageCount)").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        pageButton(forward: true)
                    }
                    Text("좌우 방향키로 페이지 이동").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                ReaderIconButton(symbol: "keyboard", label: "키보드 조작 안내") { showKeyboardHelp.toggle() }
                    .popover(isPresented: $showKeyboardHelp, arrowEdge: .top) { KeyboardHelp() }
            }.padding(.horizontal, 18).frame(height: ReaderStyle.footerHeight)
        }
    }

    private func pageButton(forward: Bool) -> some View {
        ReaderIconButton(symbol: forward ? "chevron.right" : "chevron.left", label: forward ? "다음 페이지" : "이전 페이지") {
            model.goToPage(model.page + (forward ? 1 : -1), focusReader: true)
        }
            .disabled(model.document == nil || (forward ? model.page >= pageCount : model.page <= 1))
            .help(forward ? "다음 페이지 (오른쪽 방향키)" : "이전 페이지 (왼쪽 방향키)")
            .accessibilityLabel(forward ? "다음 페이지" : "이전 페이지")
    }
}

struct EmptyLibraryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "book.pages").font(.system(size: 42, weight: .light)).foregroundStyle(.secondary)
                .frame(width: 88, height: 88).background(.regularMaterial, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusPanel))
            Text("책에서 시작되는 생각").font(.system(size: 24, weight: .medium))
            Text("PDF를 읽고, 문장을 남기고, 내 말로 정리해보세요.").font(.system(size: 13)).foregroundStyle(.secondary)
            HStack(spacing: 12) { Button("PDF 추가…") { model.chooseFiles() }.buttonStyle(.borderedProminent); Button("폴더 연결…") { model.chooseFiles(folder: true) } }.padding(.top, 10)
            if !model.books.isEmpty { Text("왼쪽 책장에서 읽을 책을 선택할 수 있습니다.").font(.system(size: 12)).foregroundStyle(.secondary) }
            Text("원본은 제자리에. 메모는 이 Mac에.").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 35)
        }
    }
}
