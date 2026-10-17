import SwiftUI
import BookshelfCore

struct ContextUsageView: View {
    let usage: AgentContextUsage?
    @State private var details = false
    private var fraction: Double { usage?.fraction ?? 0 }
    private var color: Color { fraction > 0.9 ? .orange : ReaderStyle.accent }
    var body: some View {
        Button { details.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(.secondary.opacity(0.18), lineWidth: 2)
                    if usage?.fraction != nil { Circle().trim(from: 0, to: fraction).stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90)) }
                }.frame(width: 15, height: 15)
                Text("컨텍스트").foregroundStyle(.secondary)
                Spacer()
                if let usage {
                    Text(compact(usage.usedTokens) + (usage.contextWindow.map { " / " + compact($0) } ?? " 토큰"))
                        .monospacedDigit().foregroundStyle(.primary)
                    if let ratio = usage.fraction { Text(String(format: "%.1f%%", ratio * 100)).foregroundStyle(.secondary) }
                } else { Text("첫 답변 후 표시").foregroundStyle(.secondary) }
                Image(systemName: "info.circle").foregroundStyle(.tertiary)
            }.font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 8)
                .background(ReaderStyle.muted, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityLabel("컨텍스트 사용량")
            .popover(isPresented: $details) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("마지막 요청의 컨텍스트").font(.headline)
                    if let usage {
                        if let model = usage.model { Text(model).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled) }
                        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 8) {
                            row("입력", usage.inputTokens)
                            row("출력", usage.outputTokens)
                            if let cached = usage.cachedInputTokens { row("입력 중 캐시", cached) }
                            if let maximum = usage.contextWindow { row("컨텍스트 크기", maximum) }
                        }.font(.system(size: 12))
                        if usage.contextWindow == nil { Text("이 실행기는 컨텍스트 크기를 제공하지 않았습니다.").font(.caption).foregroundStyle(.secondary) }
                    } else { Text("답변을 받은 뒤 실행기가 보고한 토큰 사용량을 표시합니다. 이전 버전의 대화에는 사용량 기록이 없을 수 있습니다.").font(.system(size: 12)) }
                    Divider()
                    Text("표시값은 마지막 요청의 입력과 출력입니다. 새 질문에는 현재 페이지와 최근 대화 최대 12개를 전달합니다. 전체 대화 기록은 이 Mac에 보관됩니다.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(18).frame(width: 300)
            }
    }
    private func row(_ label: String, _ count: Int) -> some View { GridRow { Text(label).foregroundStyle(.secondary); Text(count.formatted() + " 토큰").monospacedDigit() } }
    private func compact(_ value: Int) -> String {
        value >= 1_000_000 ? String(format: "%.1fM", Double(value) / 1_000_000) : value >= 1000 ? String(format: "%.1fk", Double(value) / 1000) : String(value)
    }
}
