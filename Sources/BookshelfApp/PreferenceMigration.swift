import Foundation
import BookshelfCore

enum PreferenceMigration {
    static func migrateCurrentInstallation() {
        let product = AppMetadata.current
        guard Bundle.main.bundleIdentifier == product.bundleIdentifier else { return }
        migrateAppearance(defaults: .standard, currentDomain: product.bundleIdentifier,
                          legacyDomains: product.legacyBundleIdentifiers)
    }

    static func migrateAppearance(defaults: UserDefaults, currentDomain: String, legacyDomains: [String]) {
        guard defaults.persistentDomain(forName: currentDomain)?["readerAppearance"] == nil else { return }
        for domain in legacyDomains {
            guard let value = defaults.persistentDomain(forName: domain)?["readerAppearance"] as? String,
                  ReaderAppearance(rawValue: value) != nil else { continue }
            defaults.set(value, forKey: "readerAppearance")
            return
        }
    }
}
