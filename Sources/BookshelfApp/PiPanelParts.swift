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
    case auto, explain, compare, visualize, trace, check, pretest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "자동"
        case .explain: return "쉽게 설명"
        case .compare: return "비교표"
        case .visualize: return "시각 자료"
        case .trace: return "막힌 곳 찾기"
        case .check: return "내 설명 점검"
        case .pretest: return "예습 질문"
        }
    }
    /// Tutoring modes run over several turns: Pi asks, the reader answers in the next message.
    /// They stay selected so each answer is read under the same protocol, and end when the reader
    /// picks another mode or starting prompt, switches books or clears the conversation.
    var isTutoring: Bool { self == .trace || self == .check || self == .pretest }
    /// The mode after choosing a starting prompt. A plain prompt leaves a tutoring mode
    /// because it is a new question, not an answer to Pi's last check.
    func starting(_ requested: PiExplanation?) -> PiExplanation { requested ?? (isTutoring ? .auto : self) }
    var placeholder: String {
        switch self {
        case .trace: return "막힌 문장을 묻거나 Pi의 확인 질문에 답해 보세요."
        case .check: return "내 말로 설명하거나 Pi가 짚은 부분을 다시 설명해 보세요."
        case .pretest: return "지금까지 읽은 쪽에 대해 물어보세요. 추측은 질문 아래에 적습니다."
        default: return "이 책에 대해 Pi에게 물어보세요."
        }
    }
    init(skill: String) { self = PiExplanation(rawValue: skill) ?? .auto }
}

/// A starting prompt fills the composer and may switch the explanation mode. Nothing is sent
/// until the reader sends it.
struct PiStarter: Equatable {
    let title: String
    let prompt: String
    var mode: PiExplanation? = nil

    static let fixed: [PiStarter] = [
        PiStarter(title: "이 페이지 쉽게 설명해줘", prompt: "이 페이지의 핵심 내용을 작은 예시와 함께 쉽게 설명해줘."),
        PiStarter(title: "이 장 핵심 정리해줘", prompt: "지금 읽는 장의 핵심 내용을 정리해줘."),
        PiStarter(title: "확인 퀴즈 내줘", prompt: "지금까지 읽은 내용을 확인하는 퀴즈 3문제를 내줘. 정답은 마지막에 따로 알려줘."),
    ]
    static let check = PiStarter(title: "내 설명 점검받기", prompt: "내 말로 설명해 볼게요. 이 책의 관련 쪽과 대조해서 점검해 줘.\n\n내 설명: ", mode: .check)
    /// The stuck sentence goes into the question itself, so later answers keep it in the
    /// conversation history after the selection is gone.
    static func trace(selection: String) -> PiStarter {
        let sentence = selection.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let quote = sentence.count > 200 ? String(sentence.prefix(200)) + "…" : sentence
        return PiStarter(title: "선택한 문장에서 막혔어요", prompt: "“\(quote)”\n이 문장에서 막혔어요. 이 문장이 기대는 개념을 이 책 앞쪽에서 찾아 주세요.", mode: .trace)
    }
    /// Pre-reading questions for the chapter the reader is opening. The page range in the
    /// question tells Pi which pages lie ahead.
    static func pretest(chapter: BookOutlineEntry) -> PiStarter {
        let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (title.isEmpty ? "이 장" : "“\(title)”") + "(\(chapter.startPage)~\(chapter.endPage)쪽)"
        return PiStarter(title: "이 장 예습 질문 받기", prompt: "\(name)을 읽기 전에 풀어 볼 예습 질문 2~3개를 내 주세요. 틀려도 괜찮아요.", mode: .pretest)
    }
    /// The trace prompt needs a selected sentence; the check prompt leaves room for the reader's own words.
    static func all(selection: String) -> [PiStarter] {
        let stuck = selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [trace(selection: selection)]
        return stuck + fixed + [check]
    }
}

struct PiSuggestions: View {
    var selection = ""
    let choose: (PiStarter) -> Void
    var body: some View {
        let items = PiStarter.all(selection: selection)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips(items) }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                    HStack(spacing: 6) { chips(Array(items[start..<min(start + 2, items.count)])) }
                }
            }
            VStack(alignment: .leading, spacing: 6) { chips(items) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func chips(_ items: [PiStarter]) -> some View {
        ForEach(items, id: \.title) { item in
            Button(item.title) { choose(item) }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                .help((item.mode.map { "\($0.title) 방식으로 바꾸고 " } ?? "") + "입력창에 넣기: " + item.prompt)
        }
    }
}

