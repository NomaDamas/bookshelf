import SwiftUI

/// Detect user scrolling without treating programmatic streaming updates as a request to leave the tail.
struct ChatScrollObserver: NSViewRepresentable {
    var nearBottom: (Bool) -> Void
    var scrolledAway: () -> Void
    func makeNSView(context: Context) -> ObserverView { ObserverView(nearBottom: nearBottom, scrolledAway: scrolledAway) }
    func updateNSView(_ view: ObserverView, context: Context) { view.nearBottom = nearBottom; view.scrolledAway = scrolledAway }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.stop() }
    final class ObserverView: NSView {
        var nearBottom: (Bool) -> Void
        var scrolledAway: () -> Void
            private var observations: [NSObjectProtocol] = []
        private weak var scroll: NSScrollView?
        private var liveScroll = false
        private var previousY: CGFloat = 0
        init(nearBottom: @escaping (Bool) -> Void, scrolledAway: @escaping () -> Void) {
            self.nearBottom = nearBottom; self.scrolledAway = scrolledAway; super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }
        private func attach() {
            guard let scroll = enclosingScrollView else { return }
            self.scroll = scroll; previousY = scroll.contentView.bounds.minY
            let center = NotificationCenter.default
            scroll.contentView.postsBoundsChangedNotifications = true
            observations.append(center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: scroll, queue: .main) { [weak self] _ in self?.liveScroll = true })
            observations.append(center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: scroll, queue: .main) { [weak self] _ in self?.liveScroll = false })
            observations.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in self?.changed() })
            changed()
        }
        private func changed() {
            guard let scroll, let document = scroll.documentView else { return }
            let visible = scroll.contentView.bounds
            let away = liveScroll && visible.minY < previousY - 1
            previousY = visible.minY
            let bottom = document.bounds.maxY - visible.maxY < 60
            DispatchQueue.main.async { [weak self] in
                guard let self, self.scroll != nil else { return }
                if away { self.scrolledAway() }
                self.nearBottom(bottom)
            }
        }
        func stop() { observations.forEach(NotificationCenter.default.removeObserver); observations = []; scroll = nil }
        deinit { stop() }
    }
}
