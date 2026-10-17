import XCTest
@testable import BookshelfApp

final class ArtifactNavigationTests: XCTestCase {
    func testBundleRelativeURLAndWebKitAbsoluteURLReferToTheSameRenderer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let base = root.appendingPathComponent("App.app", isDirectory: true)
        let relative = try XCTUnwrap(URL(string: "Contents/Resources/Agent/renderer.html", relativeTo: base))
        let absolute = URL(fileURLWithPath: relative.path)
        XCTAssertNotEqual(relative, absolute, "Foundation retains a base URL; literal URL equality caused a blank preview")
        XCTAssertTrue(ArtifactNavigationPolicy.allows(absolute, renderer: relative, mainFrame: true))
        XCTAssertFalse(ArtifactNavigationPolicy.allows(root.appendingPathComponent("private.txt"), renderer: relative, mainFrame: true))
        XCTAssertFalse(ArtifactNavigationPolicy.allows(URL(string: "https://example.org"), renderer: relative, mainFrame: true))
        XCTAssertTrue(ArtifactNavigationPolicy.allows(URL(string: "about:srcdoc"), renderer: relative, mainFrame: false))
        XCTAssertFalse(ArtifactNavigationPolicy.allows(URL(string: "about:srcdoc"), renderer: relative, mainFrame: true))
    }
}
