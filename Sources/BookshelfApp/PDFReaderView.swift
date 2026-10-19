import SwiftUI
import PDFKit
import BookshelfCore

/// Scope shortcuts to the PDF responder subtree, including PDFKit's private document view.
/// Editors in the notebook, search, page field, sheets, and PDF forms keep native key behavior.
final class ReaderPDFView: PDFView {
    var navigate: ((Int) -> Void)?
    private var keyMonitor: Any?
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        guard window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  window.attachedSheet == nil, let responder = window.firstResponder as? NSView,
                  responder === self || responder.isDescendant(of: self) else { return event }
            if let editor = responder as? NSTextView, editor.isEditable { return event }
            if let field = responder as? NSTextField, field.isEditable { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard modifiers.isEmpty || (event.keyCode == 49 && modifiers == .shift),
                  let document = self.document, let page = self.currentPage else { return event }
            let current = document.index(for: page) + 1
            let target: Int
            switch event.keyCode {
            case 123, 116: target = current - 1 // Left, Page Up (Fn + Up)
            case 124, 121: target = current + 1 // Right, Page Down (Fn + Down)
            case 49: target = current + (modifiers == .shift ? -1 : 1)
            case 115: target = 1 // Home (Fn + Left)
            case 119: target = document.pageCount // End (Fn + Right)
            default: return event
            }
            self.navigate?(min(max(target, 1), document.pageCount))
            return nil
        }
    }
    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }
}

struct PDFReaderView: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    static func dismantleNSView(_ view: ReaderPDFView, coordinator: Coordinator) {
        if coordinator.model.pdfView === view { coordinator.model.pdfView = nil }
        view.navigate = nil
        coordinator.detach()
    }
    func makeNSView(context: Context) -> ReaderPDFView {
        let view = ReaderPDFView()
        view.autoScales = true; view.displayMode = model.continuousReading ? .singlePageContinuous : .singlePage
        view.displayDirection = .vertical
        view.displaysPageBreaks = true; view.pageBreakMargins = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view.backgroundColor = NSColor.underPageBackgroundColor
        view.navigate = { [weak model] page in model?.goToPage(page) }
        context.coordinator.attach(view)
        model.pdfView = view
        return view
    }
    func updateNSView(_ view: ReaderPDFView, context: Context) {
        let coordinator = context.coordinator
        let mode: PDFDisplayMode = model.continuousReading ? .singlePageContinuous : .singlePage
        if view.displayMode != mode {
            let current = view.currentPage
            view.displayMode = mode; view.autoScales = true
            if let current { view.go(to: current) }
        }
        if view.document !== model.document {
            view.document = model.document; view.autoScales = true
            coordinator.lastJump = -1; coordinator.highlightIDs = nil
            DispatchQueue.main.async { [weak view] in
                guard let view, let window = view.window, window.attachedSheet == nil else { return }
                if let editor = window.firstResponder as? NSTextView, editor.isEditable { return }
                if let field = window.firstResponder as? NSTextField, field.isEditable { return }
                window.makeFirstResponder(view)
            }
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
        var highlightIDs: Set<String>?
        private static let annotatedPages = NSMapTable<PDFDocument, NSIndexSet>(keyOptions: .weakMemory, valueOptions: .strongMemory)
        var tokens: [NSObjectProtocol] = []
        init(model: AppModel) { self.model = model }
        func attach(_ view: PDFView) {
            self.view = view
            tokens.append(NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in Task { @MainActor in self?.changedPage() } })
            tokens.append(NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak self] _ in Task { @MainActor in self?.changedSelection() } })
            tokens.append(NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak self] _ in Task { @MainActor in self?.changedScale() } })
        }
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
        func detach() {
            tokens.forEach(NotificationCenter.default.removeObserver); tokens.removeAll(); view = nil
        }
        func changedPage() {
            guard !model.readingShelfVisible, !model.textMode,
                  let view, let document = view.document, document === model.document, let page = view.currentPage else { return }
            let index = document.index(for: page)
            if index != NSNotFound {
                DispatchQueue.main.async { [weak self, weak document] in
                    guard let self, !self.model.readingShelfVisible, !self.model.textMode,
                          let document, self.view?.document === document, self.model.document === document else { return }
                    self.model.pageChanged(index + 1)
                }
            }
        }
        func changedScale() {
            guard let view else { return }
            model.zoomChanged(scale: view.scaleFactor, fits: view.autoScales)
        }
        func changedSelection() {
            guard let current = view?.document, current === model.document else { return }
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
            // A cached PDF may still contain marks drawn by a previous view.
            // Track only our touched pages; never walk the entire book to redraw.
            let previous = (Self.annotatedPages.object(forKey: document) ?? NSIndexSet()) as IndexSet
            for i in previous {
                guard let page = document.page(at: i) else { continue }
                for annotation in page.annotations where annotation.userName == "Bookside" { page.removeAnnotation(annotation) }
            }
            var touched = IndexSet()
            for h in highlights {
                guard let page = document.page(at: h.page - 1) else { continue }
                touched.insert(h.page - 1)
                let bounds = page.bounds(for: .mediaBox)
                for normalized in h.rects {
                    let rect = CGRect(x: bounds.minX + normalized.x*bounds.width, y: bounds.minY + normalized.y*bounds.height, width: normalized.width*bounds.width, height: normalized.height*bounds.height)
                    let mark = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                    mark.color = NSColor.systemYellow.withAlphaComponent(0.35); mark.userName = "Bookside"; mark.contents = h.comment
                    page.addAnnotation(mark)
                }
            }
            Self.annotatedPages.setObject(touched as NSIndexSet, forKey: document)
            highlightIDs = ids
        }
    }
}
