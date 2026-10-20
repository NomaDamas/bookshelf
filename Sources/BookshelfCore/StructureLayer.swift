import Foundation

/// Page structure from a document VLM: Markdown with tables and LaTeX formulas plus block positions.
/// Results belong to one PDF file version (book ID + file SHA-256 + page). The text layer stays
/// the source for search and selection; only accepted pages reach Pi.
public enum StructureState: String, Codable, Sendable, CaseIterable {
    case candidate, accepted, needsReview = "needs_review"
}

public struct StructureBlock: Codable, Sendable, Equatable {
    /// PaddleOCR-VL layout label, such as `text`, `table`, `display_formula`, `formula_number`, `header` or `footer`.
    public var type: String
    /// `[x, y, width, height]` in PDF points from the lower-left corner of the crop box, in unrotated page space.
    public var bbox: [Double]
    public var markdown: String?
    public var latex: String?
    public var text: String?
    /// A formula number that was also written into its formula's Markdown as `\tag`.
    public var inMarkdown: Bool?
    public init(type: String, bbox: [Double], markdown: String? = nil, latex: String? = nil, text: String? = nil, inMarkdown: Bool? = nil) {
        self.type = type; self.bbox = bbox; self.markdown = markdown; self.latex = latex; self.text = text; self.inMarkdown = inMarkdown
    }
}

public struct StructureGeometry: Codable, Sendable, Equatable {
    /// Crop box in PDF page space, `[x, y, width, height]`. Add its origin to a block's bbox to get page coordinates.
    public var cropBox: [Double]
    public var rotation: Int
    public var renderDPI: Double
    public var imageSize: [Int]
    public init(cropBox: [Double], rotation: Int, renderDPI: Double, imageSize: [Int]) {
        self.cropBox = cropBox; self.rotation = rotation; self.renderDPI = renderDPI; self.imageSize = imageSize
    }
}

public struct StructureEngineInfo: Codable, Sendable, Equatable {
    public var engine: String
    public var engineVersion: String
    public var paddlexVersion: String?
    public var model: String
    public var layoutModel: String
    public var server: String
    public var serverVersion: String
    public var concurrency: Int
    public init(engine: String, engineVersion: String, paddlexVersion: String? = nil, model: String, layoutModel: String, server: String, serverVersion: String, concurrency: Int) {
        self.engine = engine; self.engineVersion = engineVersion; self.paddlexVersion = paddlexVersion; self.model = model
        self.layoutModel = layoutModel; self.server = server; self.serverVersion = serverVersion; self.concurrency = concurrency
    }
}

public struct StructurePage: Codable, Sendable, Equatable {
    public var bookID: String
    public var fileSHA256: String
    public var page: Int
    public var state: StructureState
    public var markdown: String
    public var blocks: [StructureBlock]
    public var engine: StructureEngineInfo
    public var geometry: StructureGeometry
    /// Why the page needs review: repeated text, a token-limit hit or malformed LaTeX.
    public var reasons: [String]
    public var seconds: Double
    public var created: Double
    public var decided: Double?
    public init(bookID: String, fileSHA256: String, page: Int, state: StructureState, markdown: String, blocks: [StructureBlock], engine: StructureEngineInfo,
                geometry: StructureGeometry, reasons: [String] = [], seconds: Double = 0, created: Double = Date().timeIntervalSince1970, decided: Double? = nil) {
        self.bookID = bookID; self.fileSHA256 = fileSHA256; self.page = page; self.state = state; self.markdown = markdown; self.blocks = blocks
        self.engine = engine; self.geometry = geometry; self.reasons = reasons; self.seconds = seconds; self.created = created; self.decided = decided
    }
}

public struct StructureReview: Codable, Sendable, Equatable {
    public var page: Int
    public var reasons: [String]
}

public struct StructureFailure: Codable, Sendable, Equatable {
    public var page: Int
    public var error: String
}

public struct StructureCounts: Codable, Sendable, Equatable {
    public var processed = 0, candidate = 0, needsReview = 0, failed = 0, skipped = 0, keptAccepted = 0
}

