import XCTest
import Foundation
@testable import BookshelfApp

final class PreferenceMigrationTests: XCTestCase {
    func testCopiesOnlyAppearanceAndPreservesNewChoice() throws {
        let current = "bookside-migration-current-" + UUID().uuidString
        let legacy = "bookside-migration-legacy-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: current))
        defer { defaults.removePersistentDomain(forName: current); defaults.removePersistentDomain(forName: legacy) }
        defaults.setPersistentDomain(["readerAppearance": "dark", "unrelated": "keep private"], forName: legacy)
        PreferenceMigration.migrateAppearance(defaults: defaults, currentDomain: current, legacyDomains: [legacy])
        XCTAssertEqual(defaults.string(forKey: "readerAppearance"), "dark")
        XCTAssertNil(defaults.object(forKey: "unrelated"))
        XCTAssertEqual(defaults.persistentDomain(forName: legacy)?["unrelated"] as? String, "keep private")
        defaults.set("light", forKey: "readerAppearance")
        PreferenceMigration.migrateAppearance(defaults: defaults, currentDomain: current, legacyDomains: [legacy])
        XCTAssertEqual(defaults.string(forKey: "readerAppearance"), "light")
    }

    func testInvalidLegacyValueDoesNotCreateANewPreference() throws {
        let current = "bookside-migration-current-" + UUID().uuidString
        let legacy = "bookside-migration-legacy-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: current))
        defer { defaults.removePersistentDomain(forName: current); defaults.removePersistentDomain(forName: legacy) }
        defaults.setPersistentDomain(["readerAppearance": "unknown-mode"], forName: legacy)
        PreferenceMigration.migrateAppearance(defaults: defaults, currentDomain: current, legacyDomains: [legacy])
        XCTAssertNil(defaults.persistentDomain(forName: current)?["readerAppearance"])
    }
}
