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
        CREATE TABLE IF NOT EXISTS conversations (
            book_id TEXT PRIMARY KEY REFERENCES books(id), body TEXT NOT NULL,
            revision INTEGER NOT NULL, updated REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS conversation_edits (
            id INTEGER PRIMARY KEY AUTOINCREMENT, book_id TEXT NOT NULL REFERENCES books(id), body TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS ocr_candidates (
            path TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id), report_path TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS ocr_versions (path TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id));
        CREATE TABLE IF NOT EXISTS reading_states (
            book_id TEXT PRIMARY KEY REFERENCES books(id),
            status TEXT NOT NULL CHECK(status IN ('unread','reading','finished')),
            started_at REAL, updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS reading_completions (
            id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id),
            started_at REAL, completed_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS reading_completions_book ON reading_completions(book_id, completed_at);
        """)
        try migrateReadingMembership()
        try migrateSchema()
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
        try readingTransaction {
            let b = try book(bookID)
            guard page > 0, b.pageCount == 0 || page <= b.pageCount else { throw ShelfError.message("유효하지 않은 페이지 번호입니다.") }
            let now = String(Date().timeIntervalSince1970)
            _ = try query("UPDATE books SET last_page=?,last_opened=? WHERE id=?", [String(page),now,bookID])
            // Only a first open starts reading automatically. Reviewing a finished
            // book or an explicitly shelved book must not start a new read-through.
            _ = try query("INSERT OR IGNORE INTO reading_states(book_id,status,started_at,updated_at) VALUES(?,'reading',?,?)", [bookID,now,now])
        }
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
    public func conversation(bookID: String) throws -> BookConversation {
        _ = try book(bookID)
        guard let row = try query("SELECT body,revision FROM conversations WHERE book_id=?", [bookID]).first else { return BookConversation() }
        let messages = try JSONDecoder().decode([BookChatMessage].self, from: Data(row["body"]!.utf8))
        return BookConversation(messages: messages, revision: Int(row["revision"]!)!)
    }
    @discardableResult public func saveConversation(bookID: String, messages: [BookChatMessage], expectedRevision: Int, preservePrevious: Bool = false) throws -> BookConversation {
        let data = try JSONEncoder().encode(messages)
        guard data.count <= 4_000_000,
              messages.allSatisfy({ ["user", "assistant"].contains($0.role) && $0.page > 0 && ["complete", "interrupted", "failed"].contains($0.state) }) else {
            throw ShelfError.message("대화 기록의 크기나 형식을 확인해 주세요.")
        }
        return try readingTransaction {
            let current = try conversation(bookID: bookID)
            guard current.revision == expectedRevision else { throw ShelfError.conflict }
            if preservePrevious {
                let previous = String(decoding: try JSONEncoder().encode(current.messages), as: UTF8.self)
                _ = try query("INSERT INTO conversation_edits(book_id,body) VALUES(?,?)", [bookID, previous])
                _ = try query("DELETE FROM conversation_edits WHERE book_id=? AND id NOT IN (SELECT id FROM conversation_edits WHERE book_id=? ORDER BY id DESC LIMIT 10)", [bookID, bookID])
            }
            let next = expectedRevision + 1
            _ = try query("INSERT INTO conversations(book_id,body,revision,updated) VALUES(?,?,?,?) ON CONFLICT(book_id) DO UPDATE SET body=excluded.body,revision=excluded.revision,updated=excluded.updated",
                          [bookID,String(decoding: data, as: UTF8.self),String(next),String(Date().timeIntervalSince1970)])
            return BookConversation(messages: messages, revision: next)
        }
    }
    public func canUndoConversationEdit(bookID: String) throws -> Bool {
        !(try query("SELECT id FROM conversation_edits WHERE book_id=? LIMIT 1", [bookID])).isEmpty
    }
    public func undoConversationEdit(bookID: String, expectedRevision: Int) throws -> BookConversation {
        try readingTransaction {
            let current = try conversation(bookID: bookID)
            guard current.revision == expectedRevision else { throw ShelfError.conflict }
            guard let saved = try query("SELECT id,body FROM conversation_edits WHERE book_id=? ORDER BY id DESC LIMIT 1", [bookID]).first,
                  let body = saved["body"], let id = saved["id"] else { return current }
            let messages = try JSONDecoder().decode([BookChatMessage].self, from: Data(body.utf8))
            let next = current.revision + 1
            _ = try query("UPDATE conversations SET body=?,revision=?,updated=? WHERE book_id=?", [body, String(next), String(Date().timeIntervalSince1970), bookID])
            _ = try query("DELETE FROM conversation_edits WHERE id=? AND book_id=?", [id, bookID])
            return BookConversation(messages: messages, revision: next)
        }
    }
    public func setSetting(_ key: String, value: String) throws { _ = try query("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [key,value]) }
    public func exportMarkdown(bookID: String) throws -> String {
        let b = try book(bookID), n = try notebook(bookID: bookID), hs = try highlights(bookID: bookID)
        var text = "# \(b.title)\n\n\(n.body)\n\n## 발췌 메모\n"
        for h in hs { text += "\n### PDF \(h.page)쪽\n\n> " + h.quote.replacingOccurrences(of: "\n", with: "\n> ") + "\n\n" + h.comment + "\n" }
        return text
    }

    private func readingTransaction<T>(_ body: () throws -> T) throws -> T {
        try synchronized {
            try exec("BEGIN IMMEDIATE")
            do { let value = try body(); try exec("COMMIT"); return value }
            catch { try? exec("ROLLBACK"); throw error }
        }
    }

    /// Import old shelf choices without inventing completions or start dates.
    /// INSERT OR IGNORE also supports a legacy CLI writing positions during an upgrade.
    private func migrateReadingMembership() throws {
        try readingTransaction {
            let legacy = try setting("readingShelf.membership").map {
                try JSONDecoder().decode([String: Bool].self, from: Data($0.utf8))
            } ?? [:]
            let rows = try query("SELECT b.id,b.last_opened FROM books b LEFT JOIN reading_states r ON r.book_id=b.id WHERE r.book_id IS NULL")
            for row in rows {
                let id = row["id"]!, opened = Double(row["last_opened"]!) ?? 0
                guard legacy[id] != nil || opened > 0 else { continue }
                let status: ReadingStatus = (legacy[id] ?? (opened > 0)) ? .reading : .unread
                _ = try query("INSERT OR IGNORE INTO reading_states(book_id,status,updated_at) VALUES(?,?,?)", [id,status.rawValue,String(opened)])
            }
        }
    }

    /// Version 2 adds the per-file structure layer as a new table; no existing table changes.
    /// Builds before it set user_version=1 on every open and ignore the table, so they keep
    /// reading and writing the library, and this step runs again idempotently afterwards.
    private func migrateSchema() throws {
        try readingTransaction {
            let version = Int(try query("PRAGMA user_version").first?["user_version"] ?? "0") ?? 0
            try exec("""
            CREATE TABLE IF NOT EXISTS structure_pages (
                book_id TEXT NOT NULL REFERENCES books(id), file_sha256 TEXT NOT NULL,
                page INTEGER NOT NULL CHECK(page>0),
                state TEXT NOT NULL CHECK(state IN ('candidate','accepted','needs_review')),
                markdown TEXT NOT NULL, blocks TEXT NOT NULL, info TEXT NOT NULL,
                created REAL NOT NULL, decided REAL,
                PRIMARY KEY(book_id, file_sha256, page)
            );
            """)
            if version < 2 { try exec("PRAGMA user_version=2") }
        }
    }

    public func readingSummaries(bookID: String? = nil) throws -> [String: ReadingSummary] {
        let rows = try query("""
        SELECT b.id,COALESCE(r.status,'unread') AS status,r.started_at,COALESCE(r.updated_at,0) AS updated_at,
               COALESCE(c.total,0) AS total,c.last_completed
        FROM books b LEFT JOIN reading_states r ON r.book_id=b.id
        LEFT JOIN (SELECT book_id,COUNT(*) AS total,MAX(completed_at) AS last_completed
                   FROM reading_completions GROUP BY book_id) c ON c.book_id=b.id
        """ + (bookID == nil ? "" : " WHERE b.id=?"), bookID.map { [$0] } ?? [])
        return Dictionary(uniqueKeysWithValues: rows.map { row in
            var summary = ReadingSummary()
            summary.status = ReadingStatus(rawValue: row["status"]!) ?? .unread
            summary.completedCount = Int(row["total"]!) ?? 0
            summary.startedAt = row["started_at"].flatMap(Double.init)
            summary.lastCompletedAt = row["last_completed"].flatMap(Double.init)
            summary.updatedAt = Double(row["updated_at"]!) ?? 0
            return (row["id"]!, summary)
        })
    }

    public func readingHistory(bookID: String) throws -> [ReadingCompletion] {
        try query("SELECT * FROM reading_completions WHERE book_id=? ORDER BY completed_at DESC,rowid DESC", [bookID]).map {
            ReadingCompletion(id: $0["id"]!, bookID: bookID, startedAt: $0["started_at"].flatMap(Double.init), completedAt: Double($0["completed_at"]!)!)
        }
    }

    private func setReadingState(_ status: ReadingStatus, bookID: String, started: Double?, now: Double) throws {
        _ = try query("""
        INSERT INTO reading_states(book_id,status,started_at,updated_at) VALUES(?,?,?,?)
        ON CONFLICT(book_id) DO UPDATE SET status=excluded.status,started_at=excluded.started_at,updated_at=excluded.updated_at
        """, [bookID,status.rawValue,started.map { String($0) },String(now)])
    }

    @discardableResult public func startReading(bookID: String, now: Double = Date().timeIntervalSince1970) throws -> Bool {
        try readingTransaction {
            _ = try book(bookID)
            let previous = try readingSummaries(bookID: bookID)[bookID] ?? ReadingSummary()
            guard previous.status != .reading else { return false }
            try setReadingState(.reading, bookID: bookID, started: now, now: now)
            if previous.status == .finished {
                _ = try query("UPDATE books SET last_page=1 WHERE id=?", [bookID])
            }
            return true
        }
    }

    @discardableResult public func completeReading(bookID: String, now: Double = Date().timeIntervalSince1970) throws -> Bool {
        try readingTransaction {
            _ = try book(bookID)
            let previous = try readingSummaries(bookID: bookID)[bookID] ?? ReadingSummary()
            guard previous.status != .finished else { return false }
            _ = try query("INSERT INTO reading_completions(id,book_id,started_at,completed_at) VALUES(?,?,?,?)",
                          [UUID().uuidString,bookID,previous.startedAt.map { String($0) },String(now)])
            try setReadingState(.finished, bookID: bookID, started: nil, now: now)
            return true
        }
    }

    @discardableResult public func undoReadingCompletion(bookID: String) throws -> Bool {
        try readingTransaction {
            _ = try book(bookID)
            guard try readingSummaries(bookID: bookID)[bookID]?.status == .finished,
                  let last = try readingHistory(bookID: bookID).first else { return false }
            _ = try query("DELETE FROM reading_completions WHERE id=? AND book_id=?", [last.id,bookID])
            try setReadingState(.reading, bookID: bookID, started: last.startedAt, now: Date().timeIntervalSince1970)
            return true
        }
    }

    /// A first read returns to unread; cancelling a reread retains past completions.
    public func shelveReading(bookID: String) throws {
        try readingTransaction {
            _ = try book(bookID)
            let previous = try readingSummaries(bookID: bookID)[bookID] ?? ReadingSummary()
            try setReadingState(previous.completedCount > 0 ? .finished : .unread,
                                bookID: bookID, started: nil, now: Date().timeIntervalSince1970)
        }
    }

    public func noteCounts(bookID: String? = nil) throws -> [String: NoteCount] {
        // Match whitespace-only notes without loading every notebook body into the UI.
        let whitespace = "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D} \u{0085}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}"
        let rows = try query("""
        SELECT b.id,CASE WHEN length(trim(n.body,?))>0 THEN 1 ELSE 0 END AS notebook,
               (SELECT COUNT(*) FROM highlights h WHERE h.book_id=b.id) AS excerpts
        FROM books b LEFT JOIN notebooks n ON n.book_id=b.id
        """ + (bookID == nil ? "" : " WHERE b.id=?"), [whitespace] + (bookID.map { [$0] } ?? []))
        return Dictionary(uniqueKeysWithValues: rows.map { row in
            var count = NoteCount(); count.notebook = Int(row["notebook"]!) ?? 0; count.excerpts = Int(row["excerpts"]!) ?? 0
            return (row["id"]!, count)
        })
    }
}

/// Structure layer rows. Every read and write names the file version, so results of one PDF
/// version never appear for another.
extension LibraryStore {
    private struct StructureInfo: Codable {
        var engine: StructureEngineInfo
        var geometry: StructureGeometry
        var reasons: [String]
        var seconds: Double
    }
    private func decodeStructure(_ row: [String: String]) throws -> StructurePage {
        let decoder = JSONDecoder()
        let info = try decoder.decode(StructureInfo.self, from: Data(row["info"]!.utf8))
        return StructurePage(bookID: row["book_id"]!, fileSHA256: row["file_sha256"]!, page: Int(row["page"]!)!, state: StructureState(rawValue: row["state"]!) ?? .needsReview,
                             markdown: row["markdown"]!, blocks: try decoder.decode([StructureBlock].self, from: Data(row["blocks"]!.utf8)), engine: info.engine,
                             geometry: info.geometry, reasons: info.reasons, seconds: info.seconds, created: Double(row["created"]!) ?? 0, decided: row["decided"].flatMap(Double.init))
    }
    /// Stores a new candidate or needs_review page. Returns false when the page is already accepted:
    /// acceptance is the reader's decision, so a later run never replaces it.
    @discardableResult public func saveStructurePage(_ page: StructurePage) throws -> Bool {
        guard page.state != .accepted else { throw ShelfError.message("구조 인식 결과는 검토한 뒤에만 승인할 수 있습니다.") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let blocks = String(decoding: try encoder.encode(page.blocks), as: UTF8.self)
        let info = String(decoding: try encoder.encode(StructureInfo(engine: page.engine, geometry: page.geometry, reasons: page.reasons, seconds: page.seconds)), as: UTF8.self)
        return try readingTransaction {
            _ = try book(page.bookID)
            if try query("SELECT state FROM structure_pages WHERE book_id=? AND file_sha256=? AND page=?", [page.bookID, page.fileSHA256, String(page.page)]).first?["state"] == StructureState.accepted.rawValue { return false }
            _ = try query("""
            INSERT INTO structure_pages(book_id,file_sha256,page,state,markdown,blocks,info,created,decided) VALUES(?,?,?,?,?,?,?,?,NULL)
            ON CONFLICT(book_id,file_sha256,page) DO UPDATE SET state=excluded.state,markdown=excluded.markdown,blocks=excluded.blocks,info=excluded.info,created=excluded.created,decided=NULL
            """, [page.bookID, page.fileSHA256, String(page.page), page.state.rawValue, page.markdown, blocks, info, String(page.created)])
            return true
        }
    }
    public func structurePages(bookID: String, fileSHA256: String, range: ClosedRange<Int>? = nil) throws -> [StructurePage] {
        let bounds = range.map { [String($0.lowerBound), String($0.upperBound)] } ?? ["1", String(Int32.max)]
        return try query("SELECT * FROM structure_pages WHERE book_id=? AND file_sha256=? AND page BETWEEN ? AND ? ORDER BY page", [bookID, fileSHA256] + bounds).map(decodeStructure)
    }
    /// Accepts candidates in the range. needs_review pages stay as they are until they are recomputed.
    public func acceptStructure(bookID: String, fileSHA256: String, range: ClosedRange<Int>) throws -> [Int] {
        try readingTransaction {
            let args = [bookID, fileSHA256, String(range.lowerBound), String(range.upperBound)]
            let pages = try query("SELECT page FROM structure_pages WHERE book_id=? AND file_sha256=? AND page BETWEEN ? AND ? AND state='candidate' ORDER BY page", args).compactMap { Int($0["page"]!) }
            _ = try query("UPDATE structure_pages SET state='accepted',decided=? WHERE book_id=? AND file_sha256=? AND page BETWEEN ? AND ? AND state='candidate'", [String(Date().timeIntervalSince1970)] + args)
            return pages
        }
    }
    public func hasAcceptedStructure(bookID: String) throws -> Bool {
        !(try query("SELECT 1 FROM structure_pages WHERE book_id=? AND state='accepted' LIMIT 1", [bookID])).isEmpty
    }
    public func acceptedStructureMarkdown(bookID: String, fileSHA256: String) throws -> [Int: String] {
        Dictionary(uniqueKeysWithValues: try query("SELECT page,markdown FROM structure_pages WHERE book_id=? AND file_sha256=? AND state='accepted'", [bookID, fileSHA256]).map { (Int($0["page"]!)!, $0["markdown"]!) })
    }
    public func structureVersions(bookID: String) throws -> [StructureVersionSummary] {
        try query("SELECT file_sha256,COUNT(*) AS pages,SUM(state='accepted') AS accepted FROM structure_pages WHERE book_id=? GROUP BY file_sha256 ORDER BY MAX(created) DESC", [bookID]).map {
            StructureVersionSummary(fileSHA256: $0["file_sha256"]!, pages: Int($0["pages"]!) ?? 0, accepted: Int($0["accepted"] ?? "0") ?? 0)
        }
    }
    /// Removes unaccepted rows written by a run whose source changed underneath it.
    func deleteStructurePages(bookID: String, fileSHA256: String, pages: [Int]) throws {
        try readingTransaction {
            for page in pages { _ = try query("DELETE FROM structure_pages WHERE book_id=? AND file_sha256=? AND page=? AND state<>'accepted'", [bookID, fileSHA256, String(page)]) }
        }
    }
}
