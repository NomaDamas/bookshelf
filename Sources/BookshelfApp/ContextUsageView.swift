import SwiftUI
import BookshelfCore

/// Token detail for the latest request, opened from the Pi menu rather than kept in the panel header.
struct ContextUsageDetails: View {
    let usage: AgentContextUsage?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("마지막 요청의 컨텍스트").font(.headline)
            if let usage {
                if let model = usage.model { Text(model).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled) }
                if let fraction = usage.fraction {
                    ProgressView(value: fraction).tint(fraction > 0.9 ? .orange : ReaderStyle.accent)
                        .accessibilityLabel("컨텍스트 사용 비율").accessibilityValue(String(format: "%.1f%%", fraction * 100))
                }
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 8) {
                    row("입력", usage.inputTokens)
                    row("출력", usage.outputTokens)
                    if let cached = usage.cachedInputTokens { row("입력 중 캐시", cached) }
                    if let maximum = usage.contextWindow { row("컨텍스트 크기", maximum) }
                }.font(.system(size: 12))
                if usage.contextWindow == nil { Text("이 실행기는 컨텍스트 크기를 제공하지 않았습니다.").font(.caption).foregroundStyle(.secondary) }
            } else { Text("답변을 받은 뒤 실행기가 보고한 토큰 사용량을 표시합니다. 이전 버전의 대화에는 사용량 기록이 없을 수 있습니다.").font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) }
            Divider()
            Text("표시값은 마지막 요청의 입력과 출력입니다. 새 질문에는 현재 페이지와 최근 대화 최대 12개를 전달합니다. 전체 대화 기록은 이 Mac에 보관됩니다.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(18).frame(width: 300)
    }
    /// Short form for the Pi menu item, e.g. "12.3k / 200k (6.2%)".
    static func summary(_ usage: AgentContextUsage?) -> String? {
        guard let usage else { return nil }
        let total = compact(usage.usedTokens) + (usage.contextWindow.map { " / " + compact($0) } ?? " 토큰")
        return usage.fraction.map { total + String(format: " (%.1f%%)", $0 * 100) } ?? total
    }
    private func row(_ label: String, _ count: Int) -> some View { GridRow { Text(label).foregroundStyle(.secondary); Text(count.formatted() + " 토큰").monospacedDigit() } }
    private static func compact(_ value: Int) -> String {
        func short(_ number: Double, _ unit: String) -> String { String(format: number >= 100 ? "%.0f" : "%.1f", number) + unit }
        return value >= 1_000_000 ? short(Double(value) / 1_000_000, "M") : value >= 1000 ? short(Double(value) / 1000, "k") : String(value)
    }
}
