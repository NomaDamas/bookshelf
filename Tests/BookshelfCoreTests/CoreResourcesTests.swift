import XCTest
@testable import BookshelfCore

final class CoreResourcesTests: XCTestCase {
    func testSwiftPackageResourcesAreAvailableToTests() throws {
        let metadata = AppMetadata.current
        XCTAssertFalse(metadata.name.isEmpty)
        XCTAssertFalse(metadata.version.isEmpty)
        let helper = try XCTUnwrap(CoreResources.url(forResource: "prepare-ocr-replacement", withExtension: "py"))
        XCTAssertTrue(try String(contentsOf: helper, encoding: .utf8).contains("pikepdf"))
    }
}
