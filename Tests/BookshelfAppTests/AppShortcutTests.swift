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
}
