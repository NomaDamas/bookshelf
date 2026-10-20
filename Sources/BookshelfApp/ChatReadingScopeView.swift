import SwiftUI
import BookshelfCore

struct ChatPageRangeEditor: View {
    let pageCount: Int
    let currentPage: Int
    let selected: ClosedRange<Int>?
    let apply: (ClosedRange<Int>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var first = ""
    @State private var last = ""
    private var range: ClosedRange<Int>? {
        guard let a = Int(first), let b = Int(last), a >= 1, b >= a, b <= pageCount else { return nil }
        return a...b
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("질문할 페이지 범위").font(.headline)
            Text("PDF 페이지 번호로 지정합니다. AI는 이 범위 안에서만 본문을 찾고 읽습니다.").font(.system(size: ReaderTokens.captionFont)).foregroundStyle(.secondary)
            HStack {
                TextField("시작 쪽", text: $first).accessibilityLabel("질문 범위 시작 페이지")
                Text("~")
                TextField("끝 쪽", text: $last).accessibilityLabel("질문 범위 끝 페이지")
            }.textFieldStyle(.roundedBorder)
            Text("1~\(pageCount)쪽 중에서 선택해 주세요.").font(.caption).foregroundStyle(range == nil ? .orange : .secondary)
            HStack { Spacer(); Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("범위 적용") { if let range { apply(range); dismiss() } }.buttonStyle(.borderedProminent).disabled(range == nil).keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 370)
            .onAppear { first = String(selected?.lowerBound ?? currentPage); last = String(selected?.upperBound ?? min(pageCount, currentPage + 4)) }
    }
}

struct ChatReadingSources: View {
    let reading: BookReadingCoverage
    let selectPage: (Int) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(reading.scope.title) / 본문 \(reading.readPages.count)/\(reading.scope.pageCount)쪽 확인")
                .font(.system(size: ReaderTokens.footnoteFont)).foregroundStyle(.secondary)
                .help("본문을 끝까지 읽은 쪽 수입니다. 검색 결과의 일부 문장만 본 페이지는 포함하지 않습니다.")
            if !reading.emptyPages.isEmpty {
                Text("텍스트가 없는 페이지 \(reading.emptyPages.count)쪽").font(.system(size: ReaderTokens.footnoteFont)).foregroundStyle(.orange)
            }
            if !reading.sourcePages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(reading.sourcePages, id: \.self) { page in
                            Button("\(page)쪽") { selectPage(page) }.buttonStyle(.bordered).controlSize(.mini)
                                .accessibilityLabel("출처 \(page)쪽으로 이동")
                        }
                    }
                }.frame(height: 24)
            }
        }.padding(.top, 4)
    }
}
