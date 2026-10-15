import AppKit
import PDFKit
import Foundation

guard CommandLine.arguments.count > 1 else { fatalError("Pass an output PDF path") }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let count = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 2 : 2
let document = PDFDocument()
for index in 0..<count {
    let image = NSImage(size: NSSize(width: 1200, height: 1600))
    image.lockFocus()
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 1600).fill()
    let title = index == 0 ? "서재 OCR 확인 문서" : "두 번째 페이지와 독서 메모"
    let titleStyle: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 52, weight: .semibold), .foregroundColor: NSColor.black]
    let bodyStyle: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 35), .foregroundColor: NSColor.black]
    (title as NSString).draw(at: NSPoint(x: 100, y: 1370), withAttributes: titleStyle)
    let lines = ["이 문서는 직접 만든 테스트 자료입니다.", "책을 읽고 내 말로 생각을 정리합니다.", "선택한 문장은 발췌 메모에 저장합니다.", "앱을 다시 열어도 메모는 남아 있습니다.", "원본 PDF는 변경하지 않습니다.", "읽던 위치는 각 책에 따로 저장합니다.", "Bookshelf local OCR verification.", "Page \(index + 1)"]
    for (line, text) in lines.enumerated() { (text as NSString).draw(at: NSPoint(x: 100, y: 1210 - line*105), withAttributes: bodyStyle) }
    image.unlockFocus()
    let page = PDFPage(image: image)!
    document.insert(page, at: index)
}
guard document.write(to: output) else { fatalError("Could not write fixture") }
print(output.path)
