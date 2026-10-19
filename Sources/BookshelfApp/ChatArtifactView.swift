import SwiftUI
import WebKit

enum ArtifactNavigationPolicy {
    static func allows(_ url: URL?, renderer: URL?, mainFrame: Bool) -> Bool {
        let ownFile = url?.isFileURL == true && (url?.host == nil || url?.host == "localhost") && url?.resolvingSymlinksInPath().standardizedFileURL.path == renderer?.resolvingSymlinksInPath().standardizedFileURL.path
        return ownFile || (!mainFrame && url?.scheme == "about")
    }
}

struct ChatArtifactView: View {
    let kind: String
    let source: String
    @State private var showSource = false
    @State private var expanded = false
    @State private var height: CGFloat = 260
    @State private var renderError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Label(kind == "mermaid" ? "다이어그램" : kind == "svg" ? "그림" : "인터랙티브 자료", systemImage: "rectangle.3.group")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Button(showSource ? "미리보기" : "코드") { showSource.toggle() }.buttonStyle(.borderless)
                Button { expanded = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.borderless).accessibilityLabel("시각 자료 크게 보기")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(10)
            ReaderHairline()
            if showSource {
                ScrollView([.horizontal, .vertical]) { Text(source).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(12) }
                    .frame(height: min(height, 320))
            } else {
                ArtifactWebView(kind: kind, source: source, height: $height, error: $renderError)
                    .frame(height: height)
                if renderError != nil {
                    Text("이 자료를 표시하지 못했습니다. 코드 보기에서 원문을 확인할 수 있습니다.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(12)
                }
            }
        }.background(ReaderStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .modifier(ReaderSurfaceBorder(radius: 10))
            .sheet(isPresented: $expanded) {
                ArtifactExpandedView(kind: kind, source: source)
            }
    }
}

private struct ArtifactExpandedView: View {
    let kind: String
    let source: String
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 600
    @State private var error: String?
    @State private var zoom: Double = 1
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("시각 자료").font(.headline)
                Spacer()
                Button { zoom = max(0.5, zoom - 0.25) } label: { Image(systemName: "minus.magnifyingglass") }.accessibilityLabel("시각 자료 축소")
                Text("\(Int(zoom * 100))%").font(.system(size: 12)).monospacedDigit().frame(width: 45)
                Button { zoom = min(3, zoom + 0.25) } label: { Image(systemName: "plus.magnifyingglass") }.accessibilityLabel("시각 자료 확대")
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            ReaderHairline()
            ArtifactWebView(kind: kind, source: source, height: $height, error: $error, zoom: zoom)
            if error != nil { Text("자료의 형식을 확인해 주세요.").font(.callout).padding() }
        }.frame(minWidth: 760, idealWidth: 960, minHeight: 560, idealHeight: 720)
    }
}

struct ArtifactWebView: NSViewRepresentable {
    let kind: String
    let source: String
    @Binding var height: CGFloat
    @Binding var error: String?
    var zoom: Double = 1
    @Environment(\.colorScheme) private var colorScheme
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.add(context.coordinator, name: "artifact")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.underPageBackgroundColor = .textBackgroundColor
        view.navigationDelegate = context.coordinator; view.allowsMagnification = true
        view.setAccessibilityLabel("시각 자료 미리보기")
        if let file = Bundle.main.resourceURL?.appendingPathComponent("Agent/renderer.html"), FileManager.default.fileExists(atPath: file.path) {
            context.coordinator.rendererURL = file
            view.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
        } else { DispatchQueue.main.async { error = "렌더러가 포함된 앱으로 실행해 주세요." } }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        view.magnification = zoom
        context.coordinator.render(view)
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.configuration.userContentController.removeScriptMessageHandler(forName: "artifact")
        view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: ArtifactWebView
        var rendererURL: URL?
        private var loaded = false
        private var lastSource: String?
        private var lastKind: String?
        private var lastDark: Bool?
        init(_ parent: ArtifactWebView) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true; render(webView) }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = action.request.url
            // Only the bundled host and its opaque srcdoc child may navigate here.
            // Bundle URLs can have a base URL and /var aliases, unlike WebKit's absolute request URL.
            let allowed = ArtifactNavigationPolicy.allows(url, renderer: rendererURL, mainFrame: action.targetFrame?.isMainFrame != false)
            if !allowed && action.targetFrame?.isMainFrame == true { parent.error = "미리보기 파일 경로를 확인하지 못했습니다." }
            decisionHandler(allowed ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.error = error.localizedDescription }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.error = error.localizedDescription }
        func render(_ view: WKWebView) {
            let dark = parent.colorScheme == .dark
            guard loaded, lastSource != parent.source || lastKind != parent.kind || lastDark != dark else { return }
            lastSource = parent.source; lastKind = parent.kind; lastDark = dark
            view.callAsyncJavaScript("return await window.renderArtifact(kind, source, dark)", arguments: ["kind": parent.kind, "source": parent.source, "dark": dark], in: nil, in: .page) { [weak self] result in
                if case .failure(let error) = result { self?.parent.error = error.localizedDescription }
            }
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.name == "artifact", let value = message.body as? [String: Any] else { return }
            if let height = value["height"] as? Double, height.isFinite {
                let next = CGFloat(min(480, max(180, height)))
                if abs(parent.height - next) > 1 { parent.height = next }
            }
            if value["state"] as? String == "error" { parent.error = value["error"] as? String ?? "표시 오류" }
            if value["state"] as? String == "ready" { parent.error = nil }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { parent.error = "미리보기가 중단됐습니다." }
    }
}
