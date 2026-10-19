import Foundation

public struct OCRResult: Codable, Sendable {
    public var bookID: String
    public var path: String
    public var sourcePath: String
    public var sourceSHA256: String
    public var outputSHA256: String
    public var mode: OCRMode
    public var inspection: PDFInspection
    public var quality: OCRQuality
    public var logPath: String
    public var reportPath: String
}

public final class OCRService: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    public init() {}

    public static func executable() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let explicit = ProductEnvironment.value("OCRMYPDF", in: env), FileManager.default.isExecutableFile(atPath: explicit) { return URL(fileURLWithPath: explicit) }
        let directories = (env["PATH"] ?? "").split(separator: ":").map(String.init) + [NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        return directories.map { URL(fileURLWithPath: $0).appendingPathComponent("ocrmypdf") }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    public static func suggestedOutput(for book: Book) -> URL {
        let baseURL = URL(fileURLWithPath: book.sourcePath).deletingPathExtension()
        var stem = baseURL.lastPathComponent
        if stem.hasSuffix("_ocr") { stem = String(stem.dropLast(4)) }
        let parent = baseURL.deletingLastPathComponent()
        var number = 1
        while true {
            let suffix = number == 1 ? "_ocr.pdf" : "_\(number)_ocr.pdf"
            let candidate = parent.appendingPathComponent(stem + suffix)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }
    public func cancel() {
        lock.lock(); cancelled = true; let current = process; lock.unlock()
        // OCRmyPDF handles SIGINT by shutting down its page workers.
        if current?.isRunning == true { current?.interrupt() }
    }
    public var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return process?.isRunning == true }

    private func checkCancellation() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw ShelfError.cancelled }
    }
    private func prepareReplacement(source: URL, output: URL, ocrExecutable: URL, log: FileHandle) throws {
        guard let script = CoreResources.url(forResource: "prepare-ocr-replacement", withExtension: "py") else {
            throw ShelfError.message("OCR 개선 도구가 앱에 없습니다. 앱을 다시 설치해 주세요.")
        }
        let handle = try FileHandle(forReadingFrom: ocrExecutable); defer { try? handle.close() }
        let header = String(decoding: try handle.read(upToCount: 4096) ?? Data(), as: UTF8.self).components(separatedBy: "\n")[0]
        let interpreter = ProductEnvironment.value("OCR_PYTHON") ?? (header.hasPrefix("#!/") ? String(header.dropFirst(2)) : "")
        guard FileManager.default.isExecutableFile(atPath: interpreter) else {
            throw ShelfError.message("OCRmyPDF의 Python 실행 환경을 확인할 수 없습니다. BOOKSIDE_OCR_PYTHON을 지정해 주세요.")
        }
        let helper = Process(), pipe = Pipe()
        helper.executableURL = URL(fileURLWithPath: interpreter)
        helper.arguments = [script.path, source.path, output.path]
        helper.standardOutput = pipe; helper.standardError = pipe
        lock.lock()
        if cancelled { lock.unlock(); throw ShelfError.cancelled }
        process = helper
        do { try helper.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); try log.write(contentsOf: data)
        helper.waitUntilExit(); try checkCancellation()
        guard helper.terminationStatus == 0 else {
            throw ShelfError.message("기존 OCR 레이어를 안전하게 준비하지 못했습니다.\n" + String(decoding: data.suffix(1500), as: UTF8.self))
        }
    }
    public static func accept(_ result: OCRResult, store: LibraryStore) throws {
        let book = try store.book(result.bookID)
        guard book.activePath == result.sourcePath,
              try OCRQualityCheck.digest(book.url) == result.sourceSHA256,
              try OCRQualityCheck.digest(URL(fileURLWithPath: result.path)) == result.outputSHA256 else {
            throw ShelfError.message("검토 중 PDF가 변경되었습니다. 기존 책을 유지했으니 다시 인식해 주세요.")
        }
        try store.attachOCR(bookID: book.id, url: URL(fileURLWithPath: result.path), pageCount: result.inspection.pageCount, textPages: result.inspection.textPages, expectedSourcePath: result.sourcePath)
    }
    public func run(book: Book, output: URL, language: String, store: LibraryStore, mode: OCRMode = .missingText, attachResult: Bool = true, progress: @escaping @Sendable (String) -> Void) throws -> OCRResult {
        try checkCancellation()
        guard ["kor", "eng", "jpn", "chi_sim", "chi_tra", "und"].contains(language) else { throw ShelfError.message("지원하는 OCR 언어를 선택해 주세요.") }
        guard let binary = Self.executable() else { throw ShelfError.message("OCRmyPDF와 AppleOCR가 필요합니다. 설정의 OCR 설치 안내를 확인해 주세요.") }
        guard FileAccess.isResident(book.url) else { throw ShelfError.message("PDF를 iCloud에서 다운로드한 뒤 실행해 주세요.") }
        guard output.pathExtension.lowercased() == "pdf", !FileManager.default.fileExists(atPath: output.path), FileAccess.canonicalPath(output) != FileAccess.canonicalPath(book.url) else { throw ShelfError.message("원본이나 기존 파일을 덮어쓸 수 없습니다. 새 PDF 파일 이름을 선택해 주세요.") }
        lock.lock()
        if process != nil { lock.unlock(); throw ShelfError.message("다른 OCR 작업이 실행 중입니다.") }
        let child = Process(); process = child
        lock.unlock()
        defer { lock.lock(); process = nil; lock.unlock() }
        try checkCancellation()
        let sourceDigest = try OCRQualityCheck.digest(book.url)
        try checkCancellation()
        let token = UUID().uuidString
        let temp = output.deletingLastPathComponent().appendingPathComponent(".bookside-\(token).partial.pdf")
        let prepared = output.deletingLastPathComponent().appendingPathComponent(".bookside-\(token).prepared.pdf")
        let logDirectory = store.directory.appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let logURL = logDirectory.appendingPathComponent("ocr-\(token).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let log = try FileHandle(forWritingTo: logURL)
        defer {
            try? log.close()
            if FileManager.default.fileExists(atPath: temp.path) { try? FileManager.default.removeItem(at: temp) }
            if FileManager.default.fileExists(atPath: prepared.path) { try? FileManager.default.removeItem(at: prepared) }
            lock.lock(); process = nil; lock.unlock()
        }
        if mode == .replaceText {
            progress("기존 OCR 레이어를 사본에서 정리하고 있습니다.")
            try prepareReplacement(source: book.url, output: prepared, ocrExecutable: binary, log: log)
        }
        child.executableURL = binary
        child.arguments = ["--ocr-engine", "appleocr", "--appleocr-recognition-mode", "accurate", "--pdf-renderer", "sandwich", "--output-type", "pdf", "--optimize", "0", "--no-overwrite", mode.argument, "--jobs", "2", "-l", language, mode == .replaceText ? prepared.path : book.activePath, temp.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [binary.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        child.environment = environment
        let pipe = Pipe(); child.standardError = pipe; child.standardOutput = pipe
        lock.lock()
        if cancelled { lock.unlock(); throw ShelfError.cancelled }
        process = child
        do { try child.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        progress("Mac에서 텍스트를 인식하고 있습니다.")
        // Drain both output streams while the worker is running so a full pipe cannot deadlock it.
        var tail = ""
        while true {
            let bytes = pipe.fileHandleForReading.availableData
            if bytes.isEmpty { break }
            try log.write(contentsOf: bytes)
            let text = String(decoding: bytes, as: UTF8.self)
            tail = String((tail + text).suffix(5000))
            if let line = text.split(whereSeparator: \.isNewline).last { progress(String(line).trimmingCharacters(in: .whitespaces)) }
        }
        child.waitUntilExit()
        lock.lock(); let wasCancelled = cancelled; lock.unlock()
        if wasCancelled { throw ShelfError.cancelled }
        guard child.terminationStatus == 0 else { throw ShelfError.message("텍스트 인식에 실패했습니다.\n" + String(tail.suffix(1500)) + "\n로그: " + logURL.path) }
        progress("페이지와 텍스트를 확인하고 있습니다.")
        let inspection = try PDFService.validateOCR(source: book.url, output: temp)
        progress("공백, 읽는 순서와 페이지 화면을 확인하고 있습니다.")
        let quality = try OCRQualityCheck.compare(source: book.url, output: temp, checkCancellation: checkCancellation)
        try checkCancellation()
        guard try OCRQualityCheck.digest(book.url) == sourceDigest else { throw ShelfError.message("작업 중 원본 PDF가 변경되어 결과를 연결하지 않았습니다.") }
        let reportURL = logDirectory.appendingPathComponent("ocr-\(token)-result.json")
        // Withhold the candidate before it becomes visible to a concurrent folder rescan.
        try store.holdOCRCandidate(bookID: book.id, url: output, report: reportURL)
        // moveItem fails if another process created the destination. The original is never replaced.
        try FileManager.default.moveItem(at: temp, to: output)
        let result = OCRResult(bookID: book.id, path: output.path, sourcePath: book.activePath, sourceSHA256: sourceDigest,
            outputSHA256: try OCRQualityCheck.digest(output), mode: mode, inspection: inspection, quality: quality, logPath: logURL.path, reportPath: reportURL.path)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: reportURL, options: .atomic)
        if attachResult {
            guard !quality.needsReview else { throw ShelfError.message("검토할 페이지가 있어 자동으로 연결하지 않았습니다. 결과: \(output.path)\n검사 기록: \(reportURL.path)") }
            try Self.accept(result, store: store)
        }
        return result
    }
}
