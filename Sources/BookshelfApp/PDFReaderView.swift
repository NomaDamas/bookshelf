import SwiftUI
import PDFKit
import BookshelfCore

struct PDFReaderView: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true; view.displayMode = .singlePageContinuous; view.displayDirection = .vertical
        view.displaysPageBreaks = true; view.pageBreakMargins = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        view.backgroundColor = NSColor.windowBackgroundColor
        context.coordinator.attach(view)
        model.pdfView = view
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        let coordinator = context.coordinator
        if view.document !== model.document {
            view.document = model.document; view.autoScales = true
            coordinator.lastJump = -1; coordinator.highlightIDs = []
        }
        if coordinator.lastJump != model.jumpSerial, let doc = view.document, let page = doc.page(at: model.requestedPage - 1) {
            coordinator.lastJump = model.jumpSerial
            view.go(to: page)
        }
        coordinator.drawHighlights(model.highlights)
    }
    @MainActor final class Coordinator: NSObject {
        let model: AppModel
        weak var view: PDFView?
        var lastJump = -1
        var highlightIDs: Set<String> = []
        var tokens: [NSObjectProtocol] = []
        init(model: AppModel) { self.model = model }
        func attach(_ view: PDFView) {
            self.view = view
            tokens.append(NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in Task { @MainActor in self?.changedPage() } })
            tokens.append(NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak self] _ in Task { @MainActor in self?.changedSelection() } })
        }
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
        func changedPage() {
            guard let view, let document = view.document, let page = view.currentPage else { return }
            let index = document.index(for: page)
            if index != NSNotFound { DispatchQueue.main.async { [weak self] in self?.model.pageChanged(index + 1) } }
        }
        func changedSelection() {
            guard let view, let document = view.document, let selection = view.currentSelection, let book = model.activeBook, !(selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { model.selection = []; return }
            var drafts: [Highlight] = []
            for page in selection.pages {
                let bounds = page.bounds(for: .mediaBox)
                let lines = selection.selectionsByLine().filter { $0.pages.contains(page) }
                let quote = lines.compactMap(\.string).joined(separator: "\n")
                let rects = lines.map { line -> PageRect in
                    let r = line.bounds(for: page)
                    return PageRect(x: (r.minX-bounds.minX)/bounds.width, y: (r.minY-bounds.minY)/bounds.height, width: r.width/bounds.width, height: r.height/bounds.height)
                }
                if !quote.isEmpty { drafts.append(Highlight(bookID: book.id, page: document.index(for: page) + 1, quote: quote, rects: rects)) }
            }
            model.selection = drafts
        }
        func drawHighlights(_ highlights: [Highlight]) {
            let ids = Set(highlights.map(\.id))
            guard ids != highlightIDs, let document = view?.document else { return }
            for i in 0..<document.pageCount {
                guard let page = document.page(at: i) else { continue }
                for annotation in page.annotations where annotation.userName == "Bookshelf" { page.removeAnnotation(annotation) }
            }
            for h in highlights {
                guard let page = document.page(at: h.page - 1) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                for normalized in h.rects {
                    let rect = CGRect(x: bounds.minX + normalized.x*bounds.width, y: bounds.minY + normalized.y*bounds.height, width: normalized.width*bounds.width, height: normalized.height*bounds.height)
                    let mark = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                    mark.color = NSColor.systemYellow.withAlphaComponent(0.35); mark.userName = "Bookshelf"; mark.contents = h.comment
                    page.addAnnotation(mark)
                }
            }
            highlightIDs = ids
        }
    }
}
