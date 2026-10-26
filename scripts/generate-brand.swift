// Generates Resources/Brand from the Newsreader variable font: the wordmark SVGs, the
// Icon Composer layers, and the GitHub social preview. Outlines are committed, so builds
// do not need the font. Usage: swift scripts/generate-brand.swift <Newsreader[opsz,wght].ttf>
import AppKit
import CoreText

let fontURL = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "")
let outDir = URL(fileURLWithPath: "Resources/Brand", isDirectory: true)
guard let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor])?.first,
      CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String == "Newsreader" else {
    FileHandle.standardError.write("Pass the Newsreader variable font (google/fonts ofl/newsreader).\n".data(using: .utf8)!)
    exit(1)
}
try FileManager.default.createDirectory(at: outDir.appendingPathComponent("AppIcon.icon/Assets"), withIntermediateDirectories: true)

struct RGB {
    let r, g, b: Double
    init(_ hex: Int) { r = Double((hex >> 16) & 0xFF) / 255; g = Double((hex >> 8) & 0xFF) / 255; b = Double(hex & 0xFF) / 255 }
    var hex: String { String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    var iconComposer: String { String(format: "srgb:%.5f,%.5f,%.5f,1.00000", r, g, b) }
}
let ink = RGB(0x1E3550), paper = RGB(0xF4EDE0), highlighter = RGB(0xF5C842)

func axis(_ tag: String) -> NSNumber { NSNumber(value: tag.utf8.reduce(0) { ($0 << 8) | Int($1) }) }
func newsreader(size: CGFloat, weight: Double, opticalSize: Double) -> CTFont {
    let variation = [axis("wght"): NSNumber(value: weight), axis("opsz"): NSNumber(value: opticalSize)]
    return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateCopyWithAttributes(descriptor, [kCTFontVariationAttribute: variation] as CFDictionary), size, nil)
}

/// One outline per glyph, y-up, baseline at y = 0.
func glyphPaths(_ text: String, font: CTFont, tracking: CGFloat = 0) -> [CGPath] {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .kern: tracking]))
    var paths: [CGPath] = []
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for (glyph, position) in zip(glyphs, positions) {
            var move = CGAffineTransform(translationX: position.x, y: position.y)
            paths.append(CTFontCreatePathForGlyph(font, glyph, &move) ?? CGMutablePath())
        }
    }
    return paths
}

/// A bookmark ribbon: a rectangle with a V notch cut into its lower edge.
func ribbon(centerX: CGFloat, top: CGFloat, bottom: CGFloat, width: CGFloat) -> CGPath {
    let path = CGMutablePath(), left = centerX - width / 2, right = centerX + width / 2
    path.addLines(between: [CGPoint(x: left, y: top), CGPoint(x: right, y: top), CGPoint(x: right, y: bottom),
                            CGPoint(x: centerX, y: bottom + width * 0.38), CGPoint(x: left, y: bottom)])
    path.closeSubpath()
    return path
}

