import Foundation

public struct OCRResult: Codable, Sendable {
    public var path: String
    public var inspection: PDFInspection
    public var logPath: String
}

public final class OCRService: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    public init() {}

    public static func executable() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["BOOKSHELF_OCRMYPDF"], FileManager.default.isExecutableFile(atPath: explicit) { return URL(fileURLWithPath: explicit) }
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

    public func run(book: Book, output: URL, language: String, store: LibraryStore, progress: @escaping @Sendable (String) -> Void) throws -> OCRResult {
        guard ["kor", "eng", "jpn", "chi_sim", "chi_tra", "und"].contains(language) else { throw ShelfError.message("지원하는 OCR 언어를 선택해 주세요.") }
        guard let binary = Self.executable() else { throw ShelfError.message("OCRmyPDF와 AppleOCR가 필요합니다. 설정의 OCR 설치 안내를 확인해 주세요.") }
        guard FileAccess.isResident(book.url) else { throw ShelfError.message("PDF를 iCloud에서 다운로드한 뒤 실행해 주세요.") }
        guard output.pathExtension.lowercased() == "pdf", !FileManager.default.fileExists(atPath: output.path), FileAccess.canonicalPath(output) != FileAccess.canonicalPath(book.url) else { throw ShelfError.message("원본이나 기존 파일을 덮어쓸 수 없습니다. 새 PDF 파일 이름을 선택해 주세요.") }
        lock.lock()
        if process != nil { lock.unlock(); throw ShelfError.message("다른 OCR 작업이 실행 중입니다.") }
        cancelled = false
        let child = Process(); process = child
        lock.unlock()
        defer { lock.lock(); process = nil; lock.unlock() }
        let token = UUID().uuidString
        let temp = output.deletingLastPathComponent().appendingPathComponent(".bookshelf-\(token).partial.pdf")
        let logDirectory = store.directory.appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let logURL = logDirectory.appendingPathComponent("ocr-\(token).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let log = try FileHandle(forWritingTo: logURL)
        defer {
            try? log.close()
            if FileManager.default.fileExists(atPath: temp.path) { try? FileManager.default.removeItem(at: temp) }
            lock.lock(); process = nil; lock.unlock()
        }
        child.executableURL = binary
        child.arguments = ["--ocr-engine", "appleocr", "--appleocr-recognition-mode", "accurate", "--pdf-renderer", "sandwich", "--output-type", "pdf", "--optimize", "0", "--skip-text", "--jobs", "2", "-l", language, book.activePath, temp.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [binary.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        child.environment = environment
        let pipe = Pipe(); child.standardError = pipe; child.standardOutput = pipe
        try child.run()
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
        // moveItem fails if another process created the destination. The original is never replaced.
        try FileManager.default.moveItem(at: temp, to: output)
        try store.attachOCR(bookID: book.id, url: output, pageCount: inspection.pageCount, textPages: inspection.textPages)
        return OCRResult(path: output.path, inspection: inspection, logPath: logURL.path)
    }
}