public struct StructureRunResult: Codable, Sendable {
    public var bookID: String
    public var fileSHA256: String
    public var firstPage: Int
    public var lastPage: Int
    public var counts = StructureCounts()
    public var candidates: [Int] = []
    public var needsReview: [StructureReview] = []
    public var failed: [StructureFailure] = []
    /// Pages left as they were by `--resume` because they already had a result.
    public var skipped: [Int] = []
    /// Accepted pages are the reader's decision; a new run never replaces them.
    public var keptAccepted: [Int] = []
    public var engine: StructureEngineInfo?
    public var logPath: String?
    public var serverLogPath: String?
    public var seconds: Double = 0
}

public struct StructureAcceptResult: Codable, Sendable {
    public var bookID: String
    public var fileSHA256: String
    public var accepted: [Int]
    public var alreadyAccepted: [Int]
    /// Never accepted directly; run `structure` on the page again.
    public var needsReview: [StructureReview]
    public var missing: [Int]
}

public struct StructurePageSummary: Codable, Sendable {
    public var page: Int
    public var state: StructureState
    public var reasons: [String]
    public var model: String
    public var renderDPI: Double
    public var created: Double
    public var decided: Double?
}

public struct StructureVersionSummary: Codable, Sendable {
    public var fileSHA256: String
    public var pages: Int
    public var accepted: Int
}

public struct StructureStatus: Codable, Sendable {
    public var bookID: String
    public var fileSHA256: String
    public var pageCount: Int
    public var counts: [String: Int]
    public var pages: [StructurePageSummary]
    /// Results stored for other versions of this book's PDF. They are not shown for the current file.
    public var otherVersions: [StructureVersionSummary]
    public var engine: StructureEngineStatus
    /// Markdown and blocks of the pages asked for with `--pages`, for review before acceptance.
    public var results: [StructurePage]?
}

/// Engine paths found from the environment and standard locations, the same way as OCRmyPDF.
public struct StructureEngineStatus: Codable, Sendable, Equatable {
    public var python: String?
    public var server: String?
    public var helper: String?
    public var model: String
    public var engine: StructureEngine? {
        guard let python, let server, let helper else { return nil }
        return StructureEngine(python: URL(fileURLWithPath: python), server: URL(fileURLWithPath: server), helper: URL(fileURLWithPath: helper), model: model)
    }
}

public struct StructureEngine: Sendable, Equatable {
    public static let defaultModel = "PaddlePaddle/PaddleOCR-VL-1.6"
    public var python: URL
    public var server: URL
    public var helper: URL
    public var model: String
    public var dpi: Double
    public init(python: URL, server: URL, helper: URL, model: String = StructureEngine.defaultModel, dpi: Double = 200) {
        self.python = python; self.server = server; self.helper = helper; self.model = model; self.dpi = dpi
    }

    /// `BOOKSIDE_STRUCTURE_PYTHON` is the Python of the PaddleOCR environment; otherwise the `paddleocr`
    /// launcher's shebang names it. `BOOKSIDE_MLX_VLM_SERVER` is the `mlx_vlm.server` executable.
    public static func discover(environment: [String: String] = ProcessInfo.processInfo.environment) -> StructureEngineStatus {
        let fm = FileManager.default
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + [NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        func find(_ name: String) -> String? {
            directories.map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }.first { fm.isExecutableFile(atPath: $0) }
        }
        func explicit(_ key: String) -> String? {
            ProductEnvironment.value(key, in: environment).flatMap { fm.isExecutableFile(atPath: $0) ? $0 : nil }
        }
        var python = explicit("STRUCTURE_PYTHON")
        if python == nil, let launcher = find("paddleocr"), let interpreter = launcherInterpreter(launcher), fm.isExecutableFile(atPath: interpreter) { python = interpreter }
        return StructureEngineStatus(python: python, server: explicit("MLX_VLM_SERVER") ?? find("mlx_vlm.server"),
                                     helper: CoreResources.url(forResource: "structure-pages", withExtension: "py")?.path,
                                     model: ProductEnvironment.value("STRUCTURE_MODEL", in: environment) ?? defaultModel)
    }
}

