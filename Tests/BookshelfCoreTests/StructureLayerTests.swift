import XCTest
import AppKit
import CoreText
import PDFKit
@testable import BookshelfCore

final class StructureLayerTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bookside-structure-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    /// Authored pages; `table` draws a 3x3 ruled grid on the first page.
    private func makePDF(_ name: String, pages: [[String]], table: [[String]] = []) throws -> URL {
        var box = CGRect(x: 0, y: 0, width: 420, height: 595)
        let url = root.appendingPathComponent(name)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        func draw(_ text: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 11) {
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size)])), context)
        }
        for (index, lines) in pages.enumerated() {
            context.beginPDFPage(nil)
            for (row, line) in lines.enumerated() { draw(line, 40, 540 - CGFloat(row) * 18) }
            if index == 0, !table.isEmpty {
                context.setLineWidth(0.8)
                for (r, cells) in table.enumerated() {
                    for (c, cell) in cells.enumerated() {
                        let rect = CGRect(x: 60 + CGFloat(c) * 100, y: 400 - CGFloat(r + 1) * 26, width: 100, height: 26)
                        context.stroke(rect); draw(cell, rect.minX + 8, rect.minY + 8)
                    }
                }
            }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
    private func script(_ name: String, _ body: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(("#!/bin/sh\n" + body).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
    /// A stand-in for `python -I structure-pages.py run ...` that speaks the helper's line protocol.
    /// Page 2 reports a problem; `after` runs once the given page is printed.
    /// Cancellation relies on the default SIGINT action. bash drops a SIGINT that arrives while it waits for a
    /// foreground command that then exits normally, and a trap could miss one during `&`, so the loop runs only
    /// builtins and the waiting page `exec`s sleep, which SIGINT ends.
    private func fakeEngine(failAfter: Int? = nil, waitAfter: Int? = nil) throws -> StructureEngine {
        let page = #"{"event":"page","page":PAGE,"index":1,"total":1,"seconds":0.1,"geometry":{"cropBox":[0,0,420,595],"rotation":0,"renderDPI":200,"imageSize":[1167,1653]},"markdown":"Page PAGE\n\n<table><tr><td>a</td><td>PAGE</td></tr></table>","blocks":[{"type":"table","bbox":[60,322,200,52],"markdown":"<table><tr><td>a</td><td>PAGE</td></tr></table>"},{"type":"footer","bbox":[40,20,60,10],"text":"PAGE"}],"reasons":REASONS}"#
        let lines = (1...10).map { number in
            let line = page.replacingOccurrences(of: "PAGE", with: String(number)).replacingOccurrences(of: "REASONS", with: number == 2 ? #"["repeated text: abc"]"# : "[]")
            return "    \(number)) printf '%s\\n' '\(line)';;"
        }.joined(separator: "\n")
        let body = """
        pages=""
        while [ $# -gt 0 ]; do case "$1" in --pages) pages="$2"; shift;; esac; shift; done
        echo "library noise on stderr" >&2
        echo '{"event":"status","message":"starting the recognition server"}'
        echo '{"event":"engine","protocol":1,"engine":"PaddleOCR-VL","engineVersion":"test","model":"fake/model","layoutModel":"PP-DocLayoutV3","server":"mlx-vlm","serverVersion":"0.0","concurrency":1}'
        for p in $(echo "$pages" | tr ',' ' '); do
          case "$p" in
        \(lines)
          esac
          \(failAfter.map { "if [ \"$p\" = \"\($0)\" ]; then echo boom >&2; exit 3; fi" } ?? "")
          \(waitAfter.map { "if [ \"$p\" = \"\($0)\" ]; then exec sleep 30; fi" } ?? "")
        done
        echo '{"event":"done"}'
        """
        return StructureEngine(python: try script("fake-engine-\(UUID().uuidString).sh", body), server: URL(fileURLWithPath: "/usr/bin/true"), helper: root.appendingPathComponent("unused.py"), model: "fake/model")
    }
    private func library() throws -> (LibraryStore, Book) {
        let pdf = try makePDF("Book.pdf", pages: [["Page one text layer"], ["Page two text layer"], ["Page three text layer"]])
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        return (store, try store.register(source: pdf, ocr: nil, root: root))
    }
    private func json(_ value: String) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]) }

    func testPageRangesAreOneBasedAndInsideTheDocument() throws {
        XCTAssertEqual(try StructureLayer.pages("3-8", pageCount: 10), 3...8)
        XCTAssertEqual(try StructureLayer.pages("4", pageCount: 10), 4...4)
        for bad in ["0-2", "5-3", "2-x", "", "1-2-3", "9-11"] { XCTAssertThrowsError(try StructureLayer.pages(bad, pageCount: 10), bad) }
    }

    func testDiscoveryFollowsLaunchersAndOverrides() throws {
        let bin = root.appendingPathComponent("bin"), python = try script("python3", "exit 0"), server = try script("mlx_vlm.server", "exit 0")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: server, to: bin.appendingPathComponent("mlx_vlm.server"))
        // uv writes this form when the interpreter path is too long for a shebang line.
        let launcher = bin.appendingPathComponent("paddleocr")
        try Data("#!/bin/sh\n'''exec' '\(python.path)' \"$0\" \"$@\"\n' '''\nimport sys\n".utf8).write(to: launcher)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        let found = StructureEngine.discover(environment: ["PATH": bin.path])
        XCTAssertEqual(found.python, python.path); XCTAssertEqual(found.server, bin.appendingPathComponent("mlx_vlm.server").path)
        XCTAssertEqual(found.model, StructureEngine.defaultModel); XCTAssertNotNil(found.engine)
        try Data("#!\(python.path)\nimport sys\n".utf8).write(to: launcher)
        XCTAssertEqual(StructureEngine.discover(environment: ["PATH": bin.path]).python, python.path)
        let explicit = StructureEngine.discover(environment: ["PATH": "/nonexistent", "BOOKSIDE_STRUCTURE_PYTHON": python.path, "BOOKSIDE_MLX_VLM_SERVER": "/missing", "BOOKSIDE_STRUCTURE_MODEL": "m-4bit"])
        XCTAssertEqual(explicit.python, python.path); XCTAssertEqual(explicit.model, "m-4bit")
        XCTAssertNil(explicit.engine, "a missing server leaves the engine unavailable")
    }

    func testRunStoresCandidatesAndReviewPagesForOneFileVersion() throws {
        let (store, book) = try library()
        let digest = try OCRQualityCheck.digest(book.url)
        let result = try StructureService(engine: fakeEngine()).run(book: book, pages: 1...3, store: store, progress: { _ in })
        XCTAssertEqual(result.candidates, [1, 3]); XCTAssertEqual(result.needsReview, [StructureReview(page: 2, reasons: ["repeated text: abc"])])
        XCTAssertEqual(result.counts.processed, 3); XCTAssertEqual(result.fileSHA256, digest)
        XCTAssertEqual(result.engine?.model, "fake/model")
        XCTAssertTrue(try String(contentsOfFile: XCTUnwrap(result.logPath), encoding: .utf8).contains("library noise on stderr"))
        let pages = try store.structurePages(bookID: book.id, fileSHA256: digest)
        XCTAssertEqual(pages.map(\.state), [.candidate, .needsReview, .candidate])
        XCTAssertEqual(pages[0].blocks.map(\.type), ["table", "footer"]); XCTAssertEqual(pages[0].blocks[0].bbox, [60, 322, 200, 52])
        XCTAssertEqual(pages[0].geometry.renderDPI, 200); XCTAssertEqual(pages[0].engine.serverVersion, "0.0")
        XCTAssertTrue(try store.structurePages(bookID: book.id, fileSHA256: String(repeating: "0", count: 64)).isEmpty)
        let status = try StructureLayer.status(book: book, store: store, engine: StructureEngineStatus(python: nil, server: nil, helper: nil, model: "m"))
        XCTAssertEqual(status.counts, ["candidate": 2, "accepted": 0, "needs_review": 1]); XCTAssertEqual(status.pageCount, 3); XCTAssertNil(status.results)
        let detail = try StructureLayer.status(book: book, store: store, engine: status.engine, results: 2...3)
        XCTAssertEqual(detail.results?.map(\.page), [2, 3]); XCTAssertEqual(detail.results?.first?.reasons, ["repeated text: abc"])
    }

    func testAcceptanceRulesAndRerunsKeepTheReadersDecision() throws {
        let (store, book) = try library()
        let engine = try fakeEngine()
        _ = try StructureService(engine: engine).run(book: book, pages: 1...3, store: store, progress: { _ in })
        XCTAssertTrue(try StructureLayer.acceptedMarkdown(book: book, store: store).isEmpty, "candidates must not reach Pi")
        let accepted = try StructureLayer.accept(book: book, pages: 1...3, store: store)
        XCTAssertEqual(accepted.accepted, [1, 3]); XCTAssertEqual(accepted.needsReview.map(\.page), [2]); XCTAssertEqual(accepted.missing, [])
        XCTAssertEqual(try StructureLayer.accept(book: book, pages: 1...1, store: store).alreadyAccepted, [1])
        XCTAssertEqual(Set(try StructureLayer.acceptedMarkdown(book: book, store: store).keys), [1, 3])

        let rerun = try StructureService(engine: engine).run(book: book, pages: 1...3, store: store, progress: { _ in })
        XCTAssertEqual(rerun.keptAccepted, [1, 3]); XCTAssertEqual(rerun.needsReview.map(\.page), [2])
        let resumed = try StructureService(engine: engine).run(book: book, pages: 1...3, resume: true, store: store, progress: { _ in })
        XCTAssertEqual(resumed.skipped, [2]); XCTAssertEqual(resumed.keptAccepted, [1, 3]); XCTAssertNil(resumed.logPath, "nothing left to run")

        let digest = try OCRQualityCheck.digest(book.url)
        var page = try XCTUnwrap(store.structurePages(bookID: book.id, fileSHA256: digest, range: 1...1).first)
        page.state = .candidate; page.markdown = "replacement"
        XCTAssertFalse(try store.saveStructurePage(page)); page.state = .accepted
        XCTAssertThrowsError(try store.saveStructurePage(page))
        XCTAssertEqual(try store.structurePages(bookID: book.id, fileSHA256: digest, range: 1...1).first?.markdown, "Page 1\n\n<table><tr><td>a</td><td>1</td></tr></table>")
    }

    func testVersionSwitchShowsOnlyThatFilesResults() throws {
        let (store, book) = try library()
        _ = try StructureService(engine: fakeEngine()).run(book: book, pages: 1...1, store: store, progress: { _ in })
        _ = try StructureLayer.accept(book: book, pages: 1...1, store: store)
        let original = try OCRQualityCheck.digest(book.url)
        let ocr = try makePDF("Book_ocr.pdf", pages: [["Page one OCR layer"], ["Page two OCR layer"], ["Page three OCR layer"]])
        try store.attachOCR(bookID: book.id, url: ocr, pageCount: 3, textPages: 3)
        let switched = try store.book(book.id)
        XCTAssertTrue(try StructureLayer.acceptedMarkdown(book: switched, store: store).isEmpty)
        let status = try StructureLayer.status(book: switched, store: store)
        XCTAssertEqual(status.pages.count, 0); XCTAssertEqual(status.otherVersions.map(\.fileSHA256), [original]); XCTAssertEqual(status.otherVersions.first?.accepted, 1)
        XCTAssertEqual(try StructureLayer.accept(book: switched, pages: 1...1, store: store).missing, [1])
        try store.useOriginal(bookID: book.id)
        XCTAssertEqual(Array(try StructureLayer.acceptedMarkdown(book: store.book(book.id), store: store).keys), [1])
    }

    func testFailedRunKeepsFinishedPagesForResume() throws {
        let (store, book) = try library()
        XCTAssertThrowsError(try StructureService(engine: fakeEngine(failAfter: 1)).run(book: book, pages: 1...3, store: store, progress: { _ in })) { error in
            XCTAssertTrue(error.localizedDescription.contains("끝난 1쪽"), error.localizedDescription)
        }
        let digest = try OCRQualityCheck.digest(book.url)
        XCTAssertEqual(try store.structurePages(bookID: book.id, fileSHA256: digest).map(\.page), [1])
        let resumed = try StructureService(engine: fakeEngine()).run(book: book, pages: 1...3, resume: true, store: store, progress: { _ in })
        XCTAssertEqual(resumed.skipped, [1]); XCTAssertEqual(resumed.candidates, [3]); XCTAssertEqual(resumed.needsReview.map(\.page), [2])
    }

    func testCancelStopsTheHelperAndKeepsFinishedPages() throws {
        let (store, book) = try library()
        let service = StructureService(engine: try fakeEngine(waitAfter: 1))
        let finished = expectation(description: "run ended")
        DispatchQueue.global().async {
            do {
                _ = try service.run(book: book, pages: 1...3, store: store, progress: { line in if line.hasPrefix("1/") { service.cancel() } })
                XCTFail("Expected cancellation")
            } catch { XCTAssertTrue(error.localizedDescription.contains("취소"), error.localizedDescription) }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 20)
        XCTAssertEqual(try store.structurePages(bookID: book.id, fileSHA256: OCRQualityCheck.digest(book.url)).map(\.page), [1])
    }

    func testReadPagesServesAcceptedStructureWithItsSource() async throws {
        let (store, book) = try library()
        _ = try StructureService(engine: fakeEngine()).run(book: book, pages: 1...3, store: store, progress: { _ in })
        _ = try StructureLayer.accept(book: book, pages: 1...3, store: store)
        let structure = try StructureLayer.acceptedMarkdown(book: book, store: store)
        let session = try BookReadingSession(book: book, scope: .init(mode: "book", startPage: 1, endPage: 3), providedPage: 1, providedCharacters: 19, structure: structure)
        let before = try json(await session.call("get_reading_coverage"))
        XCTAssertEqual((before["reading"] as? [String: Any])?["readPages"] as? [Int], [], "the prompt carried the text layer, not the structure")
        let read = try json(await session.call("read_pages", startPage: 1, endPage: 3))
        let pages = try XCTUnwrap(read["pages"] as? [[String: Any]])
        XCTAssertEqual(pages.map { $0["source"] as? String }, ["structure", "text_layer", "structure"])
        XCTAssertEqual(pages[0]["text"] as? String, "Page 1\n\n<table><tr><td>a</td><td>1</td></tr></table>")
        XCTAssertTrue((pages[1]["text"] as? String ?? "").contains("Page two text layer"), "needs_review pages never reach Pi")
        XCTAssertEqual((read["reading"] as? [String: Any])?["readPages"] as? [Int], [1, 2, 3])
        let search = try json(await session.call("search_book", query: "Page one"))
        XCTAssertEqual((search["matches"] as? [[String: Any]])?.first?["page"] as? Int, 1, "search keeps using the text layer")
        let ranged = try BookReadingSession(book: book, scope: .init(mode: "range", startPage: 2, endPage: 3), structure: structure)
        let inside = try json(await ranged.call("read_pages", startPage: 3))
        XCTAssertEqual((inside["pages"] as? [[String: Any]])?.first?["source"] as? String, "structure")
    }

    func testSchemaMigrationSurvivesAnOlderBuildOpeningTheLibrary() throws {
        let (store, book) = try library()
        _ = try StructureService(engine: fakeEngine()).run(book: book, pages: 1...1, store: store, progress: { _ in })
        let database = store.databaseURL.path
        func sqlite(_ sql: String) throws -> String {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3"); process.arguments = [database, sql]; process.standardOutput = pipe
            try process.run(); process.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        XCTAssertEqual(try sqlite("PRAGMA user_version"), "2")
        // Builds before version 2 run `PRAGMA user_version=1` on every open and never touch the new table.
        XCTAssertEqual(try sqlite("PRAGMA user_version=1; PRAGMA user_version"), "1")
        let reopened = try LibraryStore(directory: store.directory)
        XCTAssertEqual(try sqlite("PRAGMA user_version"), "2")
        XCTAssertEqual(try reopened.structurePages(bookID: book.id, fileSHA256: OCRQualityCheck.digest(book.url)).map(\.page), [1])
        // A version 1 library gains the table.
        XCTAssertEqual(try sqlite("DROP TABLE structure_pages; PRAGMA user_version=1; PRAGMA user_version"), "1")
        let upgraded = try LibraryStore(directory: store.directory)
        XCTAssertEqual(try sqlite("PRAGMA user_version"), "2")
        XCTAssertTrue(try upgraded.structurePages(bookID: book.id, fileSHA256: "x").isEmpty)
        XCTAssertEqual(try upgraded.book(book.id).id, book.id)
    }

    /// The bundled helper's conversion runs with any Python 3.9+, without the engine.
    func testHelperConvertsPaddleOutputToPageRecords() throws {
        guard let python = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw XCTSkip("python3 not installed") }
        let helper = try XCTUnwrap(CoreResources.url(forResource: "structure-pages", withExtension: "py"))
        func convert(_ result: [String: Any], _ markdown: String, geometry: [String: Any], hits: Int = 0) throws -> [String: Any] {
            let resultURL = root.appendingPathComponent(UUID().uuidString + ".json"), markdownURL = root.appendingPathComponent(UUID().uuidString + ".md")
            try JSONSerialization.data(withJSONObject: result).write(to: resultURL); try Data(markdown.utf8).write(to: markdownURL)
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = ["-I", helper.path, "convert", "--result", resultURL.path, "--markdown", markdownURL.path,
                                 "--geometry", String(decoding: try JSONSerialization.data(withJSONObject: geometry), as: UTF8.self), "--token-limit-hits", String(hits)]
            process.standardOutput = pipe
            try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        func block(_ label: String, _ box: [Double], _ content: String) -> [String: Any] { ["block_label": label, "block_bbox": box, "block_content": content] }
        let table = "<table border=1><tr><td style='text-align: center; word-wrap: break-word;' colspan=\"2\">문법\\n(ST/MT)</td></tr><tr><td>\"\\n\"</td><td>$\\nabla f$</td></tr></table>"
        let result: [String: Any] = ["res": ["model_settings": ["markdown_ignore_labels": ["header", "footer", "number", "footnote"]], "parsing_res_list": [
            block("header", [100, 20, 700, 60], "Chapter 2"),
            block("table", [100, 100, 700, 400], table),
            block("display_formula", [200, 500, 600, 560], " $$ h=\\frac{v^{2}}{2g} $$ "),
            block("formula_number", [700, 515, 760, 545], "(2.1)"),
            block("image", [100, 600, 300, 800], ""),
            block("footnote", [100, 900, 700, 940], "1 A footnote."),
            block("footer", [100, 960, 200, 990], "12"),
        ]]]
        let markdown = "<div style=\"text-align: center;\">\(table)</div>\n\n $$ h=\\frac{v^{2}}{2g} $$ \n\n<div style=\"text-align: center;\"><img src=\"imgs/a.jpg\" alt=\"Image\" width=\"20%\" /></div>\n"
        let page = try convert(result, markdown, geometry: ["scale": 2.0, "rotation": 0, "width": 420.0, "height": 595.0])
        let text = try XCTUnwrap(page["markdown"] as? String)
        XCTAssertTrue(text.hasPrefix("<table><tr><td colspan=\"2\">문법<br>(ST/MT)</td></tr><tr><td>\"\\n\"</td><td>$\\nabla f$</td></tr></table>"), text)
        XCTAssertTrue(text.contains("$$ h=\\frac{v^{2}}{2g} \\tag{2.1} $$")); XCTAssertTrue(text.contains("[figure]"))
        XCTAssertTrue(text.hasSuffix("---\n\n1 A footnote.")); XCTAssertFalse(text.contains("Chapter 2")); XCTAssertFalse(text.contains("style="))
        let blocks = try XCTUnwrap(page["blocks"] as? [[String: Any]])
        XCTAssertEqual(blocks.map { $0["type"] as? String }, ["header", "table", "display_formula", "formula_number", "image", "footnote", "footer"])
        XCTAssertEqual(blocks[0]["text"] as? String, "Chapter 2"); XCTAssertEqual(blocks[2]["latex"] as? String, "h=\\frac{v^{2}}{2g}")
        XCTAssertEqual(blocks[3]["inMarkdown"] as? Bool, true)
        XCTAssertEqual(blocks[1]["bbox"] as? [Double], [50, 395, 300, 150], "pixels at scale 2 -> points from the lower-left corner")
        XCTAssertEqual(page["reasons"] as? [String], [])
        // A page shown rotated 90 degrees: the box maps back into unrotated page space.
        let rotated = try convert(["parsing_res_list": [block("text", [0, 0, 100, 50], "x")]], "x", geometry: ["scale": 1.0, "rotation": 90, "width": 300.0, "height": 500.0])
        XCTAssertEqual((rotated["blocks"] as? [[String: Any]])?.first?["bbox"] as? [Double], [0, 0, 50, 100], "the shown top-left corner is the page's lower-left")
        // Guards: malformed LaTeX, a loop, and a token-limit hit each mark the page for review.
        let broken = try convert(["parsing_res_list": [block("display_formula", [0, 0, 10, 10], "$$ \\frac{1}{0}} $$")]], "$$ \\frac{1}{0}} $$", geometry: ["scale": 1.0, "width": 10.0, "height": 10.0])
        XCTAssertEqual(broken["reasons"] as? [String], ["malformed LaTeX formula"])
        let loop = try convert(["parsing_res_list": []], String(repeating: "고객은 먼저 ", count: 40), geometry: ["scale": 1.0, "width": 10.0, "height": 10.0], hits: 1)
        XCTAssertEqual((loop["reasons"] as? [String])?.count, 2)
        let matrix = "$$ \\begin{matrix}" + String(repeating: "{\\boxed{0}}&", count: 6) + "1\\end{matrix} $$"
        XCTAssertEqual(try convert(["parsing_res_list": []], matrix, geometry: ["scale": 1.0, "width": 10.0, "height": 10.0])["reasons"] as? [String], [], "repeated matrix entries are content, not a loop")
    }

    /// Runs only where the engine is installed, for example with BOOKSIDE_STRUCTURE_PYTHON and BOOKSIDE_MLX_VLM_SERVER set.
    func testRealEngineRecognizesAnAuthoredTable() async throws {
        guard let engine = StructureEngine.discover().engine else { throw XCTSkip("PaddleOCR-VL structure engine not installed") }
        let pdf = try makePDF("Table.pdf", pages: [["Station rainfall in March"]], table: [["Station", "Jan", "Mar"], ["Gull", "31", "58"], ["Nuri", "27", "73"]])
        let store = try LibraryStore(directory: root.appendingPathComponent("data"))
        let book = try store.register(source: pdf, ocr: nil, root: root)
        let result = try StructureService(engine: engine).run(book: book, pages: 1...1, store: store, progress: { _ in })
        XCTAssertEqual(result.counts.processed, 1); XCTAssertEqual(result.engine?.concurrency, 1)
        let page = try XCTUnwrap(store.structurePages(bookID: book.id, fileSHA256: result.fileSHA256).first)
        XCTAssertTrue(page.markdown.contains("<table>") && page.markdown.contains("73"), page.markdown)
        let table = try XCTUnwrap(page.blocks.first { $0.type == "table" })
        // Drawn at x 60...360, y 322...400 in PDF points.
        XCTAssertEqual(table.bbox[0], 60, accuracy: 12); XCTAssertEqual(table.bbox[1], 322, accuracy: 12)
        XCTAssertEqual(table.bbox[2], 300, accuracy: 20); XCTAssertEqual(table.bbox[3], 78, accuracy: 20)
        XCTAssertGreaterThan(page.geometry.renderDPI, 100)
        _ = try StructureLayer.accept(book: book, pages: 1...1, store: store)
        let session = try BookReadingSession(book: book, scope: .init(mode: "book", startPage: 1, endPage: 1), structure: StructureLayer.acceptedMarkdown(book: book, store: store))
        let read = try json(await session.call("read_pages", startPage: 1))
        XCTAssertEqual((read["pages"] as? [[String: Any]])?.first?["source"] as? String, page.state == .accepted || page.state == .candidate ? "structure" : "text_layer")
    }
}
