import SwiftUI

@MainActor final class TextScrollTarget {
    weak var scrollView: NSScrollView?
    func scroll(by distance: CGFloat) {
        guard let scrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let direction: CGFloat = document.isFlipped ? 1 : -1
        let maxY = max(document.bounds.minY, document.bounds.maxY - clip.bounds.height)
        let y = min(max(clip.bounds.minY + distance * direction, document.bounds.minY), maxY)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
    }
}

/// Resolve the public enclosing scroll view from within the text content.
/// A weak target avoids retaining SwiftUI's hosting/scroll-view hierarchy.
struct TextScrollAnchor: NSViewRepresentable {
    let target: TextScrollTarget
    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.target = target
        return view
    }
    func updateNSView(_ view: AnchorView, context: Context) { view.resolve() }

    final class AnchorView: NSView {
        weak var target: TextScrollTarget?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); resolve() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); resolve() }
        func resolve() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.target?.scrollView = self.enclosingScrollView
            }
        }
    }
}
