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
    init() { PreferenceMigration.migrateCurrentInstallation() }
    var body: some Scene {
        WindowGroup("서재") {
            ReaderWindow(model: model)
                .preferredColorScheme(appearance.colorScheme)
                .onAppear { delegate.model = model }
                .onOpenURL { url in
                    guard url.scheme == "bookshelf", url.host == "book", let id = url.pathComponents.last, let book = try? model.store.book(id) else { return }
                    model.selectBook(book)
                    if let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value, let page = Int(raw) {
                        Task { for _ in 0..<100 { if model.document != nil && model.activeBook?.id == id { model.goToPage(page); return }; try? await Task.sleep(for: .milliseconds(100)) } }
                    }
                }
        }
        .defaultSize(width: 1380, height: 900)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("PDF 추가…") { model.chooseFiles() }.keyboardShortcut("o")
                Button("폴더 추가…") { model.chooseFiles(folder: true) }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("읽기") {
                Button("서재로 돌아가기") { model.showLibrary() }.keyboardShortcut(model.shortcuts[.library].value)
                Divider()
                Button("이전 페이지") { model.goToPage(model.page - 1, focusReader: true) }.keyboardShortcut(model.shortcuts[.previousPage].value)
                Button("다음 페이지") { model.goToPage(model.page + 1, focusReader: true) }.keyboardShortcut(model.shortcuts[.nextPage].value)
                Button("읽기 화면으로") { model.focusReader() }.keyboardShortcut(model.shortcuts[.focusReader].value).disabled(model.document == nil)
                Button("책갈피") { model.toggleBookmark() }.keyboardShortcut(model.shortcuts[.bookmark].value)
                Divider()
                Button("페이지 목록") { model.openBookTool("pages") }.keyboardShortcut(model.shortcuts[.pages].value)
                Button("책 메모") { model.openBookTool("notes") }.keyboardShortcut(model.shortcuts[.notes].value)
                Button("발췌") { model.openBookTool("quotes") }.keyboardShortcut(model.shortcuts[.excerpts].value)
                Button("이 책에서 찾기") { model.openBookTool("search") }.keyboardShortcut(model.shortcuts[.search].value)
                Button("선택 문장 메모") { model.saveSelection() }.keyboardShortcut("h", modifiers: [.command, .shift]).disabled(model.selection.isEmpty)
                Button("메모 저장") { model.flushPendingSave() }.keyboardShortcut(model.shortcuts[.saveNote].value)
                Button("메모 내보내기…") { model.exportNotes() }.disabled(model.activeBook == nil)
                Divider()
                Button("텍스트 인식…") { model.startOCR() }.disabled(model.activeBook == nil || model.ocrRunning)
                Button("기존 OCR 개선…") { model.startOCR(mode: .replaceText) }.disabled(model.activeBook == nil || model.ocrRunning)
                Button("생성한 OCR 사본 검토…") { model.reviewLatestOCR() }.disabled(model.activeBook == nil || model.ocrRunning)
                Button("원본 PDF 사용") { model.useOriginalPDF() }.disabled(model.activeBook?.ocrPath == nil || model.ocrRunning)
            }
            CommandGroup(after: .sidebar) {
                Button("왼쪽 사이드바 표시") { model.sidebarVisible.toggle() }.keyboardShortcut(model.shortcuts[.leftSidebar].value)
                Button("AI 패널 표시") { model.toggleAIPanel() }.keyboardShortcut(model.shortcuts[.aiPanel].value).disabled(AgentRuntime.bridgeURL == nil)
            }
        }
        Settings { SettingsView(model: model).preferredColorScheme(appearance.colorScheme) }
    }
}
