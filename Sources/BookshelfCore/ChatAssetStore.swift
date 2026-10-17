import Foundation

/// User-selected media is copied into app-owned storage; model paths never grant file access.
public enum ChatAssetStore {
    public static let extensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "svg", "html", "htm", "mmd", "mermaid", "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "mp4", "mov", "m4v"]
    public static func kind(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff": return "image"
        case "svg": return "svg"
        case "html", "htm": return "html"
        case "mmd", "mermaid": return "mermaid"
        case "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac": return "audio"
        case "mp4", "mov", "m4v": return "video"
        default: return nil
        }
    }
    public static func importFile(_ source: URL, directory: URL) throws -> ChatAttachment {
        let source = source.resolvingSymlinksInPath()
        let ext = source.pathExtension.lowercased()
        guard let kind = kind(forExtension: ext) else { throw ShelfError.message("지원하지 않는 자료 형식입니다.") }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        let limit = ["html", "svg", "mermaid"].contains(kind) ? 2_000_000 : 250_000_000
        guard values.isRegularFile == true, let size = values.fileSize, size <= limit else {
            throw ShelfError.message("자료를 열 수 없습니다. 시각화 코드는 2MB, 미디어는 250MB 이내로 선택해 주세요.")
        }
        let root = directory.appendingPathComponent("ChatAssets", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let id = UUID().uuidString, name = id + "." + ext
        try FileManager.default.copyItem(at: source, to: root.appendingPathComponent(name))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: root.appendingPathComponent(name).path)
        return ChatAttachment(id: id, name: source.lastPathComponent, fileName: name, kind: kind)
    }
    public static func url(for attachment: ChatAttachment, directory: URL) -> URL? {
        guard attachment.fileName == (attachment.fileName as NSString).lastPathComponent,
              UUID(uuidString: (attachment.fileName as NSString).deletingPathExtension) != nil,
              kind(forExtension: (attachment.fileName as NSString).pathExtension) == attachment.kind else { return nil }
        let root = directory.appendingPathComponent("ChatAssets", isDirectory: true).resolvingSymlinksInPath()
        let url = root.appendingPathComponent(attachment.fileName).resolvingSymlinksInPath()
        guard url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
