import Foundation
import PDFKit
import CryptoKit

public enum OCRMode: String, Codable, Sendable {
    case missingText, replaceText
    public var title: String { self == .replaceText ? "기존 OCR 개선" : "텍스트 인식" }
    public var argument: String { self == .replaceText ? "--redo-ocr" : "--skip-text" }
}

public struct OCRQuality: Codable, Sendable {
    public var pageCount: Int
    public var textPages: Int
    public var substantialTextPages: Int
    public var spacingSuspectPages: [Int]
    public var improvedSpacingPages: [Int]
    public var textLossPages: [Int]
    public var textGrowthPages: [Int]?
    public var changedTextPages: [Int]
    public var extractorDisagreementPages: [Int]
    public var renderedPages: [Int]
    public var renderingChecks: [OCRRenderingCheck]?
    public var popplerChecked: Bool
    public var needsReview: Bool {
        !spacingSuspectPages.isEmpty || !textLossPages.isEmpty || !(textGrowthPages ?? []).isEmpty || !extractorDisagreementPages.isEmpty || !renderingMismatchPages.isEmpty || !popplerChecked
    }
    public var renderingMismatchPages: [Int] { (renderingChecks ?? []).filter { !$0.passed }.map(\.page) }
    public var reviewPages: [Int] {
        Array(Set(spacingSuspectPages + textLossPages + (textGrowthPages ?? []) + extractorDisagreementPages + renderingMismatchPages + renderedPages)).sorted()
    }
}

public struct OCRRenderingCheck: Codable, Sendable {
    public var page: Int
    public var pixels: Int
    public var changedPixels: Int
    public var maximumChannelDifference: Int
    public var passed: Bool
}

public enum OCRQualityCheck {
    public static func compact(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }
    public static func hasExcessSpacing(_ text: String) -> Bool {
        for (pattern, minimum, maximumRun) in [("[가-힣]+", 80, 1.45), ("[A-Za-z]+", 120, 1.6)] {
            let regex = try! NSRegularExpression(pattern: pattern)
            let runs = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range.length)
            let count = runs.reduce(0, +)
            if count >= minimum && Double(count) / Double(runs.count) < maximumRun
                && Double(runs.filter { $0 == 1 }.count) / Double(runs.count) > 0.65 { return true }
        }
        return false
    }
    public static func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func renderedPixels(_ page: PDFPage) throws -> Data {
        guard let ref = page.pageRef else { throw ShelfError.message("검증할 PDF 페이지를 열지 못했습니다.") }
        let box = page.bounds(for: .mediaBox)
        let width = 720, height = max(1, Int(720 * box.height / max(1, box.width)))
        guard height <= 20_000, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ShelfError.message("페이지 화면을 비교할 수 없습니다.")
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect)
        context.concatenate(ref.getDrawingTransform(.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(ref)
        guard let bytes = context.data else { throw ShelfError.message("페이지 화면 비교에 실패했습니다.") }
        return Data(bytes: bytes, count: height * width * 4)
    }
    static func comparePixels(_ before: Data, _ after: Data, page: Int) -> OCRRenderingCheck {
        let count = before.count / 4
        guard before.count == after.count, count > 0 else {
            return OCRRenderingCheck(page: page, pixels: count, changedPixels: count, maximumChannelDifference: 255, passed: false)
        }
        var changed = 0, maximum = 0
        before.withUnsafeBytes { (a: UnsafeRawBufferPointer) in
            after.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
                for offset in stride(from: 0, to: before.count, by: 4) {
                    var difference = 0
                    for channel in 0..<4 { difference = max(difference, abs(Int(a[offset + channel]) - Int(b[offset + channel]))) }
                    if difference > 0 { changed += 1; maximum = max(maximum, difference) }
                }
            }
        }
        // Quartz can round a few edge pixels differently after adding an invisible layer.
        // Permit at most 0.001% of pixels (minimum 4), each within 8/255; report the actual deltas.
        return OCRRenderingCheck(page: page, pixels: count, changedPixels: changed, maximumChannelDifference: maximum,
            passed: maximum <= 8 && changed <= max(4, count / 100_000))
    }
    private static func popplerPages(_ url: URL) -> [String]? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]
        guard let executable = paths.map({ URL(fileURLWithPath: $0).appendingPathComponent("pdftotext") }).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return nil }
        let process = Process(), pipe = Pipe()
        process.executableURL = executable; process.arguments = [url.path, "-"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); timeout.cancel()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        return text.components(separatedBy: "\u{c}")
    }
    public static func compare(source: URL, output: URL, checkCancellation: () throws -> Void = {}) throws -> OCRQuality {
        let before = try PDFService.document(at: source), after = try PDFService.document(at: output)
        _ = try PDFService.validateOCR(source: source, output: output)
        let external = popplerPages(output)
        var report = OCRQuality(pageCount: after.pageCount, textPages: 0, substantialTextPages: 0, spacingSuspectPages: [], improvedSpacingPages: [],
            textLossPages: [], textGrowthPages: [], changedTextPages: [], extractorDisagreementPages: [], renderedPages: [], renderingChecks: [], popplerChecked: external != nil)
        var textPages: [Int] = []
        // Fresh copies every few pages keep text layouts of both PDFs from accumulating (see PDFService.pagesPerDocument).
        var texts = (before: before, after: after)
        for index in 0..<after.pageCount {
            try checkCancellation()
            if index > 0 && index % PDFService.pagesPerDocument == 0 {
                texts = (try PDFService.reopen(source, pageCount: before.pageCount), try PDFService.reopen(output, pageCount: after.pageCount))
            }
            autoreleasepool {
                let a = texts.before.page(at: index)?.string ?? "", b = texts.after.page(at: index)?.string ?? ""
                let old = compact(a), new = compact(b), number = index + 1
                if !new.isEmpty { report.textPages += 1 }
                if new.count >= 30 { textPages.append(number); report.substantialTextPages += 1 }
                if hasExcessSpacing(b) { report.spacingSuspectPages.append(number) }
                else if hasExcessSpacing(a) { report.improvedSpacingPages.append(number) }
                if old.count >= 80 && new.count < old.count * 3 / 4 { report.textLossPages.append(number) }
                if old.count >= 80 && new.count > old.count * 3 / 2 { report.textGrowthPages?.append(number) }
                if old != new { report.changedTextPages.append(number) }
                if let external, (index >= external.count || compact(external[index]) != new) { report.extractorDisagreementPages.append(number) }
            }
        }
        let sample = textPages.isEmpty ? [1] : [textPages[0], textPages[textPages.count / 2], textPages[textPages.count - 1]]
        for number in Set(sample).sorted() {
            try checkCancellation()
            guard let a = before.page(at: number - 1), let b = after.page(at: number - 1) else { throw ShelfError.message("화면 비교 페이지를 열지 못했습니다.") }
            let check = try comparePixels(renderedPixels(a), renderedPixels(b), page: number)
            report.renderingChecks?.append(check)
            if check.passed { report.renderedPages.append(number) }
        }
        return report
    }
}
