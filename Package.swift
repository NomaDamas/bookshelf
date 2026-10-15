// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bookshelf",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BookshelfCore", targets: ["BookshelfCore"]),
        .executable(name: "Bookshelf", targets: ["BookshelfApp"]),
        .executable(name: "bookshelf-cli", targets: ["BookshelfCLI"]),
    ],
    dependencies: [.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "BookshelfCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "BookshelfApp", dependencies: ["BookshelfCore"]),
        .executableTarget(name: "BookshelfCLI", dependencies: ["BookshelfCore", .product(name: "MCP", package: "swift-sdk")]),
        .testTarget(name: "BookshelfCoreTests", dependencies: ["BookshelfCore"]),
    ],
    swiftLanguageModes: [.v5]
)
