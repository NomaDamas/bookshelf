import Foundation
import BookshelfCore
import MCP

func encoded<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(data: try encoder.encode(value), encoding: .utf8)!
}
func objectJSON(_ value: Any) throws -> String { String(data: try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), encoding: .utf8)! }
func stderr(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }

@main struct BookshelfCLI {
    static func main() async {
        do { try await run() }
        catch { stderr(error.localizedDescription); exit(1) }
    }
    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "help"
        if command == "help" || command == "--help" {
            print("""
            Bookshelf / 서재 (macOS 14+)
            bookshelf-cli import <PDF-or-folder>
            bookshelf-cli books [title]
            bookshelf-cli read <book-id> <PDF-page>
            bookshelf-cli search <book-id> <text>
            bookshelf-cli notes <book-id>
            bookshelf-cli note-set <book-id> <text>
            bookshelf-cli bookmark <book-id> <PDF-page>
            bookshelf-cli position <book-id> <PDF-page>
            bookshelf-cli inspect <book-id>
            bookshelf-cli ocr <book-id> [--language kor|eng|jpn|und] [--output path]
            bookshelf-cli export <book-id>
            bookshelf-cli doctor
            bookshelf-cli mcp

            Data location: BOOKSHELF_DATA_DIR or ~/Library/Application Support/Bookshelf
            MCP exposes only reads. OCR and imports require explicit CLI/app actions.
            """)
            return
        }
        let store = try LibraryStore()
        func argument(_ index: Int) throws -> String { guard args.indices.contains(index) else { throw ShelfError.message("필수 인자가 없습니다. bookshelf-cli --help를 확인해 주세요.") }; return args[index] }
        func pageArgument(_ index: Int) throws -> Int { guard let page = Int(try argument(index)), page > 0 else { throw ShelfError.message("페이지는 양의 정수여야 합니다.") }; return page }
        switch command {
        case "import": print(try encoded(LibraryImporter.add(URL(fileURLWithPath: try argument(1)), to: store)))
        case "books": print(try encoded(store.books(query: args.dropFirst().joined(separator: " "))))
        case "inspect":
            let book = try store.book(argument(1)), result = try PDFService.inspect(book.url)
            try store.updateInspection(bookID: book.id, pageCount: result.pageCount, textPages: result.textPages)
            print(try encoded(result))
        case "read":
            let book = try store.book(argument(1)), page = try pageArgument(2)
            print(try objectJSON(["book_id": book.id, "title": book.title, "page": page, "text": PDFService.readPage(book, page: page), "url": "bookshelf://book/\(book.id)?page=\(page)"]))
        case "search": print(try encoded(PDFService.search(store.book(argument(1)), query: argument(2))))
        case "notes":
            let id = try argument(1)
            print(try objectJSON(["book_id": id, "notebook": JSONSerialization.jsonObject(with: Data(encoded(store.notebook(bookID: id)).utf8)), "highlights": JSONSerialization.jsonObject(with: Data(encoded(store.highlights(bookID: id)).utf8)), "bookmarks": store.bookmarks(bookID: id)]))
        case "note-set":
            let id = try argument(1), old = try store.notebook(bookID: id)
            print(try encoded(store.saveNotebook(bookID: id, body: argument(2), expectedRevision: old.revision)))
        case "bookmark": let id = try argument(1); try store.toggleBookmark(bookID: id, page: pageArgument(2)); print(try encoded(store.bookmarks(bookID: id)))
        case "position": let id = try argument(1); try store.savePosition(bookID: id, page: pageArgument(2)); print(try encoded(store.book(id)))
        case "export": print(try store.exportMarkdown(bookID: argument(1)))
        case "ocr":
            let book = try store.book(argument(1))
            let languageIndex = args.firstIndex(of: "--language"), outputIndex = args.firstIndex(of: "--output")
            let language = try languageIndex.map { try argument($0 + 1) } ?? "kor"
            let output = try outputIndex.map { URL(fileURLWithPath: try argument($0 + 1)) } ?? OCRService.suggestedOutput(for: book)
            let service = OCRService()
            signal(SIGINT, SIG_IGN)
            let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            signalSource.setEventHandler { service.cancel() }; signalSource.resume()
            defer { signalSource.cancel() }
            let result = try await Task.detached { try service.run(book: book, output: output, language: language, store: store, progress: { stderr($0) }) }.value
            print(try encoded(result))
        case "doctor": print(try objectJSON(["data_directory": store.directory.path, "ocrmypdf": OCRService.executable()?.path ?? "not found", "book_count": store.books().count, "version": "0.1.0"]))
        case "mcp": try await runMCP(store: store)
        default: throw ShelfError.message("알 수 없는 명령: \(command)")
        }
    }
}
