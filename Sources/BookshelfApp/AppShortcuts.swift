import Carbon.HIToolbox
import SwiftUI
import BookshelfCore

enum ShortcutGroup: String, CaseIterable, Identifiable {
    case view, navigate, find, notes, pi
    var id: String { rawValue }
    var title: String {
        switch self {
        case .view: return "보기"
        case .navigate: return "이동"
        case .find: return "찾기"
        case .notes: return "책갈피와 메모"
        case .pi: return "Pi"
        }
    }
    var symbol: String {
        switch self {
        case .view: return "sidebar.left"
        case .navigate: return "arrow.up.arrow.down"
        case .find: return "magnifyingglass"
        case .notes: return "bookmark"
        case .pi: return "bubble.left.and.text.bubble.right"
        }
    }
    var actions: [ReaderAction] { ReaderAction.allCases.filter { $0.group == self } }
}

/// Defaults follow macOS and Preview: zoom ⌘+ ⌘- ⌘0 ⌘9, pages ⌥↑ ⌥↓, go to page ⌥⌘G,
/// find ⌘F ⌘G ⇧⌘G, sidebar ⌃⌘S, sidebar views ⌥⌘1-3, inspector-style Pi panel ⌥⌘I.
enum ReaderAction: String, CaseIterable, Identifiable, Codable {
    case leftSidebar, aiPanel, pages, notes, excerpts, zoomIn, zoomOut, actualSize, zoomToFit
    case library, previousPage, nextPage, goToPage, focusReader
    case search, findNext, findPrevious
    case bookmark, highlight, saveNote
    case sendMessage
    var id: String { rawValue }
    var group: ShortcutGroup {
        switch self {
        case .leftSidebar, .aiPanel, .pages, .notes, .excerpts, .zoomIn, .zoomOut, .actualSize, .zoomToFit: return .view
        case .library, .previousPage, .nextPage, .goToPage, .focusReader: return .navigate
        case .search, .findNext, .findPrevious: return .find
        case .bookmark, .highlight, .saveNote: return .notes
        case .sendMessage: return .pi
        }
    }
    var title: String {
        switch self {
        case .leftSidebar: return "사이드바 보기/숨기기"
        case .aiPanel: return "Pi 패널 보기/숨기기"
        case .pages: return "페이지 목록"
        case .notes: return "책 메모"
        case .excerpts: return "발췌"
        case .zoomIn: return "확대"
        case .zoomOut: return "축소"
        case .actualSize: return "실제 크기"
        case .zoomToFit: return "페이지에 맞춤"
        case .library: return "서재로 돌아가기"
        case .previousPage: return "이전 페이지"
        case .nextPage: return "다음 페이지"
        case .goToPage: return "페이지로 이동"
        case .focusReader: return "읽기 화면으로"
        case .search: return "이 책에서 찾기"
        case .findNext: return "다음 찾기"
        case .findPrevious: return "이전 찾기"
        case .bookmark: return "책갈피 추가/해제"
        case .highlight: return "선택 문장 발췌"
        case .saveNote: return "메모 저장"
        case .sendMessage: return "Pi에게 질문 보내기"
        }
    }
    var defaultBinding: AppKeyBinding {
        switch self {
        case .leftSidebar: return .init(key: "s", modifiers: 5)
        case .aiPanel: return .init(key: "i", modifiers: 3)
        case .pages: return .init(key: "1", modifiers: 3)
        case .notes: return .init(key: "2", modifiers: 3)
        case .excerpts: return .init(key: "3", modifiers: 3)
        case .zoomIn: return .init(key: "+", modifiers: 1)
        case .zoomOut: return .init(key: "-", modifiers: 1)
        case .actualSize: return .init(key: "0", modifiers: 1)
        case .zoomToFit: return .init(key: "9", modifiers: 1)
        case .library: return .init(key: "l", modifiers: 9)
        case .previousPage: return .init(key: "up", modifiers: 2)
        case .nextPage: return .init(key: "down", modifiers: 2)
        case .goToPage: return .init(key: "g", modifiers: 3)
        case .focusReader: return .init(key: "r", modifiers: 9)
        case .search: return .init(key: "f", modifiers: 1)
        case .findNext: return .init(key: "g", modifiers: 1)
        case .findPrevious: return .init(key: "g", modifiers: 9)
        case .bookmark: return .init(key: "d", modifiers: 1)
        case .highlight: return .init(key: "h", modifiers: 5)
        case .saveNote: return .init(key: "s", modifiers: 1)
        case .sendMessage: return .init(key: "return", modifiers: 1)
        }
    }
    /// Option-arrow moves by word or paragraph in text fields, so page commands step aside while text is edited.
    var yieldsToTextInput: Bool { self == .previousPage || self == .nextPage }
}

