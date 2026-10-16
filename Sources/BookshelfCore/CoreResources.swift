import Foundation

private final class ResourceAnchor: NSObject {}

enum CoreResources {
    static func url(forResource name: String, withExtension fileExtension: String) -> URL? {
        let main = Bundle.main
        let roots: [URL]
        if main.bundleURL.pathExtension == "app" {
            // Distributed apps must be self-contained. SwiftPM's generated accessor
            // can fall back to an absolute build-machine path and hide a bad package.
            roots = [main.bundleURL.appendingPathComponent("Contents/Resources")]
        } else {
            // Raw SwiftPM executables and XCTest bundles keep resources beside the product.
            let containing = Bundle(for: ResourceAnchor.self)
            roots = [main.resourceURL, main.bundleURL, containing.resourceURL,
                     containing.bundleURL.deletingLastPathComponent()].compactMap { $0 }
        }
        for root in roots {
            let bundle = root.appendingPathComponent("Bookshelf_BookshelfCore.bundle")
            // Swift toolchains emit both flat and conventional macOS resource bundles.
            for directory in [bundle.appendingPathComponent("Contents/Resources"), bundle] {
                let candidate = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }
}
