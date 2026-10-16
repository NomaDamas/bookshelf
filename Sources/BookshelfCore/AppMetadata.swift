import Foundation

public struct ProductMetadata: Decodable, Sendable {
    public let name: String
    public let bundleIdentifier: String
    public let version: String
    public let buildNumber: Int
    public let minimumMacOS: String
    public let repository: String
    public let legacyBundleIdentifiers: [String]
}

public enum AppMetadata {
    public static let current: ProductMetadata = {
        guard let url = Bundle.module.url(forResource: "AppMetadata", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode(ProductMetadata.self, from: data) else {
            fatalError("Bookshelf product metadata is missing or invalid. Rebuild the app bundle.")
        }
        return metadata
    }()
}
