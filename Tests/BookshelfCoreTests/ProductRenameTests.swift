import XCTest
@testable import BookshelfCore

final class ProductRenameTests: XCTestCase {
    func testNewEnvironmentPrefixWinsAndOldPrefixStillApplies() {
        XCTAssertEqual(ProductEnvironment.value("DATA_DIR", in: ["BOOKSIDE_DATA_DIR": "/new", "BOOKSHELF_DATA_DIR": "/old"]), "/new")
        XCTAssertEqual(ProductEnvironment.value("DATA_DIR", in: ["BOOKSIDE_DATA_DIR": "", "BOOKSHELF_DATA_DIR": "/old"]), "/old")
        XCTAssertNil(ProductEnvironment.value("DATA_DIR", in: ["BOOKSHELF_DATA_DIR": ""]))
    }

    func testExistingBookshelfLibraryIsUsedInPlace() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let current = support.appendingPathComponent("Bookside", isDirectory: true)
        let legacy = support.appendingPathComponent("Bookshelf", isDirectory: true)
        XCTAssertEqual(FileAccess.defaultDataDirectory(environment: [:], applicationSupport: support), current)

        // An unrelated Bookshelf folder without our database is not adopted.
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        XCTAssertEqual(FileAccess.defaultDataDirectory(environment: [:], applicationSupport: support), current)

        try Data().write(to: legacy.appendingPathComponent("library.sqlite3"))
        XCTAssertEqual(FileAccess.defaultDataDirectory(environment: [:], applicationSupport: support), legacy)

        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        XCTAssertEqual(FileAccess.defaultDataDirectory(environment: [:], applicationSupport: support), current)
        XCTAssertEqual(FileAccess.defaultDataDirectory(environment: ["BOOKSHELF_DATA_DIR": "/custom"], applicationSupport: support).path, "/custom")
    }
}
