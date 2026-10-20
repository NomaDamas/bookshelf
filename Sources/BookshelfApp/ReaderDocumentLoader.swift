import Foundation
import PDFKit
import BookshelfCore
import Darwin

/// File replacement, in-place edits and OCR version switches make the open
/// document and the inspection cache stale without hashing hundreds of megabytes.
struct PDFFileVersion: Codable, Equatable, Sendable {
    let path: String
    let device: Int32
    let inode: UInt64
    let bytes: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(_ url: URL) throws {
        var info = stat()
        guard url.path.withCString({ stat($0, &info) }) == 0 else {
            throw ShelfError.message("PDF 파일 정보를 읽지 못했습니다.")
        }
        path = FileAccess.canonicalPath(url)
        device = info.st_dev; inode = info.st_ino; bytes = info.st_size
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
        changedSeconds = Int64(info.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(info.st_ctimespec.tv_nsec)
    }
}

struct OpenedPDF {
    let document: PDFDocument
    let version: PDFFileVersion
    let pageCount: Int
}

/// Opens a reading document off the main thread. Only the active book keeps its document (`AppModel.document`):
/// CoreGraphics keeps the fonts it loads for every rendered page inside the `PDFDocument` (about 1.4 MB per page
/// for OCRmyPDF output) and has no public way to drop them, so documents reused across book switches held that
/// memory. Returning to a book opens its file again, which costs about 1 ms plus the first page render.
@MainActor enum ReaderDocumentLoader {
    static func load(_ url: URL) async throws -> OpenedPDF {
        try Task.checkCancellation()
        let opened = try await Task.detached(priority: .userInitiated) {
            let version = try PDFFileVersion(url)
            let pdf = try PDFService.document(at: url)
            let pageCount = pdf.pageCount
            guard try PDFFileVersion(url) == version else { throw ShelfError.message("PDF가 변경되었습니다. 다시 열어 주세요.") }
            return OpenedPDF(document: pdf, version: version, pageCount: pageCount)
        }.value
        try Task.checkCancellation()
        return opened
    }
}

struct CachedPDFInspection: Codable {
    let version: PDFFileVersion
    let result: PDFInspection
    static func key(_ bookID: String) -> String { "readerInspection." + bookID }

    static func read(bookID: String, version: PDFFileVersion, store: LibraryStore) -> PDFInspection? {
        guard let text = try? store.setting(key(bookID)),
              let cached = try? JSONDecoder().decode(Self.self, from: Data(text.utf8)),
              cached.version == version else { return nil }
        return cached.result
    }
    func save(bookID: String, store: LibraryStore) throws {
        let text = String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
        try store.setSetting(Self.key(bookID), value: text)
    }
}