/// The Python a console-script launcher runs. uv and pip write `#!/bin/sh` plus an `exec` line
/// instead of a direct shebang when the interpreter path is too long for one.
func launcherInterpreter(_ path: String) -> String? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    let lines = String(decoding: (try? handle.read(upToCount: 8192)) ?? Data(), as: UTF8.self).components(separatedBy: "\n")
    guard let first = lines.first, first.hasPrefix("#!/") else { return nil }
    if !first.hasSuffix("/sh") { return String(first.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
    let prefix = "'''exec' '"
    guard lines.count > 1, lines[1].hasPrefix(prefix) else { return nil }
    let rest = lines[1].dropFirst(prefix.count)
    return rest.firstIndex(of: "'").map { String(rest[..<$0]) }
}

public enum StructureLayer {
    public static let missingEngine = "표와 수식 인식 엔진(PaddleOCR-VL, mlx-vlm)을 찾지 못했습니다. docs/04-ocr.md의 구조 레이어 설치 안내를 확인하거나 BOOKSIDE_STRUCTURE_PYTHON과 BOOKSIDE_MLX_VLM_SERVER를 지정해 주세요."

    /// `A-B` or `N`, as 1-based PDF page indices inside the document.
    public static func pages(_ text: String, pageCount: Int) throws -> ClosedRange<Int> {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard (1...2).contains(parts.count), let first = parts.first ?? nil, let last = parts.last ?? nil, first >= 1, last >= first else {
            throw ShelfError.message("--pages는 3-8처럼 첫 쪽과 끝 쪽으로 적어 주세요.")
        }
        guard last <= pageCount else { throw ShelfError.message("페이지는 1~\(pageCount) 범위여야 합니다.") }
        return first...last
    }

    static func pageCount(_ book: Book) throws -> Int {
        try autoreleasepool { try PDFService.document(at: book.url).pageCount }
    }

    /// Accepted Markdown for the book's current file. The file is hashed only when some page was accepted.
    public static func acceptedMarkdown(book: Book, store: LibraryStore) throws -> [Int: String] {
        guard try store.hasAcceptedStructure(bookID: book.id) else { return [:] }
        return try store.acceptedStructureMarkdown(bookID: book.id, fileSHA256: OCRQualityCheck.digest(book.url))
    }

    /// The reader's explicit decision. Only candidates of the current file version are accepted.
    public static func accept(book: Book, pages: ClosedRange<Int>, store: LibraryStore) throws -> StructureAcceptResult {
        let digest = try OCRQualityCheck.digest(book.url)
        let before = Dictionary(uniqueKeysWithValues: try store.structurePages(bookID: book.id, fileSHA256: digest, range: pages).map { ($0.page, $0) })
        let accepted = try store.acceptStructure(bookID: book.id, fileSHA256: digest, range: pages)
        return StructureAcceptResult(bookID: book.id, fileSHA256: digest, accepted: accepted,
                                     alreadyAccepted: pages.filter { before[$0]?.state == .accepted },
                                     needsReview: pages.compactMap { page in before[page].flatMap { $0.state == .needsReview ? StructureReview(page: page, reasons: $0.reasons) : nil } },
                                     missing: pages.filter { before[$0] == nil })
    }

    public static func status(book: Book, store: LibraryStore, engine: StructureEngineStatus = StructureEngine.discover(), results range: ClosedRange<Int>? = nil) throws -> StructureStatus {
        let count = try pageCount(book), digest = try OCRQualityCheck.digest(book.url)
        let pages = try store.structurePages(bookID: book.id, fileSHA256: digest)
        var counts = Dictionary(uniqueKeysWithValues: StructureState.allCases.map { ($0.rawValue, 0) })
        for page in pages { counts[page.state.rawValue, default: 0] += 1 }
        let others = try store.structureVersions(bookID: book.id).filter { $0.fileSHA256 != digest }
        return StructureStatus(bookID: book.id, fileSHA256: digest, pageCount: count, counts: counts,
                               pages: pages.map { StructurePageSummary(page: $0.page, state: $0.state, reasons: $0.reasons, model: $0.engine.model, renderDPI: $0.geometry.renderDPI, created: $0.created, decided: $0.decided) },
                               otherVersions: others, engine: engine, results: range.map { range in pages.filter { range.contains($0.page) } })
    }
}

/// Runs the bundled helper with the PaddleOCR environment's Python. The helper owns the mlx-vlm
/// server's lifetime; each finished page is stored at once, so a stopped run can resume.
public final class StructureService: @unchecked Sendable {
    private let engine: StructureEngine
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    public init(engine: StructureEngine) { self.engine = engine }

    public func cancel() {
        lock.lock(); cancelled = true; let current = process; lock.unlock()
        // The helper turns SIGINT into a clean stop of its server.
        if current?.isRunning == true { current?.interrupt() }
    }
    private var wasCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    private struct Event: Decodable {
        var event: String
        var message: String?
        var page: Int?
        var index: Int?
        var total: Int?
        var seconds: Double?
        var error: String?
        var markdown: String?
        var blocks: [StructureBlock]?
        var reasons: [String]?
        var geometry: StructureGeometry?
        var `protocol`: Int?
    }
    private struct FileStamp: Equatable {
        var size: Int64, modified: Date?, identity: String
        init(_ url: URL) throws {
            let values = try FileManager.default.attributesOfItem(atPath: url.path)
            size = (values[.size] as? NSNumber)?.int64Value ?? -1; modified = values[.modificationDate] as? Date; identity = FileAccess.identity(url)
        }
    }

    public func run(book: Book, pages: ClosedRange<Int>, resume: Bool = false, store: LibraryStore, progress: @escaping @Sendable (String) -> Void) throws -> StructureRunResult {
        let started = Date()
        guard !wasCancelled else { throw ShelfError.message("구조 인식을 취소했습니다.") }
        guard FileAccess.isResident(book.url) else { throw ShelfError.message("PDF를 iCloud에서 다운로드한 뒤 실행해 주세요.") }
        let pageCount = try StructureLayer.pageCount(book)
        guard pages.lowerBound >= 1, pages.upperBound <= pageCount else { throw ShelfError.message("페이지는 1~\(pageCount) 범위여야 합니다.") }
        let stamp = try FileStamp(book.url), digest = try OCRQualityCheck.digest(book.url)
        var result = StructureRunResult(bookID: book.id, fileSHA256: digest, firstPage: pages.lowerBound, lastPage: pages.upperBound)
        let existing = Dictionary(uniqueKeysWithValues: try store.structurePages(bookID: book.id, fileSHA256: digest, range: pages).map { ($0.page, $0.state) })
        var todo: [Int] = []
        for page in pages {
            switch existing[page] {
            case .accepted?: result.keptAccepted.append(page)
            case .some(_) where resume: result.skipped.append(page)
            default: todo.append(page)
            }
        }
        result.counts.skipped = result.skipped.count; result.counts.keptAccepted = result.keptAccepted.count
        guard !todo.isEmpty else { result.seconds = Date().timeIntervalSince(started); return result }

        lock.lock()
        if process != nil { lock.unlock(); throw ShelfError.message("다른 구조 인식 작업이 실행 중입니다.") }
        let child = Process(); process = child
        lock.unlock()
        defer { lock.lock(); process = nil; lock.unlock() }

        let token = UUID().uuidString
        let logDirectory = store.directory.appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let logURL = logDirectory.appendingPathComponent("structure-\(token).log"), serverLogURL = logDirectory.appendingPathComponent("structure-\(token)-server.log")
        for url in [logURL, serverLogURL] { FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        result.logPath = logURL.path; result.serverLogPath = serverLogURL.path

        child.executableURL = engine.python
        child.arguments = ["-I", engine.helper.path, "run", "--pdf", book.activePath, "--pages", todo.map(String.init).joined(separator: ","),
                           "--server", engine.server.path, "--server-log", serverLogURL.path, "--model", engine.model, "--dpi", String(engine.dpi)]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [engine.server.deletingLastPathComponent().path, environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        // Without this PaddleX probes its model hosts on every start, even with cached models.
        environment["PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK"] = "True"
        child.environment = environment
        let pipe = Pipe(); child.standardOutput = pipe; child.standardError = log
        lock.lock()
        if cancelled { lock.unlock(); throw ShelfError.message("구조 인식을 취소했습니다.") }
        do { try child.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        progress("표와 수식 인식을 준비하고 있습니다. \(todo.count)쪽")

        let wanted = Set(todo)
        var saved: [Int] = [], failure: Error?, helperError: String?, buffer = Data()
        func handle(_ line: Data) throws {
            guard let event = try? JSONDecoder().decode(Event.self, from: line) else { return }
            switch event.event {
            case "status":
                let messages = ["starting the recognition server": "인식 서버를 시작하고 있습니다.", "loading the recognition model": "인식 모델을 불러오고 있습니다."]
                progress(event.message.map { messages[$0] ?? $0 } ?? "")
            case "engine":
                guard event.protocol == 1 else { throw ShelfError.message("구조 인식 도구의 버전이 앱과 맞지 않습니다. 앱을 다시 설치해 주세요.") }
                result.engine = try JSONDecoder().decode(StructureEngineInfo.self, from: line)
                if let info = result.engine { progress("\(info.engine) \(info.engineVersion), \(info.model), \(info.server) \(info.serverVersion) 준비 완료") }
            case "page":
                guard let page = event.page, wanted.contains(page), let markdown = event.markdown, let blocks = event.blocks, let geometry = event.geometry, let info = result.engine else { return }
                guard try FileStamp(book.url) == stamp else { throw ShelfError.message("작업 중 PDF가 바뀌어 구조 인식을 멈췄습니다. 이번 실행의 결과는 저장하지 않았습니다.") }
                let reasons = event.reasons ?? []
                let record = StructurePage(bookID: book.id, fileSHA256: digest, page: page, state: reasons.isEmpty ? .candidate : .needsReview, markdown: markdown,
                                           blocks: blocks, engine: info, geometry: geometry, reasons: reasons, seconds: event.seconds ?? 0)
                guard try store.saveStructurePage(record) else { return }
                saved.append(page)
                if reasons.isEmpty { result.candidates.append(page) } else { result.needsReview.append(StructureReview(page: page, reasons: reasons)) }
                let seconds = String(format: "%.1f", event.seconds ?? 0)
                progress("\(event.index ?? saved.count)/\(event.total ?? todo.count): \(page)쪽 \(seconds)초" + (reasons.isEmpty ? "" : ", 검토 필요(\(reasons.joined(separator: "; ")))"))
            case "page_error":
                if let page = event.page { result.failed.append(StructureFailure(page: page, error: event.error ?? "unknown")) }
                progress("\(event.page ?? 0)쪽을 인식하지 못했습니다.")
            case "error": helperError = event.message
            default: break
            }
            try log.write(contentsOf: Data("[bookside] \(event.event)\(event.page.map { " page \($0)" } ?? "")\n".utf8))
        }
        let reader = pipe.fileHandleForReading
        while true {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline); buffer = Data(buffer.suffix(from: newline + 1))
                // After a failure keep draining, so the helper can stop its server instead of blocking on a full pipe.
                guard failure == nil else { continue }
                do { try handle(Data(line)) } catch { failure = error; child.interrupt() }
            }
        }
        child.waitUntilExit()
        if let failure {
            try? store.deleteStructurePages(bookID: book.id, fileSHA256: digest, pages: saved)
            throw failure
        }
        if wasCancelled {
            throw ShelfError.message("구조 인식을 취소했습니다. 끝난 \(saved.count)쪽은 저장했으니 --resume으로 이어서 실행할 수 있습니다. 로그: \(logURL.path)")
        }
        guard child.terminationStatus == 0 else {
            let tail = (try? String(contentsOf: logURL, encoding: .utf8)).map { String($0.suffix(1500)) } ?? ""
            throw ShelfError.message("표와 수식 인식이 중단되었습니다. 끝난 \(saved.count)쪽은 저장했습니다.\n" + (helperError ?? tail) + "\n로그: \(logURL.path)\n서버 로그: \(serverLogURL.path)")
        }
        guard try OCRQualityCheck.digest(book.url) == digest else {
            try store.deleteStructurePages(bookID: book.id, fileSHA256: digest, pages: saved)
            throw ShelfError.message("작업 중 PDF가 바뀌어 이번 실행의 구조 인식 결과를 저장하지 않았습니다.")
        }
        result.counts.processed = saved.count + result.failed.count
        result.counts.candidate = result.candidates.count; result.counts.needsReview = result.needsReview.count; result.counts.failed = result.failed.count
        result.seconds = Date().timeIntervalSince(started)
        return result
    }
}
