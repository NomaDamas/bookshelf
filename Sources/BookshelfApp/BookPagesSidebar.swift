import SwiftUI
import PDFKit

struct BookPagesSidebar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            if model.document != nil { NativePageThumbnails(model: model) }
            else { ProgressView("페이지를 불러오는 중").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }
}

private struct NativePageThumbnails: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.thumbnailSize = NSSize(width: 138, height: 180); view.maximumNumberOfColumns = 1
        context.coordinator.navigation.isHidden = true
        view.addSubview(context.coordinator.navigation)
        view.backgroundColor = .clear; view.pdfView = context.coordinator.navigation
        view.setAccessibilityLabel("책 페이지 썸네일")
        return view
    }
    func updateNSView(_ view: PDFThumbnailView, context: Context) {
        let coordinator = context.coordinator
        coordinator.updating = true
        defer { coordinator.updating = false }
        if coordinator.navigation.document !== model.document { coordinator.navigation.document = model.document }
        if let page = model.document?.page(at: model.page - 1), coordinator.navigation.currentPage !== page { coordinator.navigation.go(to: page) }
        coordinator.bind(view)
        // The main PDF view can be constructed after its sibling sidebar.
        DispatchQueue.main.async { [weak view, weak coordinator] in if let view { coordinator?.bind(view) } }
    }
    static func dismantleNSView(_ view: PDFThumbnailView, coordinator: Coordinator) { view.pdfView = nil; coordinator.detach() }
    @MainActor final class Coordinator {
        let model: AppModel
        // A hidden, window-attached PDF view drives thumbnails in text mode.
        let navigation = PDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        var updating = false
        private var observer: NSObjectProtocol?
        private let bookID: String?
        init(model: AppModel) {
            self.model = model; bookID = model.activeBook?.id
            navigation.displayMode = .singlePage; navigation.autoScales = true
            observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: navigation, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                guard let self, !self.updating, self.model.isReadingBook,
                      let document = self.navigation.document, document === self.model.document,
                      let page = self.navigation.currentPage else { return }
                let index = document.index(for: page)
                if index != NSNotFound, index + 1 != self.model.page { self.model.goToPage(index + 1) }
                }
            }
        }
        func bind(_ view: PDFThumbnailView) {
            guard model.activeBook?.id == bookID else { return }
            let primary = !model.textMode && model.pdfView?.document === model.document ? model.pdfView : nil
            let target = primary ?? navigation
            if view.pdfView !== target { view.pdfView = target }
        }
        func detach() { if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
