import XCTest
import BookshelfCore
@testable import BookshelfApp

@MainActor final class AppShortcutTests: XCTestCase {
    func testCustomShortcutPersistsAcrossModelRestartAndCanReset() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root)
        let model = AppModel(store: store), changed = AppKeyBinding(key: "p", modifiers: 3)
        model.setShortcut(changed, for: .aiPanel)
        XCTAssertNil(model.shortcutError)
        let reopened = AppModel(store: try LibraryStore(directory: root))
        XCTAssertEqual(reopened.shortcuts[.aiPanel], changed)
        reopened.resetShortcuts()
        XCTAssertEqual(AppModel(store: try LibraryStore(directory: root)).shortcuts[.aiPanel], ReaderAction.aiPanel.defaultBinding)
    }
    func testDuplicateAndPlainTypingShortcutsDoNotReplaceAnExistingBinding() throws {
        var values = AppShortcuts()
        XCTAssertThrowsError(try values.set(values[.search], for: .aiPanel))
        XCTAssertThrowsError(try values.set(.init(key: "a", modifiers: 0), for: .aiPanel))
        XCTAssertThrowsError(try values.set(.init(key: "q", modifiers: 1), for: .aiPanel))
        XCTAssertEqual(values[.aiPanel], ReaderAction.aiPanel.defaultBinding)
    }
    func testDefaultsAreDistinctValidAndOutsideReservedKeys() throws {
        let defaults = ReaderAction.allCases.map(\.defaultBinding)
        XCTAssertEqual(Set(defaults.map(\.label)).count, defaults.count)
        for action in ReaderAction.allCases {
            XCTAssertNoThrow(try AppShortcuts.validate(action.defaultBinding, for: action), action.title)
            XCTAssertNotNil(action.defaultBinding.value, action.title)
        }
        XCTAssertEqual(ShortcutGroup.allCases.flatMap(\.actions).count, ReaderAction.allCases.count)
    }
    func testSystemKeysAndBareModifiersAreRejected() {
        var values = AppShortcuts()
        for (key, modifiers) in [("w", 1), ("h", 1), ("/", 9), ("q", 5), ("f", 5), ("o", 1), (" ", 4), ("left", 4)] {
            XCTAssertThrowsError(try values.set(.init(key: key, modifiers: modifiers), for: .bookmark), "\(key) \(modifiers)")
        }
        XCTAssertThrowsError(try values.set(.init(key: "a", modifiers: 4), for: .bookmark), "Control alone edits text")
        XCTAssertThrowsError(try values.set(.init(key: "b", modifiers: 2), for: .bookmark), "Option alone types characters")
        XCTAssertThrowsError(try values.set(.init(key: "up", modifiers: 2), for: .bookmark), "Option-arrow is only for page commands")
        XCTAssertNoThrow(try values.set(.init(key: "left", modifiers: 2), for: .previousPage))
        XCTAssertNoThrow(try values.set(.init(key: "b", modifiers: 5), for: .bookmark))
    }
    func testClearedShortcutHasNoKeyAndDefaultCanBeRestored() throws {
        var values = AppShortcuts()
        try values.set(AppKeyBinding.unassigned, for: .search)
        XCTAssertNil(values[.search].value)
        XCTAssertEqual(values[.search].label, "없음")
        try values.set(ReaderAction.search.defaultBinding, for: .bookmark)
        XCTAssertThrowsError(try values.restoreDefault(.search), "⌘F now belongs to the bookmark")
        try values.set(AppKeyBinding.unassigned, for: .bookmark)
        try values.restoreDefault(.search)
        XCTAssertEqual(values[.search], ReaderAction.search.defaultBinding)
    }
    func testLoadingKeepsSavedOverridesAndUnassignsCollidingDefaults() {
        // An older build saved ⌘0 for the sidebar; ⌘0 is now the default for actual size.
        let saved = AppShortcuts(overrides: [
            ReaderAction.leftSidebar.rawValue: .init(key: "0", modifiers: 1),
            ReaderAction.bookmark.rawValue: .init(key: "q", modifiers: 1),
            ReaderAction.notes.rawValue: .init(key: "0", modifiers: 1),
        ]).validated()
        XCTAssertEqual(saved[.leftSidebar], .init(key: "0", modifiers: 1))
        XCTAssertTrue(saved[.actualSize].isUnassigned)
        XCTAssertEqual(saved[.bookmark], ReaderAction.bookmark.defaultBinding, "⌘Q is reserved")
        XCTAssertEqual(saved[.notes], ReaderAction.notes.defaultBinding, "a duplicate override falls back")
        let bindings = ReaderAction.allCases.map { saved[$0] }.filter { !$0.isUnassigned }
        XCTAssertEqual(Set(bindings.map(\.label)).count, bindings.count)
    }
    func testRecorderReadsKeysFromTheASCIILayoutPosition() {
        // keyCode 1 is the S key; under a Korean input source its characters are "ㄴ".
        XCTAssertEqual(AppKeyBinding.asciiKey(1), "s")
        XCTAssertEqual(AppKeyBinding.asciiKey(18), "1", "Shift is a modifier flag, so ⇧⌘1 is not stored as ⇧⌘!")
        XCTAssertEqual(AppKeyBinding.asciiKey(24), "=")
    }
}
