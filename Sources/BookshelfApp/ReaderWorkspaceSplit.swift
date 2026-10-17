import SwiftUI
import QuartzCore
import BookshelfCore

/// Keep the PDF and side panels mounted while AppKit animates their native split constraints.
struct ReaderWorkspaceSplit: NSViewControllerRepresentable {
    @ObservedObject var model: AppModel
    let book: Book
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = true; controller.splitView.dividerStyle = .thin
        controller.minimumThicknessForInlineSidebars = 0
        let c = context.coordinator
        let left = NSSplitViewItem(sidebarWithViewController: c.left)
        left.minimumThickness = 250; left.maximumThickness = 390; left.preferredThicknessFraction = 0.21
        left.canCollapseFromWindowResize = false; left.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        left.isCollapsed = !model.sidebarVisible
        let center = NSSplitViewItem(viewController: c.center); center.minimumThickness = 380
        center.holdingPriority = .init(200)
        controller.addSplitViewItem(left); controller.addSplitViewItem(center)
        c.leftItem = left
        if AgentRuntime.bridgeURL != nil {
            let right = NSSplitViewItem(viewController: c.right)
            right.minimumThickness = 320; right.maximumThickness = 650; right.preferredThicknessFraction = 0.3
            right.automaticMaximumThickness = 420
            right.canCollapse = true; right.canCollapseFromWindowResize = false
            right.collapseBehavior = .preferResizingSiblingsWithFixedSplitView; right.isCollapsed = !model.aiPanelVisible
            controller.addSplitViewItem(right); c.rightItem = right
        }
        c.observe()
        updateRoots(c)
        return controller
    }
    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        let c = context.coordinator; updateRoots(c)
        c.applying = true
        defer { c.applying = false }
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = reduceMotion || controller.view.window == nil ? 0 : ReaderTokens.panelDuration
            animation.timingFunction = CAMediaTimingFunction(controlPoints: Float(ReaderTokens.easeX1), Float(ReaderTokens.easeY1), Float(ReaderTokens.easeX2), Float(ReaderTokens.easeY2))
            for (item, visible) in [(c.leftItem, model.sidebarVisible), (c.rightItem, model.aiPanelVisible)] {
                guard let item, item.isCollapsed == visible else { continue }
                if animation.duration == 0 { item.isCollapsed = !visible }
                else { item.animator().isCollapsed = !visible }
            }
        }
    }
    private func host<V: View>(_ view: V) -> AnyView {
        // Each native hosting view reads the OS accessibility preferences itself.
        AnyView(view.environment(\.colorScheme, scheme))
    }
    private func updateRoots(_ c: Coordinator) {
        let key = [book.id, book.title, book.activePath, String(book.pageCount), String(book.isAvailable)].joined(separator: "|")
        guard c.rootKey != key || c.rootScheme != scheme else { return }
        c.rootKey = key; c.rootScheme = scheme
        // Hosted views observe the models themselves. Replacing every root on each
        // parent update can create a nested SwiftUI layout/update feedback loop.
        c.left.rootView = host(NotesPanel(model: model, book: book).id(book.id))
        c.center.rootView = host(ReaderSurface(model: model, book: book).padding(8))
        c.right.rootView = host(BookChatView(model: model, chat: model.chat, book: book).id(book.id))
    }
    final class Coordinator {
        let model: AppModel
        let left = NSHostingController(rootView: AnyView(EmptyView()))
        let center = NSHostingController(rootView: AnyView(EmptyView()))
        let right = NSHostingController(rootView: AnyView(EmptyView()))
        var leftItem: NSSplitViewItem?
        var rightItem: NSSplitViewItem?
        var observations: [NSKeyValueObservation] = []
        var applying = false
        var rootKey: String?
        var rootScheme: ColorScheme?
        init(model: AppModel) { self.model = model; left.sizingOptions = []; center.sizingOptions = []; right.sizingOptions = [] }
        func observe() {
            if let leftItem { observations.append(leftItem.observe(\.isCollapsed) { [weak self] item, _ in
                guard let self, !self.applying else { return }
                DispatchQueue.main.async { if self.model.sidebarVisible == item.isCollapsed { self.model.sidebarVisible = !item.isCollapsed } }
            }) }
            if let rightItem { observations.append(rightItem.observe(\.isCollapsed) { [weak self] item, _ in
                guard let self, !self.applying else { return }
                DispatchQueue.main.async { if self.model.aiPanelVisible == item.isCollapsed { self.model.aiPanelVisible = !item.isCollapsed } }
            }) }
        }
    }
}
