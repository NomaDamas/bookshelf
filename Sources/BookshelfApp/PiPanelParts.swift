import SwiftUI
import BookshelfCore

/// Menu item that shows the native checkmark for the current choice. The Pi composer's
/// scope, explanation and model menus all mark their selection this way.
struct PiMenuChoice: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View { Toggle(title, isOn: Binding(get: { selected }, set: { _ in action() })) }
}

enum PiExplanation: String, CaseIterable, Identifiable {
    case auto, explain, compare, visualize
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "자동"
        case .explain: return "쉽게 설명"
        case .compare: return "비교표"
        case .visualize: return "시각 자료"
        }
    }
    init(skill: String) { self = PiExplanation(rawValue: skill) ?? .auto }
}

/// Fixed starting prompts. Choosing one fills the composer; nothing is sent until the reader sends it.
struct PiSuggestions: View {
    static let prompts: [(title: String, prompt: String)] = [
        ("이 페이지 쉽게 설명해줘", "이 페이지의 핵심 내용을 작은 예시와 함께 쉽게 설명해줘."),
        ("이 장 핵심 정리해줘", "지금 읽는 장의 핵심 내용을 정리해줘."),
        ("확인 퀴즈 내줘", "지금까지 읽은 내용을 확인하는 퀴즈 3문제를 내줘. 정답은 마지막에 따로 알려줘."),
    ]
    let choose: (String) -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips(Self.prompts) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { chips(Array(Self.prompts.prefix(2))) }
                chips(Array(Self.prompts.dropFirst(2)))
            }
            VStack(alignment: .leading, spacing: 6) { chips(Self.prompts) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func chips(_ items: [(title: String, prompt: String)]) -> some View {
        ForEach(items, id: \.title) { item in
            Button(item.title) { choose(item.prompt) }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                .help("입력창에 넣기: " + item.prompt)
        }
    }
}

/// Shown in place of suggestions when Pi cannot answer yet. Sign-in itself stays in Settings.
struct PiConnectionNotice: View {
    let block: PiComposerBlock
    let connect: () -> Void
    let recheck: () -> Void
    private var title: String {
        switch block {
        case .nodeMissing: return "Node.js가 필요합니다"
        case .bridgeMissing: return "Pi 실행 모듈이 없습니다"
        case .accountDisconnected(let backend): return "\(backend.title) 계정을 연결해 주세요"
        default: return "연결 상태를 확인하지 못했습니다"
        }
    }
    private var detail: String {
        switch block {
        case .nodeMissing: return "Pi는 Node.js 22.19 이상에서 Claude Code나 Codex를 실행합니다. 설치한 뒤 연결 상태를 다시 확인해 주세요."
        case .bridgeMissing: return "이 빌드에는 Pi 연결 모듈이 들어 있지 않습니다. Bookside를 다시 설치해 주세요."
        case .accountDisconnected(let backend):
            return "Pi는 공식 \(backend == .claude ? "Claude Code" : "Codex") 로그인으로 답합니다. 설정의 Pi 탭에서 계정을 연결하거나 다른 실행기를 고를 수 있습니다."
        default: return "설정의 Pi 탭에서 계정과 실행기 상태를 확인할 수 있습니다."
        }
    }
    var body: some View {
        PiGutterRow { PiStatusMark(kind: .needsYou) } content: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("연결하기", action: connect).buttonStyle(.borderedProminent)
                        .help("설정의 Pi 탭을 엽니다.")
                    if block != .bridgeMissing { Button("다시 확인", action: recheck).help("연결 상태를 다시 확인합니다.") }
                }.controlSize(.small).padding(.top, 2)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("pi-connection-card")
    }
}

/// Transcript layout: status marks sit in a narrow leading column and every line of text starts after it.
enum PiTranscript {
    static let gutter: CGFloat = 18
}

struct PiGutterRow<Mark: View, Content: View>: View {
    private let alignment: VerticalAlignment
    private let mark: Mark
    private let content: Content
    init(alignment: VerticalAlignment = .firstTextBaseline, @ViewBuilder mark: () -> Mark, @ViewBuilder content: () -> Content) {
        self.alignment = alignment; self.mark = mark(); self.content = content()
    }
    var body: some View {
        HStack(alignment: alignment, spacing: 0) {
            mark.frame(width: PiTranscript.gutter, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Status vocabulary shared by steps, turns and connection notices:
/// spinner while running, orange ring when the reader has to act, green dot when done.
struct PiStatusMark: View {
    enum Kind { case running, needsYou, done, settled }
    let kind: Kind
    var body: some View {
        switch kind {
        case .running: ProgressView().controlSize(.mini).accessibilityLabel("진행 중")
        case .needsYou: Image(systemName: "smallcircle.filled.circle").font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange)
        case .done: Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.green)
        case .settled: Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.tertiary)
        }
    }
}

/// One tool step: "● 책 읽기 (27~29쪽)" with its result "└ 3쪽 읽음" underneath.
struct PiStepRow: View {
    let step: ChatStep
    private var mark: PiStatusMark.Kind {
        switch step.state {
        case "running": return .running
        case "done": return .done
        case "failed": return .needsYou
        default: return .settled
        }
    }
    private var stateLabel: String {
        switch step.state {
        case "running": return "진행 중"
        case "done": return "완료"
        case "failed": return "완료하지 못함"
        default: return "중단됨"
        }
    }
    var body: some View {
        PiGutterRow { PiStatusMark(kind: mark) } content: {
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title).fontWeight(.semibold) + Text(step.detail.map { " (\($0))" } ?? "").foregroundStyle(.secondary)
                if let result = step.result, !result.isEmpty { Text("└ " + result).foregroundStyle(.secondary) }
            }.font(.system(size: 12)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel([step.title, step.detail, stateLabel, step.result].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

/// Muted line that closes a turn, e.g. "12초 동안 작업, 오후 9:41 완료, Claude / Sonnet".
enum PiTurnWording {
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)초" }
        if total < 3600 { return total % 60 == 0 ? "\(total / 60)분" : "\(total / 60)분 \(total % 60)초" }
        let minutes = total % 3600 / 60
        return minutes == 0 ? "\(total / 3600)시간" : "\(total / 3600)시간 \(minutes)분"
    }
    static func clock(_ time: Double, now: Date = Date()) -> String {
        let date = Date(timeIntervalSince1970: time)
        return Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened) : date.formatted(date: .abbreviated, time: .shortened)
    }
    /// Replies saved before turns were timed only name their state and speaker.
    static func finished(_ message: BookChatMessage, speaker: String, now: Date = Date()) -> String {
        var parts: [String] = []
        if let finished = message.finished { parts.append(duration(finished - message.created) + " 동안 작업") }
        switch message.state {
        case "complete": if let finished = message.finished { parts.append(clock(finished, now: now) + " 완료") }
        case "failed": parts.append("완료하지 못함")
        default: parts.append("중단됨")
        }
        return (parts + [speaker]).joined(separator: ", ")
    }
    static func running(started: Double, writing: Bool, now: Date) -> String {
        (writing ? "답변 쓰는 중, " : "생각하는 중, ") + duration(now.timeIntervalSince1970 - started)
    }
}

/// Compact secondary icon action on a turn's summary line. Every one carries a tooltip and a spoken label.
struct PiActionButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: ReaderTokens.radiusMedium))
        }.buttonStyle(.plain).foregroundStyle(.secondary)
            .background(hovering && isEnabled ? ReaderStyle.muted : .clear, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusMedium, style: .continuous))
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { hovering = $0 }
            .help(label).accessibilityLabel(label)
    }
}
