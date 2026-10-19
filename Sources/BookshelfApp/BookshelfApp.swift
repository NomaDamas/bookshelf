import SwiftUI
import BookshelfCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !model.chat.importingAssets else { model.information = "자료를 보관하고 있습니다. 완료 후 종료할 수 있습니다."; return .terminateCancel }
        guard model.flushPendingSave() else { return .terminateCancel }
        model.chat.stop()
        guard model.chat.persist() else { return .terminateCancel }
        model.savePositionNow()
        if model.ocrRunning {
            let alert = NSAlert(); alert.messageText = "텍스트 인식이 진행 중입니다."
            alert.informativeText = "진행 중인 작업을 취소하고 서재를 종료할까요? 원본 PDF는 보존됩니다."
            alert.addButton(withTitle: "계속 작업"); alert.addButton(withTitle: "취소하고 종료")
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
            model.cancelOCR()
            Task {
                for _ in 0..<100 {
                    if !model.ocrRunning { NSApp.reply(toApplicationShouldTerminate: true); return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                NSApp.reply(toApplicationShouldTerminate: false)
                model.errorMessage = "OCR 종료를 기다리고 있습니다. 잠시 후 다시 종료해 주세요."
            }
            return .terminateLater
        }
        return .terminateNow
    }
}

@main struct BookshelfApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("readerAppearance") private var appearance = ReaderAppearance.system
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() {
        PreferenceMigration.migrateCurrentInstallation()
        // Every window shows the same library state, so window tabs would only duplicate it.
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    var body: some Scene {
        WindowGroup("서재") {
            ReaderWindow(model: model)
                .preferredColorScheme(appearance.colorScheme)
                .onAppear { delegate.model = model }
                .onOpenURL { url in
                    guard let scheme = url.scheme, ["bookside", "bookshelf"].contains(scheme), url.host == "book", let id = url.pathComponents.last, let book = try? model.store.book(id) else { return }
                    model.selectBook(book)
                    if let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value, let page = Int(raw) {
                        Task { for _ in 0..<100 { if model.document != nil && model.activeBook?.id == id { model.goToPage(page); return }; try? await Task.sleep(for: .milliseconds(100)) } }
                    }
                }
        }
        .defaultSize(width: 1380, height: 900)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("PDF 추가…") { model.chooseFiles() }.keyboardShortcut("o")
                Button("폴더 추가…") { model.chooseFiles(folder: true) }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            // Close lives in the save group, so the note commands follow it instead of replacing it.
            CommandGroup(after: .saveItem) {
                item(.saveNote) { model.flushPendingSave() }
                Button("메모 내보내기…") { model.exportNotes() }.disabled(model.activeBook == nil)
            }
            CommandGroup(after: .textEditing) {
                Menu("찾기") {
                    item(.search) { model.findInBook() }.disabled(model.activeBook == nil)
                    item(.findNext) { model.findNext() }.disabled(model.activeBook == nil)
                    item(.findPrevious) { model.findNext(forward: false) }.disabled(model.activeBook == nil)
                }
            }
            CommandGroup(after: .sidebar) {
                item(.leftSidebar, title: model.sidebarVisible ? "사이드바 숨기기" : "사이드바 보기") { model.sidebarVisible.toggle() }
                item(.aiPanel, title: model.isReadingBook && model.aiPanelVisible ? "Pi 패널 숨기기" : "Pi 패널 보기") { model.toggleAIPanel() }
                    .disabled(AgentRuntime.bridgeURL == nil || model.activeBook == nil)
                Divider()
                item(.pages) { model.openBookTool("pages") }.disabled(model.activeBook == nil)
                item(.notes) { model.openBookTool("notes") }.disabled(model.activeBook == nil)
                item(.excerpts) { model.openBookTool("quotes") }.disabled(model.activeBook == nil)
                Divider()
                item(.zoomIn) { model.zoom(.zoomIn) }.disabled(!model.canZoom)
                item(.zoomOut) { model.zoom(.zoomOut) }.disabled(!model.canZoom)
                item(.actualSize) { model.zoom(.actualSize) }.disabled(!model.canZoom)
                item(.zoomToFit) { model.zoom(.fit) }.disabled(!model.canZoom)
                Divider()
            }
            CommandMenu("이동") {
                item(.library) { model.showLibrary() }
                Divider()
                item(.previousPage) { model.goToPage(model.page - 1, focusReader: true) }.disabled(model.document == nil || model.textInputActive)
                item(.nextPage) { model.goToPage(model.page + 1, focusReader: true) }.disabled(model.document == nil || model.textInputActive)
                item(.goToPage, title: "페이지로 이동…") { model.requestPageEntry() }.disabled(!model.isReadingBook || model.document == nil)
                Divider()
                item(.focusReader) { model.focusReader() }.disabled(model.document == nil)
            }
            CommandMenu("책") {
                item(.bookmark) { model.toggleBookmark() }.disabled(model.document == nil)
                item(.highlight) { model.saveSelection() }.disabled(model.selection.isEmpty)
                Divider()
                Button("책장에서 보기") { model.revealCurrentBook() }.disabled(model.activeBook == nil)
                Button("Finder에서 보기") { model.revealSource() }.disabled(model.activeBook == nil)
                Divider()
                Button("텍스트 인식…") { model.startOCR() }.disabled(model.activeBook == nil || model.ocrRunning)
                Button("기존 OCR 개선…") { model.startOCR(mode: .replaceText) }.disabled(model.activeBook == nil || model.ocrRunning)
                Button("생성한 OCR 사본 검토…") { model.reviewLatestOCR() }.disabled(model.activeBook == nil || model.ocrRunning)
                Button("원본 PDF 사용") { model.useOriginalPDF() }.disabled(model.activeBook?.ocrPath == nil || model.ocrRunning)
                Divider()
                Button("AI로 이어가기") { model.copyContext() }.disabled(model.activeBook == nil)
            }
            HelpCommands()
        }
        Window(KeyboardShortcutsList.windowTitle, id: KeyboardShortcutsList.windowID) {
            KeyboardShortcutsList(model: model).preferredColorScheme(appearance.colorScheme)
        }
        .windowResizability(.contentSize)
        // The Help menu opens this list; a Window menu entry would repeat it.
        .commandsRemoved()
        Settings { SettingsView(model: model).preferredColorScheme(appearance.colorScheme) }
    }
    /// Menu items for remappable actions read their keys from the user's shortcut settings.
    private func item(_ action: ReaderAction, title: String? = nil, perform: @escaping () -> Void) -> some View {
        Button(title ?? action.title, action: perform).keyboardShortcut(model.shortcuts[action].value)
    }
}

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Bookside 키보드 단축키") { openWindow(id: KeyboardShortcutsList.windowID) }
        }
    }
}
