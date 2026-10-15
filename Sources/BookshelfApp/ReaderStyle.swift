import SwiftUI

enum ReaderStyle {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.55, green: 0.74, blue: 0.67, alpha: 1)
            : NSColor(srgbRed: 0.22, green: 0.43, blue: 0.36, alpha: 1)
    })
    static let panel = Color(nsColor: .textBackgroundColor)
    static let toolbarHeight: CGFloat = 56
    static let footerHeight: CGFloat = 68
}

struct ReaderIconButton: View {
    let symbol: String
    let label: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? ReaderStyle.accent : .primary)
                .frame(width: 32, height: 32)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.borderless)
        .background(selected ? ReaderStyle.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .help(label).accessibilityLabel(label)
    }
}

struct KeyboardHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("손을 떼지 않고 읽기").font(.system(size: 16, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                shortcut("이전 / 다음 페이지", "←  →")
                shortcut("다음 페이지", "Space / Fn ↓")
                shortcut("이전 페이지", "Shift Space / Fn ↑")
                shortcut("첫 / 마지막 페이지", "Fn ← / Fn →")
                shortcut("페이지 안에서 스크롤", "↑  ↓")
                shortcut("읽기 화면으로", "⌘ ⇧ R")
            }
            Divider()
            Text("원문과 텍스트 보기에서 사용할 수 있습니다.\n메모와 검색어를 입력할 때는 글 편집에 쓰입니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
        }.padding(24).fixedSize()
    }
    private func shortcut(_ title: String, _ keys: String) -> some View {
        GridRow {
            Text(title).font(.system(size: 12))
            Text(keys).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}
