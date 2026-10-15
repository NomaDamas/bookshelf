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
        guard model.flushPendingSave() else { return .terminateCancel }
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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("서재") {
            ReaderWindow(model: model)
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
                Button("이전 페이지") { model.goToPage(model.page - 1, focusReader: true) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("다음 페이지") { model.goToPage(model.page + 1, focusReader: true) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("읽기 화면으로") { model.focusReader() }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model.document == nil)
                Button("책갈피") { model.toggleBookmark() }.keyboardShortcut("d")
                Divider()
                Button("이 책에서 찾기") { model.notesVisible = true; model.panelTab = "search" }.keyboardShortcut("f")
                Button("선택 문장 메모") { model.saveSelection() }.keyboardShortcut("h", modifiers: [.command, .shift]).disabled(model.selection.isEmpty)
                Button("메모 저장") { model.flushPendingSave() }.keyboardShortcut("s")
                Button("메모 내보내기…") { model.exportNotes() }.disabled(model.activeBook == nil)
                Divider()
                Button("텍스트 인식…") { model.startOCR() }.disabled(model.activeBook == nil || model.ocrRunning)
            }
            CommandGroup(after: .sidebar) {
                Button("책장 표시") { model.sidebarVisible.toggle() }.keyboardShortcut("0")
                Button("메모 패널 표시") { model.notesVisible.toggle() }.keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
        Settings { SettingsView(model: model) }
    }
}