struct AppKeyBinding: Codable, Equatable {
    let key: String
    /// App-owned flags: command=1, option=2, control=4, shift=8.
    let modifiers: Int
    /// A binding the user cleared on purpose.
    static let unassigned = AppKeyBinding(key: "", modifiers: 0)
    static let namedKeys = ["left", "right", "up", "down", "return"]
    var isUnassigned: Bool { key.isEmpty }
    var value: KeyboardShortcut? {
        guard !isUnassigned else { return nil }
        let equivalent: KeyEquivalent
        switch key { case "left": equivalent = .leftArrow; case "right": equivalent = .rightArrow; case "up": equivalent = .upArrow; case "down": equivalent = .downArrow; case "return": equivalent = .return; default: equivalent = KeyEquivalent(key.first ?? " ") }
        var flags: SwiftUI.EventModifiers = []
        if modifiers & 1 != 0 { flags.insert(.command) }; if modifiers & 2 != 0 { flags.insert(.option) }
        if modifiers & 4 != 0 { flags.insert(.control) }; if modifiers & 8 != 0 { flags.insert(.shift) }
        return KeyboardShortcut(equivalent, modifiers: flags)
    }
    var label: String {
        guard !isUnassigned else { return "없음" }
        let names = ["left":"←", "right":"→", "up":"↑", "down":"↓", "return":"↩"]
        return (modifiers & 4 != 0 ? "⌃" : "") + (modifiers & 2 != 0 ? "⌥" : "") + (modifiers & 8 != 0 ? "⇧" : "") + (modifiers & 1 != 0 ? "⌘" : "") + (names[key] ?? key.uppercased())
    }
    var isArrow: Bool { ["left", "right", "up", "down"].contains(key) }
    static func from(_ event: NSEvent) -> AppKeyBinding? {
        let named: [UInt16: String] = [123:"left",124:"right",125:"down",126:"up",36:"return",76:"return"]
        // The ASCII layout keeps Shift-digits and keys typed with a Korean input source readable (⇧⌘1, not ⇧⌘!).
        guard let key = named[event.keyCode] ?? asciiKey(event.keyCode) ?? event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return nil }
        let flags = event.modifierFlags
        return AppKeyBinding(key: key, modifiers: (flags.contains(.command) ? 1 : 0) | (flags.contains(.option) ? 2 : 0) | (flags.contains(.control) ? 4 : 0) | (flags.contains(.shift) ? 8 : 0))
    }
    static func asciiKey(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0, length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layout.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(base, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let key = String(utf16CodeUnits: characters, count: length).lowercased()
        return key.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 32 }) ? key : nil
    }
}

struct AppShortcuts: Codable {
    var overrides: [String: AppKeyBinding] = [:]
    /// Shortcuts owned by macOS or by fixed app menus. Recording one would leave two menu items on the same keys.
    static let reserved: [AppKeyBinding] = [
        ("q", 1), ("w", 1), ("w", 3), ("o", 1), ("o", 9), ("c", 1), ("v", 1), ("x", 1), ("z", 1), ("z", 9), ("a", 1),
        (",", 1), ("h", 1), ("h", 3), ("m", 1), ("m", 3), ("`", 1), ("/", 9), ("\\", 9), ("f", 5), ("q", 5), (".", 1),
        ("3", 9), ("4", 9), ("5", 9), (" ", 1), (" ", 4), ("\t", 1), ("left", 4), ("right", 4), ("up", 4), ("down", 4),
    ].map { AppKeyBinding(key: $0.0, modifiers: $0.1) }
    subscript(_ action: ReaderAction) -> AppKeyBinding { overrides[action.rawValue] ?? action.defaultBinding }
    mutating func set(_ binding: AppKeyBinding, for action: ReaderAction) throws {
        if binding.isUnassigned { overrides[action.rawValue] = binding; return }
        try Self.validate(binding, for: action)
        if let other = ReaderAction.allCases.first(where: { $0 != action && self[$0] == binding }) { throw ShelfError.message("\(binding.label) 단축키는 ‘\(other.title)’에서 이미 쓰고 있습니다.") }
        overrides[action.rawValue] = binding
    }
    mutating func restoreDefault(_ action: ReaderAction) throws {
        let binding = action.defaultBinding
        if let other = ReaderAction.allCases.first(where: { $0 != action && self[$0] == binding }) { throw ShelfError.message("기본값 \(binding.label) 단축키는 ‘\(other.title)’에서 이미 쓰고 있습니다.") }
        overrides[action.rawValue] = nil
    }
    static func validate(_ binding: AppKeyBinding, for action: ReaderAction) throws {
        guard binding.modifiers & ~15 == 0, binding.key.count == 1 || AppKeyBinding.namedKeys.contains(binding.key) else {
            throw ShelfError.message("이 키는 단축키로 쓸 수 없습니다.")
        }
        let command = binding.modifiers & 1 != 0, option = binding.modifiers & 2 != 0, control = binding.modifiers & 4 != 0
        if !command {
            // ⌃ alone edits text (⌃A, ⌃E, ⌃K) and switches Spaces; ⌥ alone types characters or moves by word.
            guard option, !control, binding.isArrow, action.yieldsToTextInput else {
                throw ShelfError.message("Command와 함께 눌러 주세요. Option만 쓰는 조합은 페이지 이동 화살표에만 쓸 수 있습니다.")
            }
        }
        if reserved.contains(binding) { throw ShelfError.message("\(binding.label) 단축키는 macOS나 앱 메뉴에서 쓰고 있습니다.") }
    }
    /// Saved overrides win over defaults. An invalid or duplicate override falls back to its default,
    /// and a default that a saved override already uses is left unassigned.
    func validated() -> AppShortcuts {
        var result = AppShortcuts(), taken: [AppKeyBinding] = []
        for action in ReaderAction.allCases {
            guard let binding = overrides[action.rawValue] else { continue }
            if binding.isUnassigned { result.overrides[action.rawValue] = binding; continue }
            guard (try? Self.validate(binding, for: action)) != nil, !taken.contains(binding) else { continue }
            result.overrides[action.rawValue] = binding; taken.append(binding)
        }
        for action in ReaderAction.allCases where result.overrides[action.rawValue] == nil && taken.contains(action.defaultBinding) {
            result.overrides[action.rawValue] = AppKeyBinding.unassigned
        }
        return result
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
                if event.keyCode == 51 || event.keyCode == 117 { self.stop(); self.onChange?(AppKeyBinding.unassigned); return nil }
                if let value = AppKeyBinding.from(event) { self.stop(); self.onChange?(value) }
                return nil
            }
        }
        override func resignFirstResponder() -> Bool { stop(); return super.resignFirstResponder() }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = false; title = bindingLabel }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
