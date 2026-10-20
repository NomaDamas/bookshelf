import SwiftUI

enum ReaderAppearance: String, CaseIterable {
    case system, light, dark
    var title: String {
        switch self { case .system: return "시스템"; case .light: return "밝게"; case .dark: return "어둡게" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

/// Aside's neutral surfaces and compact controls, adapted to macOS semantic colors.
/// Dimensions are generated from Resources/Design/tokens.json.
enum ReaderStyle {
    static let accent = Color(nsColor: .systemBlue)
    static let panel = Color(nsColor: .textBackgroundColor)
    static let canvas = Color.primary.opacity(ReaderTokens.mutedOpacity)
    static let muted = Color.primary.opacity(ReaderTokens.mutedOpacity)
    static let selection = Color.primary.opacity(ReaderTokens.selectionOpacity)
    static let border = Color.primary.opacity(ReaderTokens.borderOpacity)
    static let toolbarHeight = ReaderTokens.toolbarHeight
    static let footerHeight = ReaderTokens.footerHeight
}

enum ReaderMotion {
    static func ease(_ duration: Double) -> Animation {
        .timingCurve(ReaderTokens.easeX1, ReaderTokens.easeY1, ReaderTokens.easeX2, ReaderTokens.easeY2, duration: duration)
    }
}

/// Reading surfaces stay opaque; Reduce Transparency gets a solid fallback.
struct ReaderMaterial: View {
    var material: NSVisualEffectView.Material = .sidebar
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else { NativeMaterial(material: material) }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    private struct NativeMaterial: NSViewRepresentable {
        let material: NSVisualEffectView.Material
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.blendingMode = .behindWindow
            view.state = .followsWindowActiveState
            view.material = material
            return view
        }
        func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
    }
}

struct ReaderHairline: View {
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Rectangle().fill(contrast == .increased ? Color.secondary : ReaderStyle.border)
            .frame(height: contrast == .increased ? 1 : ReaderTokens.hairline)
            .accessibilityHidden(true)
    }
}

struct ReaderSurfaceBorder: ViewModifier {
    var radius: CGFloat = ReaderTokens.radiusLarge
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(contrast == .increased ? Color.secondary : ReaderStyle.border,
                              lineWidth: contrast == .increased ? 1 : ReaderTokens.hairline)
                .allowsHitTesting(false)
        }
    }
}

struct ReaderIconButton: View {
    let symbol: String
    let label: String
    var selected = false
    /// Smaller, muted variant for secondary actions on a Pi turn's summary line.
    var compact = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: compact ? ReaderTokens.captionFont : ReaderTokens.controlFont, weight: .medium))
                .foregroundStyle(selected ? ReaderStyle.accent : compact ? Color.secondary : Color.primary)
                .frame(width: compact ? 26 : ReaderTokens.controlSize, height: compact ? 26 : ReaderTokens.controlSize)
                .contentShape(RoundedRectangle(cornerRadius: ReaderTokens.radiusMedium))
        }
        .buttonStyle(.plain)
        .background(selected ? ReaderStyle.selection : (hovering && isEnabled ? ReaderStyle.muted : .clear),
                    in: RoundedRectangle(cornerRadius: ReaderTokens.radiusMedium, style: .continuous))
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : ReaderMotion.ease(ReaderTokens.controlDuration), value: hovering)
        .help(label).accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ReaderSearchField: View {
    let prompt: String
    let label: String
    @Binding var text: String
    var submit: () -> Void = {}
    /// Set by a menu command such as Find; the field takes focus once and clears the request.
    var focusRequest: Binding<Bool>?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain).focused($focused).onSubmit(submit)
                .accessibilityLabel(label)
                .task(id: focusRequest?.wrappedValue) {
                    guard focusRequest?.wrappedValue == true else { return }
                    await Task.yield()
                    focused = true; focusRequest?.wrappedValue = false
                }
            if !text.isEmpty {
                Button { text = ""; focused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).accessibilityLabel("\(label) 지우기")
            }
        }
        .font(.system(size: ReaderTokens.controlFont))
        .padding(.horizontal, 10).frame(height: 34)
        .background(ReaderStyle.muted, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusMedium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReaderTokens.radiusMedium, style: .continuous)
                .strokeBorder(focused ? ReaderStyle.accent : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
    }
}

/// AppKit's textured segments keep native arrow-key and accessibility behavior
/// without tinting the selected tab as a primary action.
struct ReaderPicker<Value: Hashable>: NSViewRepresentable {
    let choices: [(String, Value)]
    @Binding var selection: Value
    let label: String
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: choices.map(\.0), trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentStyle = .texturedRounded
        control.segmentDistribution = .fill
        control.font = .systemFont(ofSize: ReaderTokens.captionFont, weight: .medium)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel(label)
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.isEnabled = isEnabled
        control.selectedSegment = choices.firstIndex(where: { $0.1 == selection }) ?? -1
        for (index, choice) in choices.enumerated() { control.setLabel(choice.0, forSegment: index) }
    }
    final class Coordinator: NSObject {
        var parent: ReaderPicker
        init(_ parent: ReaderPicker) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) {
            guard parent.choices.indices.contains(sender.selectedSegment) else { return }
            parent.selection = parent.choices[sender.selectedSegment].1
        }
    }
}

/// The Help window lists every key the reader answers to, read from the user's current shortcut settings.
struct KeyboardShortcutsList: View {
    static let windowID = "keyboard-shortcuts"
    static let windowTitle = "키보드 단축키"
    @ObservedObject var model: AppModel
    private static let readingKeys = [("이전 / 다음 페이지", "←  →"), ("다음 페이지", "Space / Fn ↓"), ("이전 페이지", "⇧Space / Fn ↑"),
                                      ("첫 / 마지막 페이지", "Fn ← / Fn →"), ("페이지 안에서 스크롤", "↑  ↓")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("읽는 화면에서") { ForEach(Self.readingKeys, id: \.0) { row($0.0, $0.1) } }
                ForEach(ShortcutGroup.allCases) { group in
                    section(group.title) { ForEach(group.actions) { row($0.title, model.shortcuts[$0].label) } }
                }
                Text("읽는 화면의 키는 원문과 텍스트 보기에서 쓸 수 있습니다. 메모나 검색어를 입력하는 동안에는 글 편집 키로 쓰입니다. 단축키는 설정의 단축키 항목에서 바꿀 수 있습니다.")
                    .font(.system(size: ReaderTokens.captionFont)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(width: 420, height: 620)
    }
    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: ReaderTokens.controlFont, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) { rows() }
        }
    }
    private func row(_ title: String, _ keys: String) -> some View {
        GridRow {
            Text(title).font(.system(size: ReaderTokens.captionFont)).frame(maxWidth: .infinity, alignment: .leading)
            Text(keys).font(.system(size: ReaderTokens.captionFont, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
        }.accessibilityElement(children: .combine)
    }
}
