import Foundation

public enum LibraryImporter {
    public static let excludedFolders: Set<String> = ["_DEDUP_STAGING", "00-Materials", ".bookshelf-cache", "scripts", "context", "prompts", "node_modules", ".git"]
    @discardableResult public static func add(_ location: URL, to store: LibraryStore) throws -> [Book] {
        let location = location.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: location.path, isDirectory: &isDirectory) else { throw ShelfError.message("파일이나 폴더가 존재하지 않습니다.") }
        let root = isDirectory.boolValue ? location : location.deletingLastPathComponent()
        var files: [URL] = []
        if isDirectory.boolValue {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            guard let enumeration = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { throw ShelfError.message("폴더를 읽지 못했습니다.") }
            for case let file as URL in enumeration {
                let values = try file.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true || (values.isDirectory == true && excludedFolders.contains(file.lastPathComponent)) { enumeration.skipDescendants(); continue }
                if values.isRegularFile == true && file.pathExtension.lowercased() == "pdf" { files.append(file) }
            }
        } else {
            guard location.pathExtension.lowercased() == "pdf" else { throw ShelfError.message("PDF 파일을 선택해 주세요.") }
            files = [location]
            // Explicitly adding one member of a same-stem pair still imports the pair as one book.
            let base = location.deletingPathExtension()
            let mate = base.lastPathComponent.hasSuffix("_ocr") ? base.deletingLastPathComponent().appendingPathComponent(String(base.lastPathComponent.dropLast(4)) + ".pdf") : URL(fileURLWithPath: base.path + "_ocr.pdf")
            if FileManager.default.fileExists(atPath: mate.path) { files.append(mate) }
        }
        let withheld = try store.heldOCRPaths()
        files.removeAll { withheld.contains(FileAccess.canonicalPath($0)) }
        var groups: [String: [URL]] = [:]
        for file in files {
            let base = file.deletingPathExtension()
            let stem = base.lastPathComponent.hasSuffix("_ocr") ? String(base.lastPathComponent.dropLast(4)) : base.lastPathComponent
            let key = base.deletingLastPathComponent().appendingPathComponent(stem).path.precomposedStringWithCanonicalMapping
            groups[key, default: []].append(file)
        }
        var imported: [Book] = []
        for key in groups.keys.sorted() {
            let pair = groups[key]!.sorted { $0.path < $1.path }
            let ocr = pair.first { $0.deletingPathExtension().lastPathComponent.hasSuffix("_ocr") }
            let source = pair.first { !$0.deletingPathExtension().lastPathComponent.hasSuffix("_ocr") } ?? pair[0]
            imported.append(try store.register(source: source, ocr: ocr == source ? nil : ocr, root: root))
        }
        try store.setSetting("lastImportRoot", value: root.path)
        var seen = Set<String>()
        return imported.filter { seen.insert($0.id).inserted }
    }
}
