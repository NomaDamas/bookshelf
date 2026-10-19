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
        guard let url = CoreResources.url(forResource: "AppMetadata", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode(ProductMetadata.self, from: data) else {
            fatalError("Bookside product metadata is missing or invalid. Rebuild the app bundle.")
        }
        return metadata
    }()
}

/// Reads `BOOKSIDE_<name>`. The pre-rename `BOOKSHELF_<name>` still applies when the
/// new variable is unset, so MCP configs written for Bookshelf keep their settings.
public enum ProductEnvironment {
    public static func value(_ name: String, in environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        for prefix in ["BOOKSIDE_", "BOOKSHELF_"] {
            if let value = environment[prefix + name], !value.isEmpty { return value }
        }
        return nil
    }
}
