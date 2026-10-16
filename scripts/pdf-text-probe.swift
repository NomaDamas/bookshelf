import Foundation
import PDFKit

guard CommandLine.arguments.count >= 2 else { fatalError("Usage: pdf-text-probe <pdf> [pages]") }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let pdf = PDFDocument(url: url), !pdf.isLocked else { fatalError("Unreadable or locked PDF") }
let count = pdf.pageCount
let requested = CommandLine.arguments.count > 2
    ? (CommandLine.arguments[2] == "all" ? Array(1..<(count + 1)) : CommandLine.arguments[2].split(separator: ",").compactMap { Int($0) })
    : [min(10, count), max(1, count / 2), max(1, count - 10)]
let pages: [[String: Any]] = Set(requested).sorted().filter { $0 > 0 && $0 <= count }.compactMap { number in
    guard let page = pdf.page(at: number - 1) else { return nil }
    let bounds = page.bounds(for: .mediaBox)
    return ["page": number, "text": page.string ?? "", "width": bounds.width, "height": bounds.height, "rotation": page.rotation]
}
let attributes = pdf.documentAttributes ?? [:]
let result: [String: Any] = [
    "path": url.path, "page_count": count,
    "creator": attributes[PDFDocumentAttribute.creatorAttribute] as? String ?? "",
    "producer": attributes[PDFDocumentAttribute.producerAttribute] as? String ?? "",
    "pages": pages,
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes])
FileHandle.standardOutput.write(data)
