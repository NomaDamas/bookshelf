import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let frame = NSRect(x: Double(pixels)*0.07, y: Double(pixels)*0.07, width: Double(pixels)*0.86, height: Double(pixels)*0.86)
        NSColor(calibratedRed: 0.14, green: 0.23, blue: 0.33, alpha: 1).setFill()
        NSBezierPath(roundedRect: frame, xRadius: Double(pixels)*0.19, yRadius: Double(pixels)*0.19).fill()
        let symbol = NSImage(systemSymbolName: "book.pages", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: Double(pixels)*0.49, weight: .light))!
        let tinted = symbol.copy() as! NSImage
        tinted.lockFocus(); NSColor(calibratedWhite: 0.94, alpha: 1).set(); NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop); tinted.unlockFocus()
        tinted.draw(in: NSRect(x: Double(pixels)*0.23, y: Double(pixels)*0.22, width: Double(pixels)*0.54, height: Double(pixels)*0.56))
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
    }
}
