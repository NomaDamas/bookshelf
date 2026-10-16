import Foundation
import CSQLite

/// Shared local store for the Mac app and the read-only MCP surface.
/// SQLite serializes writes across processes; this lock protects each connection.
public final class LibraryStore: @unchecked Sendable {
    public let directory: URL
    public let databaseURL: URL
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(directory: URL = FileAccess.defaultDataDirectory()) throws {
        self.directory = directory
        databaseURL = directory.appendingPathComponent("library.sqlite3")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw ShelfError.message("서재 데이터베이스를 열지 못했습니다.") }
        sqlite3_busy_timeout(db, 5000)
        try exec("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL;")
        try exec("""
        CREATE TABLE IF NOT EXISTS books (
            id TEXT PRIMARY KEY, title TEXT NOT NULL, category TEXT NOT NULL,
            source_path TEXT NOT NULL UNIQUE, ocr_path TEXT, file_identity TEXT NOT NULL,
            root_path TEXT NOT NULL, page_count INTEGER NOT NULL DEFAULT 0,
            text_pages INTEGER NOT NULL DEFAULT -1, last_page INTEGER NOT NULL DEFAULT 1,
            last_opened REAL NOT NULL DEFAULT 0, created REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS books_identity ON books(file_identity);
        CREATE TABLE IF NOT EXISTS notebooks (
            book_id TEXT PRIMARY KEY REFERENCES books(id), body TEXT NOT NULL,
            revision INTEGER NOT NULL, updated REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS highlights (
            id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id),
            page INTEGER NOT NULL CHECK(page>0), quote TEXT NOT NULL, comment TEXT NOT NULL,
            rects TEXT NOT NULL, created REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS highlights_book ON highlights(book_id, page);
        CREATE TABLE IF NOT EXISTS bookmarks (
            book_id TEXT NOT NULL REFERENCES books(id), page INTEGER NOT NULL CHECK(page>0),
            PRIMARY KEY(book_id, page)
        );
        CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS ocr_candidates (
            path TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id), report_path TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS ocr_versions (path TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id));
        PRAGMA user_version=1;
        """)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
    }
    deinit { sqlite3_close(db) }

    private func synchronized<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }
    private func error() -> ShelfError { .message(String(cString: sqlite3_errmsg(db))) }
    private func exec(_ sql: String) throws { if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw error() } }
    private func query(_ sql: String, _ values: [String?] = []) throws -> [[String: String]] {
        try synchronized {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
            defer { sqlite3_finalize(statement) }
            for (i, value) in values.enumerated() {
                if let value { sqlite3_bind_text(statement, Int32(i + 1), value, -1, transient) }
                else { sqlite3_bind_null(statement, Int32(i + 1)) }
            }
            var rows: [[String: String]] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW else { throw error() }
                var row: [String: String] = [:]
                for col in 0..<sqlite3_column_count(statement) {
                    if let value = sqlite3_column_text(statement, col), let name = sqlite3_column_name(statement, col) { row[String(cString: name)] = String(cString: value) }
                }
                rows.append(row)
            }
            return rows
        }
    }
    private func decodeBook(_ row: [String: String]) -> Book {
        Book(id: row["id"]!, title: row["title"]!, category: row["category"]!, sourcePath: row["source_path"]!, ocrPath: row["ocr_path"], fileIdentity: row["file_identity"]!, rootPath: row["root_path"]!, pageCount: Int(row["page_count"]!) ?? 0, textPages: Int(row["text_pages"]!) ?? -1, lastPage: Int(row["last_page"]!) ?? 1, lastOpened: Double(row["last_opened"]!) ?? 0, created: Double(row["created"]!) ?? 0)
    }
    public func books(query search: String = "") throws -> [Book] {
        let all = try query("SELECT * FROM books ORDER BY last_opened DESC, title COLLATE NOCASE").map(decodeBook)
        let term = search.precomposedStringWithCanonicalMapping.replacingOccurrences(of: " ", with: "").lowercased()
        return term.isEmpty ? all : all.filter { ($0.title + $0.category).replacingOccurrences(of: " ", with: "").lowercased().contains(term) }
    }
    public func book(_ id: String) throws -> Book {
        guard let row = try query("SELECT * FROM books WHERE id=?", [id]).first else { throw ShelfError.message("서재에서 책을 찾지 못했습니다.") }
        return decodeBook(row)
    }
    @discardableResult public func register(source: URL, ocr: URL?, root: URL) throws -> Book {
        try synchronized {
            let path = FileAccess.canonicalPath(source), identity = FileAccess.identity(source)
            if let owner = try query("SELECT book_id FROM ocr_versions WHERE path=?", [path]).first?["book_id"] { return try book(owner) }
            let ocrKey = ocr.map(FileAccess.canonicalPath)
            let existing = try query("SELECT * FROM books WHERE source_path=? OR ocr_path=? OR file_identity=? OR source_path=? OR ocr_path=? LIMIT 1", [path, path, identity, ocrKey, ocrKey]).first
            let base = source.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_ocr", with: "", options: [.anchored, .backwards])
            let title = base.replacingOccurrences(of: "_", with: " ").precomposedStringWithCanonicalMapping
            let rootPath = FileAccess.canonicalPath(root)
            let rel = path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : source.lastPathComponent
            let category = rel.contains("/") ? String(rel.split(separator: "/")[0]) : ""
            let id = existing?["id"] ?? UUID().uuidString
            if let existing {
                // Re-importing an attached OCR asset must not replace the original source identity.
                if path == existing["ocr_path"], path != existing["source_path"] { return try book(id) }
                // Path updates keep the book ID and all user notes. Never clear a known OCR version during a rescan.
                let knownOCR = existing["ocr_path"].flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
                let preferOriginal = try setting("preferOriginal." + id) == "true"
                let effectiveOCR = preferOriginal ? nil : knownOCR ?? ocr.map(FileAccess.canonicalPath)
                let oldRoot = existing["root_path"] ?? rootPath
                let keepWiderRoot = path.hasPrefix(oldRoot + "/") && oldRoot.count < rootPath.count
                let savedRoot = keepWiderRoot ? oldRoot : rootPath
                let savedCategory = keepWiderRoot ? existing["category"] ?? category : category
                _ = try query("UPDATE books SET source_path=?, ocr_path=?, file_identity=?, title=?, category=?, root_path=? WHERE id=?", [path, effectiveOCR, identity, title, savedCategory, savedRoot, id])
            } else {
                _ = try query("INSERT INTO books(id,title,category,source_path,ocr_path,file_identity,root_path,created) VALUES(?,?,?,?,?,?,?,?)", [id,title,category,path,ocr.map(FileAccess.canonicalPath),identity,rootPath,String(Date().timeIntervalSince1970)])
            }
            return try book(id)
        }
    }
    public func holdOCRCandidate(bookID: String, url: URL, report: URL) throws {
        _ = try query("INSERT INTO ocr_candidates(path,book_id,report_path) VALUES(?,?,?) ON CONFLICT(path) DO UPDATE SET report_path=excluded.report_path", [FileAccess.canonicalPath(url),bookID,report.path])
    }
    public func heldOCRPaths() throws -> Set<String> { Set(try query("SELECT path FROM ocr_candidates").compactMap { $0["path"] }) }
    public func ocrReviewReport(bookID: String) throws -> String? { try query("SELECT report_path FROM ocr_candidates WHERE book_id=? ORDER BY rowid DESC LIMIT 1", [bookID]).first?["report_path"] }
    public func attachOCR(bookID: String, url: URL, pageCount: Int, textPages: Int, expectedSourcePath: String? = nil) throws {
        try synchronized {
            try exec("BEGIN IMMEDIATE")
            do {
                if let expectedSourcePath, try book(bookID).activePath != expectedSourcePath { throw ShelfError.message("검토 중 다른 OCR 사본이 선택되었습니다. 현재 PDF를 유지합니다.") }
                if let previous = try book(bookID).ocrPath { _ = try query("INSERT OR IGNORE INTO ocr_versions(path,book_id) VALUES(?,?)", [previous,bookID]) }
                _ = try query("INSERT OR IGNORE INTO ocr_versions(path,book_id) VALUES(?,?)", [FileAccess.canonicalPath(url),bookID])
                _ = try query("UPDATE books SET ocr_path=?,page_count=?,text_pages=? WHERE id=?", [FileAccess.canonicalPath(url),String(pageCount),String(textPages),bookID])
                _ = try query("DELETE FROM ocr_candidates WHERE path=?", [FileAccess.canonicalPath(url)])
                try setSetting("preferOriginal." + bookID, value: "false")
                try exec("COMMIT")
            } catch { try? exec("ROLLBACK"); throw error }
        }
    }
    public func useOriginal(bookID: String) throws {
        let current = try book(bookID)
        let inspection = try PDFService.inspect(URL(fileURLWithPath: current.sourcePath))
        try synchronized {
            try exec("BEGIN IMMEDIATE")
            do {
                _ = try query("UPDATE books SET ocr_path=NULL,page_count=?,text_pages=? WHERE id=?", [String(inspection.pageCount),String(inspection.textPages),bookID])
                try setSetting("preferOriginal." + bookID, value: "true")
                try exec("COMMIT")
            } catch { try? exec("ROLLBACK"); throw error }
        }
    }
    public func updateInspection(bookID: String, pageCount: Int, textPages: Int) throws {
        _ = try query("UPDATE books SET page_count=?,text_pages=? WHERE id=?", [String(pageCount),String(textPages),bookID])
    }
    public func savePosition(bookID: String, page: Int) throws {
        let b = try book(bookID)
        guard page > 0, b.pageCount == 0 || page <= b.pageCount else { throw ShelfError.message("유효하지 않은 페이지 번호입니다.") }
        _ = try query("UPDATE books SET last_page=?,last_opened=? WHERE id=?", [String(page),String(Date().timeIntervalSince1970),bookID])
    }
    public func notebook(bookID: String) throws -> Notebook {
        guard let row = try query("SELECT * FROM notebooks WHERE book_id=?", [bookID]).first else { return Notebook() }
        return Notebook(body: row["body"]!, revision: Int(row["revision"]!)!, updated: Double(row["updated"]!)!)
    }
    @discardableResult public func saveNotebook(bookID: String, body: String, expectedRevision: Int) throws -> Notebook {
        guard body.utf8.count <= 2_000_000 else { throw ShelfError.message("메모가 너무 큽니다. 2MB 이하로 나누어 주세요.") }
        return try synchronized {
            try exec("BEGIN IMMEDIATE")
            do {
                _ = try book(bookID)
                let current = try notebook(bookID: bookID)
                guard current.revision == expectedRevision else { throw ShelfError.conflict }
                let updated = Notebook(body: body, revision: current.revision + 1, updated: Date().timeIntervalSince1970)
                _ = try query("INSERT INTO notebooks(book_id,body,revision,updated) VALUES(?,?,?,?) ON CONFLICT(book_id) DO UPDATE SET body=excluded.body,revision=excluded.revision,updated=excluded.updated", [bookID,body,String(updated.revision),String(updated.updated)])
                try exec("COMMIT")
                return updated
            } catch { try? exec("ROLLBACK"); throw error }
        }
    }
    public func highlights(bookID: String) throws -> [Highlight] {
        try query("SELECT * FROM highlights WHERE book_id=? ORDER BY page,created", [bookID]).map { row in
            Highlight(id: row["id"]!, bookID: bookID, page: Int(row["page"]!)!, quote: row["quote"]!, comment: row["comment"]!, rects: (try? JSONDecoder().decode([PageRect].self, from: Data(row["rects"]!.utf8))) ?? [], created: Double(row["created"]!)!)
        }
    }
    public func saveHighlight(_ h: Highlight) throws {
        guard h.page > 0, !h.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ShelfError.message("선택한 문장이 없습니다.") }
        _ = try book(h.bookID)
        let rects = String(data: try JSONEncoder().encode(h.rects), encoding: .utf8)!
        _ = try query("INSERT INTO highlights(id,book_id,page,quote,comment,rects,created) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET comment=excluded.comment", [h.id,h.bookID,String(h.page),h.quote,h.comment,rects,String(h.created)])
    }
    public func deleteHighlight(id: String, bookID: String) throws { _ = try query("DELETE FROM highlights WHERE id=? AND book_id=?", [id,bookID]) }
    public func bookmarks(bookID: String) throws -> [Int] { try query("SELECT page FROM bookmarks WHERE book_id=? ORDER BY page", [bookID]).compactMap { Int($0["page"]!) } }
    public func toggleBookmark(bookID: String, page: Int) throws {
        guard page > 0 else { throw ShelfError.message("페이지 번호를 확인해 주세요.") }
        if try bookmarks(bookID: bookID).contains(page) { _ = try query("DELETE FROM bookmarks WHERE book_id=? AND page=?", [bookID,String(page)]) }
        else { _ = try query("INSERT INTO bookmarks(book_id,page) VALUES(?,?)", [bookID,String(page)]) }
    }
    public func setting(_ key: String) throws -> String? { try query("SELECT value FROM settings WHERE key=?", [key]).first?["value"] }
    public func setSetting(_ key: String, value: String) throws { _ = try query("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [key,value]) }
    public func exportMarkdown(bookID: String) throws -> String {
        let b = try book(bookID), n = try notebook(bookID: bookID), hs = try highlights(bookID: bookID)
        var text = "# \(b.title)\n\n\(n.body)\n\n## 발췌 메모\n"
        for h in hs { text += "\n### PDF \(h.page)쪽\n\n> " + h.quote.replacingOccurrences(of: "\n", with: "\n> ") + "\n\n" + h.comment + "\n" }
        return text
    }
}