/// SVG path data for a y-up path placed in a y-down canvas.
func svgPath(_ path: CGPath, canvasHeight: CGFloat) -> String {
    var d = ""
    func point(_ p: CGPoint) -> String { String(format: "%.2f %.2f", p.x, canvasHeight - p.y) }
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: d += "M\(point(points[0]))"
        case .addLineToPoint: d += "L\(point(points[0]))"
        case .addQuadCurveToPoint: d += "Q\(point(points[0])) \(point(points[1]))"
        case .addCurveToPoint: d += "C\(point(points[0])) \(point(points[1])) \(point(points[2]))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

func combined(_ paths: [CGPath]) -> CGPath { let path = CGMutablePath(); paths.forEach { path.addPath($0) }; return path }
func transformed(_ path: CGPath, _ transform: CGAffineTransform) -> CGPath { var t = transform; return path.copy(using: &t)! }

// Wordmark: the dotless i keeps its stem and the ribbon takes the dot's place.
let letters = glyphPaths("Booksıde", font: newsreader(size: 200, weight: 600, opticalSize: 72), tracking: -2)
let ascender = max(letters[3].boundingBoxOfPath.maxY, letters[6].boundingBoxOfPath.maxY)
let xHeight = letters[1].boundingBoxOfPath.maxY
let stemBox = letters[5].boundingBoxOfPath
let stemHits = stride(from: stemBox.minX, through: stemBox.maxX, by: 0.25).filter { letters[5].contains(CGPoint(x: $0, y: xHeight / 2)) }
let stemWidth = stemHits.last! - stemHits.first!
let wordRibbon = ribbon(centerX: (stemHits.first! + stemHits.last!) / 2, top: ascender - 2,
                        bottom: xHeight + (ascender - xHeight) * 0.2, width: stemWidth * 1.3)
let wordLetters = combined(letters)
let wordBox = wordLetters.boundingBoxOfPath.union(wordRibbon.boundingBoxOfPath)

for (name, color) in [("wordmark.svg", ink), ("wordmark-dark.svg", paper)] {
    let pad: CGFloat = 8, width = ceil(wordBox.width + pad * 2), height = ceil(wordBox.height + pad * 2)
    let move = CGAffineTransform(translationX: pad - wordBox.minX, y: pad - wordBox.minY)
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(Int(width)) \(Int(height))" role="img" aria-label="Bookside">
    <path fill="\(color.hex)" d="\(svgPath(transformed(wordLetters, move), canvasHeight: height))"/>
    <path fill="\(highlighter.hex)" d="\(svgPath(transformed(wordRibbon, move), canvasHeight: height))"/>
    </svg>

    """
    try svg.write(to: outDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
}

// App icon: Icon Composer layers on a 1024 pt canvas. The ribbon hangs from the top edge
// beside the letter, like a bookmark left in a book.
let canvas: CGFloat = 1024
let letterGlyph = glyphPaths("B", font: newsreader(size: 700, weight: 600, opticalSize: 72))[0]
let letterGlyphBox = letterGlyph.boundingBoxOfPath
let letterScale = canvas * 0.5 / letterGlyphBox.height
let iconLetter = transformed(letterGlyph, CGAffineTransform(translationX: -letterGlyphBox.midX, y: -letterGlyphBox.midY)
    .concatenating(CGAffineTransform(scaleX: letterScale, y: letterScale))
    .concatenating(CGAffineTransform(translationX: canvas * 0.45, y: canvas * 0.47)))
let iconRibbonWidth = canvas * 0.1
let iconRibbon = ribbon(centerX: iconLetter.boundingBoxOfPath.maxX + canvas * 0.035 + iconRibbonWidth / 2,
                        top: canvas + 40, bottom: canvas * 0.57, width: iconRibbonWidth)
for (name, path, color) in [("letter.svg", iconLetter, paper), ("ribbon.svg", iconRibbon, highlighter)] {
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\"><path fill=\"\(color.hex)\" d=\"\(svgPath(path, canvasHeight: canvas))\"/></svg>\n"
    try svg.write(to: outDir.appendingPathComponent("AppIcon.icon/Assets/\(name)"), atomically: true, encoding: .utf8)
}
// The Dark icon style paints a layer that has no dark fill in the tile color, which left the B
// navy on a near-black tile, so the letter keeps the paper color there.
func layerGroup(_ name: String, translucency: Bool, darkFill: RGB? = nil) -> String {
    let fill = darkFill.map { color in
        """
                  "fill-specializations" : [
                    {
                      "appearance" : "dark",
                      "value" : {
                        "solid" : "\(color.iconComposer)"
                      }
                    }
                  ],

        """
    } ?? ""
    return """
        {
          "layers" : [
            {
    \(fill)          "image-name" : "\(name).svg",
              "name" : "\(name)"
            }
          ],
          "shadow" : {
            "kind" : "neutral",
            "opacity" : 0.5
          },
          "translucency" : {
            "enabled" : \(translucency),
            "value" : 0.3
          }
        }
    """
}
let iconJSON = """
{
  "fill" : {
    "solid" : "\(ink.iconComposer)"
  },
  "groups" : [
\(layerGroup("ribbon", translucency: false)),
\(layerGroup("letter", translucency: true, darkFill: paper))
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}

"""
try iconJSON.write(to: outDir.appendingPathComponent("AppIcon.icon/icon.json"), atomically: true, encoding: .utf8)

// Social preview at GitHub's recommended 1280 x 640.
let preview = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 640, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: preview)
let cg = NSGraphicsContext.current!.cgContext
cg.setFillColor(paper.cg); cg.fill(CGRect(x: 0, y: 0, width: 1280, height: 640))
let previewScale = 720 / wordBox.width
let place = CGAffineTransform(translationX: -wordBox.midX, y: -wordBox.minY)
    .concatenating(CGAffineTransform(scaleX: previewScale, y: previewScale))
    .concatenating(CGAffineTransform(translationX: 640, y: 300))
cg.addPath(transformed(wordLetters, place)); cg.setFillColor(ink.cg); cg.fillPath()
cg.addPath(transformed(wordRibbon, place)); cg.setFillColor(highlighter.cg); cg.fillPath()
let tagline = CTLineCreateWithAttributedString(NSAttributedString(string: "Read your PDFs. Keep your thoughts beside them.", attributes: [
    .font: newsreader(size: 38, weight: 400, opticalSize: 16), .foregroundColor: NSColor(cgColor: ink.cg)!.withAlphaComponent(0.78),
]))
cg.textPosition = CGPoint(x: 640 - CTLineGetTypographicBounds(tagline, nil, nil, nil) / 2, y: 210)
CTLineDraw(tagline, cg)
NSGraphicsContext.current = nil
try preview.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("social-preview.png"))

let version = CTFontCopyName(newsreader(size: 12, weight: 400, opticalSize: 16), kCTFontVersionNameKey) as String? ?? "unknown"
print("Wrote \(outDir.path) from Newsreader \(version)")
