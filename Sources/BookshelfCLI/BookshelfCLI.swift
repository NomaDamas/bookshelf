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
        if command == "--version" || command == "version" {
            let product = AppMetadata.current
            print("\(product.name) \(product.version) (build \(product.buildNumber))")
            return
        }
        if command == "help" || command == "--help" {
            print("""
            Bookside (macOS 14+)
            bookside-cli --version
            bookside-cli import <PDF-or-folder>
            bookside-cli books [title]
            bookside-cli read <book-id> <PDF-page>
            bookside-cli search <book-id> <text> [--exact-spacing]
            bookside-cli notes <book-id>
            bookside-cli note-set <book-id> <text>
            bookside-cli bookmark <book-id> <PDF-page>
            bookside-cli position <book-id> <PDF-page>
            bookside-cli inspect <book-id>
            bookside-cli ocr <book-id> [--language kor|eng|jpn|chi_sim|chi_tra|und] [--output path] [--redo] [--review-only]
            bookside-cli ocr-accept <result-json>
            bookside-cli ocr-original <book-id>
            bookside-cli structure <book-id> --pages <first>-<last> [--resume]
            bookside-cli structure-accept <book-id> --pages <first>-<last>
            bookside-cli structure-status <book-id> [--pages <first>-<last>]
            bookside-cli export <book-id>
            bookside-cli doctor
            bookside-cli mcp
            bookside-cli reading-mcp <book-id> <book|page|range> <first-page> <last-page> [provided-page provided-characters]

            Data location: BOOKSIDE_DATA_DIR or ~/Library/Application Support/Bookside
            (an existing Application Support/Bookshelf library is used in place)
            Search ignores OCR whitespace by default. --exact-spacing preserves word spacing.
            MCP exposes only reads. OCR and imports require explicit CLI/app actions.
            structure recognizes tables and formulas as review candidates; only accepted pages reach Pi.
            """)
            return
        }
        let store = try LibraryStore()
        func argument(_ index: Int) throws -> String { guard args.indices.contains(index) else { throw ShelfError.message("필수 인자가 없습니다. bookside-cli --help를 확인해 주세요.") }; return args[index] }
        /// `--pages A-B` plus the flags a command allows, after the book ID.
        func structurePages(_ book: Book, flags: Set<String>) throws -> ClosedRange<Int> {
            let options = Array(args.dropFirst(2))
            guard let index = options.firstIndex(of: "--pages"), options.indices.contains(index + 1) else { throw ShelfError.message("--pages <첫 쪽>-<끝 쪽>이 필요합니다.") }
            var rest = options; rest.removeSubrange(index...(index + 1))
            guard Set(rest).isSubset(of: flags), rest.count == Set(rest).count else { throw ShelfError.message("알 수 없는 옵션입니다. bookside-cli --help를 확인해 주세요.") }
            return try StructureLayer.pages(options[index + 1], pageCount: PDFService.document(at: book.url).pageCount)
        }
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
            print(try objectJSON(["book_id": book.id, "title": book.title, "page": page, "text": PDFService.readPage(book, page: page), "url": "bookside://book/\(book.id)?page=\(page)"]))
        case "search":
            let options = Array(args.dropFirst(3))
            guard options.isEmpty || options == ["--exact-spacing"] else { throw ShelfError.message("검색 옵션은 --exact-spacing만 지원합니다.") }
            print(try encoded(PDFService.search(store.book(argument(1)), query: argument(2), ignoreWhitespace: options.isEmpty)))
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
            let mode: OCRMode = args.contains("--redo") ? .replaceText : .missingText
            let attach = !args.contains("--review-only")
            let result = try await Task.detached { try service.run(book: book, output: output, language: language, store: store, mode: mode, attachResult: attach, progress: { stderr($0) }) }.value
            print(try encoded(result))
        case "ocr-accept":
            let result = try JSONDecoder().decode(OCRResult.self, from: Data(contentsOf: URL(fileURLWithPath: argument(1))))
            try OCRService.accept(result, store: store)
            print(try encoded(store.book(result.bookID)))
        case "ocr-original":
            let id = try argument(1)
            try store.useOriginal(bookID: id)
            print(try encoded(store.book(id)))
        case "structure":
            let book = try store.book(argument(1)), pages = try structurePages(book, flags: ["--resume"])
            guard let engine = StructureEngine.discover().engine else { throw ShelfError.message(StructureLayer.missingEngine) }
            let service = StructureService(engine: engine)
            signal(SIGINT, SIG_IGN)
            let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            signalSource.setEventHandler { service.cancel() }; signalSource.resume()
            defer { signalSource.cancel() }
            let resume = args.contains("--resume")
            let result = try await Task.detached { try service.run(book: book, pages: pages, resume: resume, store: store, progress: { stderr($0) }) }.value
            print(try encoded(result))
        case "structure-accept":
            let book = try store.book(argument(1))
            print(try encoded(StructureLayer.accept(book: book, pages: structurePages(book, flags: []), store: store)))
        case "structure-status":
            let book = try store.book(argument(1))
            print(try encoded(StructureLayer.status(book: book, store: store, results: args.count > 2 ? structurePages(book, flags: []) : nil)))
        case "doctor": print(try objectJSON(["data_directory": store.directory.path, "ocrmypdf": OCRService.executable()?.path ?? "not found", "book_count": store.books().count, "version": AppMetadata.current.version, "build_number": AppMetadata.current.buildNumber, "bundle_identifier": AppMetadata.current.bundleIdentifier]))
        case "mcp": try await runMCP(store: store)
        case "reading-mcp":
            guard args.count == 5 || args.count == 7 else { throw ShelfError.message("독서 연결 인자를 확인해 주세요.") }
            let scope = try BookReadingScope(mode: argument(2), startPage: pageArgument(3), endPage: pageArgument(4))
            let providedPage = args.count == 7 ? Int(args[5]) : nil
            let providedCharacters = args.count == 7 ? (Int(args[6]) ?? -1) : 0
            guard providedCharacters >= 0, providedCharacters <= 10000 else { throw ShelfError.message("현재 페이지 문맥을 확인해 주세요.") }
            try await runBookReadingMCP(store: store, bookID: argument(1), scope: scope, providedPage: providedPage, providedCharacters: providedCharacters)
        default: throw ShelfError.message("알 수 없는 명령: \(command)")
        }
    }
}