/// Offered only at the start of an outline chapter. Choosing it fills the composer like any
/// starting prompt; closing it stops the offer for this book until the app restarts.
struct PiPretestOffer: View {
    let chapter: BookOutlineEntry
    let choose: (PiStarter) -> Void
    let decline: () -> Void
    var body: some View {
        let starter = PiStarter.pretest(chapter: chapter)
        HStack(spacing: 2) {
            Button(starter.title) { choose(starter) }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                .help("예습 질문 방식으로 바꾸고 입력창에 넣기: " + starter.prompt)
            ReaderIconButton(symbol: "xmark", label: "예습 질문 제안 닫기", compact: true, action: decline)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("pi-pretest-offer")
    }
}

/// Pre-reading questions under Pi's reply. An answer and its page stay hidden until the reader's
/// position reaches that page; then the guess and the answer sit together for comparison.
struct PiPretestCard: View {
    let set: PretestSet
    let commitGuess: (_ question: String, _ guess: String) -> Void
    let openPage: (Int) -> Void
    var body: some View {
        let revealed = set.questions.filter { $0.revealed != nil }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("예습 질문").font(.system(size: ReaderTokens.captionFont, weight: .semibold))
                Spacer(minLength: 4)
                if !set.questions.isEmpty {
                    Text("\(revealed)/\(set.questions.count) 공개").font(.system(size: ReaderTokens.detailFont)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            ForEach(Array(set.questions.enumerated()), id: \.element.id) { index, item in
                PiPretestRow(number: index + 1, item: item, commit: { commitGuess(item.id, $0) }, openPage: openPage)
            }
            if set.dropped > 0 {
                Text(set.questions.isEmpty ? "답이 있는 쪽을 확인한 질문이 없어 보여 드릴 질문이 없습니다." : "답이 있는 쪽을 확인하지 못한 질문 \(set.dropped)개는 뺐습니다.")
                    .font(.system(size: ReaderTokens.detailFont)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(ReaderStyle.panel, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusMedium, style: .continuous))
            .modifier(ReaderSurfaceBorder(radius: ReaderTokens.radiusMedium))
            .accessibilityElement(children: .contain).accessibilityIdentifier("pi-pretest-card")
    }
}

private struct PiPretestRow: View {
    let number: Int
    let item: PretestQuestion
    let commit: (String) -> Void
    let openPage: (Int) -> Void
    @State private var guess = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(number). \(item.question)").font(.system(size: ReaderTokens.bodyFont, weight: .medium)).lineSpacing(3)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if item.revealed == nil {
                TextField("읽기 전에 추측해 보세요", text: $guess, axis: .vertical)
                    .textFieldStyle(.roundedBorder).font(.system(size: ReaderTokens.controlFont)).lineLimit(1...4)
                    .onChange(of: guess) { _, value in commit(value) }
                    .accessibilityLabel("질문 \(number) 추측")
                Label("읽다가 답이 나오는 쪽에 이르면 답이 열립니다.", systemImage: "lock")
                    .font(.system(size: ReaderTokens.detailFont)).foregroundStyle(.secondary)
            } else {
                Button("\(item.answerPage)쪽에 나온 답") { openPage(item.answerPage) }
                    .buttonStyle(.plain).foregroundStyle(ReaderStyle.accent).font(.system(size: ReaderTokens.detailFont, weight: .semibold))
                    .help("\(item.answerPage)쪽으로 이동합니다.")
                Text(item.answer).font(.system(size: ReaderTokens.controlFont)).lineSpacing(3)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text("내 추측: " + ((item.guess?.isEmpty ?? true) ? "적지 않음" : item.guess!))
                    .font(.system(size: ReaderTokens.captionFont)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.onAppear { guess = item.guess ?? "" }
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
                Text(title).font(.system(size: ReaderTokens.controlFont, weight: .semibold))
                Text(detail).font(.system(size: ReaderTokens.captionFont)).foregroundStyle(.secondary).lineSpacing(3)
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
        case .needsYou: Image(systemName: "smallcircle.filled.circle").font(.system(size: ReaderTokens.footnoteFont, weight: .semibold)).foregroundStyle(.orange)
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
            }.font(.system(size: ReaderTokens.captionFont)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
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
