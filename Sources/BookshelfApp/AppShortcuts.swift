import SwiftUI
import BookshelfCore

enum ReaderAction: String, CaseIterable, Identifiable, Codable {
    case leftSidebar, aiPanel, library, pages, notes, excerpts, search, previousPage, nextPage, focusReader, bookmark, saveNote, sendMessage
    var id: String { rawValue }
    var title: String {
        switch self {
        case .leftSidebar: return "왼쪽 사이드바"
        case .aiPanel: return "AI 패널"
        case .library: return "서재로 돌아가기"
        case .pages: return "페이지 목록"
        case .notes: return "책 메모"
        case .excerpts: return "발췌"
        case .search: return "책 안에서 검색"
        case .previousPage: return "이전 페이지"
        case .nextPage: return "다음 페이지"
        case .focusReader: return "읽기 화면으로"
        case .bookmark: return "책갈피"
        case .saveNote: return "메모 저장"
        case .sendMessage: return "AI 질문 보내기"
        }
    }
    var defaultBinding: AppKeyBinding {
        switch self {
        case .leftSidebar: return .init(key: "0", modifiers: 1)
        case .aiPanel: return .init(key: "a", modifiers: 9)
        case .library: return .init(key: "l", modifiers: 9)
        case .pages: return .init(key: "1", modifiers: 1)
        case .notes: return .init(key: "2", modifiers: 1)
        case .excerpts: return .init(key: "3", modifiers: 1)
        case .search: return .init(key: "f", modifiers: 1)
        case .previousPage: return .init(key: "left", modifiers: 3)
        case .nextPage: return .init(key: "right", modifiers: 3)
        case .focusReader: return .init(key: "r", modifiers: 9)
        case .bookmark: return .init(key: "d", modifiers: 1)
        case .saveNote: return .init(key: "s", modifiers: 1)
        case .sendMessage: return .init(key: "return", modifiers: 1)
        }
    }
}

struct AppKeyBinding: Codable, Equatable {
    let key: String
    /// App-owned flags: command=1, option=2, control=4, shift=8.
    let modifiers: Int
    var value: KeyboardShortcut {
        let equivalent: KeyEquivalent
        switch key { case "left": equivalent = .leftArrow; case "right": equivalent = .rightArrow; case "up": equivalent = .upArrow; case "down": equivalent = .downArrow; case "return": equivalent = .return; default: equivalent = KeyEquivalent(key.first ?? " ") }
        var flags: EventModifiers = []
        if modifiers & 1 != 0 { flags.insert(.command) }; if modifiers & 2 != 0 { flags.insert(.option) }
        if modifiers & 4 != 0 { flags.insert(.control) }; if modifiers & 8 != 0 { flags.insert(.shift) }
        return KeyboardShortcut(equivalent, modifiers: flags)
    }
    var label: String {
        let names = ["left":"←", "right":"→", "up":"↑", "down":"↓", "return":"↩"]
        return (modifiers & 4 != 0 ? "⌃" : "") + (modifiers & 2 != 0 ? "⌥" : "") + (modifiers & 8 != 0 ? "⇧" : "") + (modifiers & 1 != 0 ? "⌘" : "") + (names[key] ?? key.uppercased())
    }
    static func from(_ event: NSEvent) -> AppKeyBinding? {
        let named: [UInt16: String] = [123:"left",124:"right",125:"down",126:"up",36:"return",76:"return"]
        guard let key = named[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return nil }
        let flags = event.modifierFlags
        return AppKeyBinding(key: key, modifiers: (flags.contains(.command) ? 1 : 0) | (flags.contains(.option) ? 2 : 0) | (flags.contains(.control) ? 4 : 0) | (flags.contains(.shift) ? 8 : 0))
    }
}

struct AppShortcuts: Codable {
    var overrides: [String: AppKeyBinding] = [:]
    subscript(_ action: ReaderAction) -> AppKeyBinding { overrides[action.rawValue] ?? action.defaultBinding }
    mutating func set(_ binding: AppKeyBinding, for action: ReaderAction) throws {
        guard binding.modifiers & 7 != 0, binding.modifiers & ~15 == 0,
              binding.key.count == 1 || ["left","right","up","down","return"].contains(binding.key) else { throw ShelfError.message("Command, Option 또는 Control과 키를 함께 눌러 주세요.") }
        if binding.modifiers == 1 && ["q","w","o","c","v","x","z","a",",","\t"," "].contains(binding.key) { throw ShelfError.message("macOS의 기본 편집과 창 조작에 쓰는 단축키입니다.") }
        if let other = ReaderAction.allCases.first(where: { $0 != action && self[$0] == binding }) { throw ShelfError.message("\(binding.label)은 ‘\(other.title)’에서 사용 중입니다.") }
        overrides[action.rawValue] = binding
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let label: String
    let action: String
    let onChange: (AppKeyBinding) -> Void
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(); button.bezelStyle = .rounded; button.controlSize = .small
        button.target = button; button.action = #selector(RecorderButton.beginRecording)
        button.setAccessibilityLabel(action + " 단축키 변경"); return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) { button.bindingLabel = label; button.onChange = onChange; if !button.recording { button.title = label } }
    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) { button.stop() }
    final class RecorderButton: NSButton {
        var bindingLabel = ""
        var onChange: ((AppKeyBinding) -> Void)?
        var recording = false
        private var monitor: Any?
        override var acceptsFirstResponder: Bool { true }
        @objc func beginRecording() {
            window?.makeFirstResponder(self); recording = true; title = "키를 눌러 주세요"
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.recording, self.window?.firstResponder === self, event.window === self.window else { return event }
                if event.keyCode == 53 { self.stop(); return nil }
                if let value = AppKeyBinding.from(event) { self.stop(); self.onChange?(value) }
                return nil
            }
        }
        override func resignFirstResponder() -> Bool { stop(); return super.resignFirstResponder() }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = false; title = bindingLabel }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
