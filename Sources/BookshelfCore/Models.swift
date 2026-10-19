import Foundation
import Darwin

public struct Book: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var category: String
    public var sourcePath: String
    public var ocrPath: String?
    public var fileIdentity: String
    public var rootPath: String
    public var pageCount: Int
    public var textPages: Int
    public var lastPage: Int
    public var lastOpened: Double
    public var created: Double
    public var activePath: String { ocrPath ?? sourcePath }
    public var url: URL { URL(fileURLWithPath: activePath) }
    public var displayCategory: String { category.isEmpty ? "내 서재" : category }
    public var isAvailable: Bool { FileAccess.isResident(url) }
    public var textStatus: String {
        if textPages < 0 { return "텍스트 확인 전" }
        if textPages == 0 { return "텍스트 인식 필요" }
        if textPages < pageCount { return "텍스트 \(textPages)/\(pageCount)쪽" }
        return "텍스트 선택 가능"
    }
}

public struct Notebook: Codable, Sendable {
    public var body: String
    public var revision: Int
    public var updated: Double
    public init(body: String = "", revision: Int = 0, updated: Double = 0) {
        self.body = body; self.revision = revision; self.updated = updated
    }
}

public struct PageRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct Highlight: Codable, Identifiable, Sendable {
    public var id: String
    public var bookID: String
    public var page: Int
    public var quote: String
    public var comment: String
    public var rects: [PageRect]
    public var created: Double
    public init(id: String = UUID().uuidString, bookID: String, page: Int, quote: String, comment: String = "", rects: [PageRect] = [], created: Double = Date().timeIntervalSince1970) {
        self.id = id; self.bookID = bookID; self.page = page; self.quote = quote
        self.comment = comment; self.rects = rects; self.created = created
    }
}

public struct SearchHit: Codable, Identifiable, Sendable {
    public var page: Int
    public var text: String
    public var id: Int { page }
}

public enum ShelfError: LocalizedError {
    case message(String)
    case conflict
    case cancelled
    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .conflict: return "다른 창에서 메모가 변경되었습니다. 현재 내용을 복사한 뒤 다시 불러와 주세요."
        case .cancelled: return "텍스트 인식을 취소했습니다. 원본은 그대로 보존됩니다."
        }
    }
}

public enum FileAccess {
    /// Cheap local metadata for list indicators. Opening still performs the full
    /// iCloud availability check below, outside the list's rendering path.
    public static func hasLocalData(_ url: URL) -> Bool {
        var info = stat()
        return url.path.withCString { lstat($0, &info) } == 0
            && info.st_size > 0 && (info.st_flags & 0x40000000) == 0
    }
    public static func isResident(_ url: URL) -> Bool {
        var info = stat()
        if url.path.withCString({ lstat($0, &info) }) != 0 || (info.st_flags & 0x40000000) != 0 { return false }
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
        let flags = (a[.size] as? NSNumber)?.int64Value ?? 0
        guard flags > 0 else { return false }
        if let v = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]), let s = v.ubiquitousItemDownloadingStatus, s == .notDownloaded { return false }
        return true
    }
    public static func canonicalPath(_ url: URL) -> String { url.standardizedFileURL.path.precomposedStringWithCanonicalMapping }
    public static func identity(_ url: URL) -> String {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path), let inode = a[.systemFileNumber] as? NSNumber, let device = a[.systemNumber] as? NSNumber else { return canonicalPath(url) }
        return "\(device):\(inode)"
    }
    public static func defaultDataDirectory(environment: [String: String] = ProcessInfo.processInfo.environment,
                                            applicationSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) -> URL {
        if let custom = ProductEnvironment.value("DATA_DIR", in: environment) { return URL(fileURLWithPath: custom, isDirectory: true) }
        let current = applicationSupport.appendingPathComponent("Bookside", isDirectory: true)
        // A library created before the rename is used in place; moving it could split
        // the database from WAL sidecars while another Bookshelf process still runs.
        let legacy = applicationSupport.appendingPathComponent("Bookshelf", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: current.path), fm.fileExists(atPath: legacy.appendingPathComponent("library.sqlite3").path) { return legacy }
        return current
    }
}
