import SwiftUI
import PDFKit
import BookshelfCore

struct OCRReview: Identifiable {
    let id = UUID()
    let book: Book
    let result: OCRResult
}

struct OCRReviewView: View {
    @ObservedObject var model: AppModel
    let review: OCRReview
    @State private var page = 1
    @State private var pageEntry = "1"
    @State private var display = "text"
    @State private var phrase = ""
    @State private var beforeText = ""
    @State private var afterText = ""
    @State private var confirmed = false
    private var quality: OCRQuality { review.result.quality }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary).frame(width: 44, height: 44)
                    .background(ReaderStyle.muted, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusLarge))
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(review.result.mode.title) 결과").font(.system(size: 18, weight: .semibold))
                    Text(review.book.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text("\(quality.textPages) / \(quality.pageCount)쪽 텍스트 확인").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                metric("공백 의심", count: quality.spacingSuspectPages.count)
                metric("텍스트 감소", count: quality.textLossPages.count)
                if !(quality.textGrowthPages ?? []).isEmpty { metric("텍스트 급증", count: quality.textGrowthPages?.count ?? 0) }
                metric("추출 결과 차이", count: quality.extractorDisagreementPages.count)
                    .help("서로 다른 PDF 추출기에서 글자나 읽는 순서가 다르게 나온 페이지입니다.")
                if !quality.renderingMismatchPages.isEmpty { metric("화면 차이", count: quality.renderingMismatchPages.count) }
                Spacer()
                Text("화면 비교 \(quality.renderedPages.count)쪽 통과").font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(14)
                .background(ReaderStyle.panel, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusLarge, style: .continuous))
                .modifier(ReaderSurfaceBorder())
            Text(quality.popplerChecked
                ? "전체 페이지의 공백과 두 추출기의 결과를 대조했습니다. 화면 비교는 표본 검사입니다. 아래에서 문구와 읽는 순서를 확인해 주세요."
                : "이 Mac에서는 추가 추출기 검사를 하지 못했습니다. 아래에서 공백, 문구와 읽는 순서를 확인해 주세요.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                ReaderPicker(choices: [("텍스트 비교", "text"), ("PDF 확인", "pdf")], selection: $display, label: "비교 화면")
                    .frame(width: 210, height: 28)
                Spacer()
                Menu("확인할 페이지") {
                    ForEach(quality.reviewPages.prefix(80), id: \.self) { number in Button("\(number)쪽") { page = number } }
                }.fixedSize()
                TextField("쪽", text: $pageEntry).textFieldStyle(.roundedBorder).frame(width: 52)
                    .accessibilityLabel("OCR 비교 페이지 번호")
                    .onSubmit { page = min(max(Int(pageEntry) ?? page, 1), quality.pageCount); pageEntry = String(page) }
                Text("/ \(quality.pageCount)").font(.system(size: 12)).foregroundStyle(.secondary)
                Stepper("페이지", value: $page, in: 1...max(1, quality.pageCount)).labelsHidden().fixedSize()
            }
            HStack(spacing: 12) {
                comparison("현재 PDF", text: beforeText, url: URL(fileURLWithPath: review.result.sourcePath))
                comparison("새 OCR 사본", text: afterText, url: URL(fileURLWithPath: review.result.path))
            }.frame(maxHeight: .infinity)
            HStack {
                ReaderSearchField(prompt: "원문 문구를 입력해 이 페이지에서 검색", label: "OCR 검증 문구", text: $phrase)
                if !phrase.isEmpty {
                    Label(afterText.contains(phrase) ? "문구 일치" : "일치하지 않음", systemImage: afterText.contains(phrase) ? "checkmark.circle" : "magnifyingglass")
                        .foregroundStyle(afterText.contains(phrase) ? Color.green : Color.orange).font(.system(size: 12)).frame(width: 110)
                }
            }
            if quality.needsReview {
                Toggle("확인이 필요한 페이지를 검토했습니다", isOn: $confirmed).font(.system(size: 12))
                    .toggleStyle(.checkbox)
            }
            ReaderHairline()
            HStack {
                Button("검사 기록") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: review.result.reportPath)]) }
                Spacer()
                Button("기존 PDF 유지") { model.keepOriginalOCR() }.keyboardShortcut(.cancelAction)
                Button("이 결과 사용") { model.acceptOCRReview() }.buttonStyle(.borderedProminent)
                    .disabled(quality.needsReview && !confirmed).keyboardShortcut(.return, modifiers: [.command])
            }
            Text("원본 파일과 책별 메모는 보존됩니다. 생성한 사본은 ‘기존 PDF 유지’를 눌러도 저장 위치에 남습니다.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(24).frame(width: 920, height: 720)
            .background(ReaderMaterial(material: .underWindowBackground)).tint(ReaderStyle.accent)
            .interactiveDismissDisabled()
            .onAppear { page = quality.reviewPages.first ?? 1; loadText() }
            .onChange(of: page) { _, _ in pageEntry = String(page); loadText() }
    }
    private func metric(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) { Text(title).foregroundStyle(.secondary); Text("\(count)쪽").fontWeight(.medium).foregroundStyle(count > 0 ? Color.orange : Color.primary) }.font(.system(size: 12))
    }
    private func comparison(_ title: String, text: String, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(title, systemImage: title == "현재 PDF" ? "doc" : "doc.text")
                Spacer()
                Text("\(page)쪽").monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 16).frame(height: 38)
            ReaderHairline()
            if display == "pdf" { OCRPagePreview(url: url, page: page) }
            else {
                ScrollView { Text(text.isEmpty ? "추출된 텍스트가 없습니다." : text).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14) }
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ReaderStyle.panel)
            .clipShape(RoundedRectangle(cornerRadius: ReaderTokens.radiusLarge, style: .continuous))
            .modifier(ReaderSurfaceBorder())
    }
    private func loadText() {
        beforeText = PDFDocument(url: URL(fileURLWithPath: review.result.sourcePath))?.page(at: page - 1)?.string ?? ""
        afterText = PDFDocument(url: URL(fileURLWithPath: review.result.path))?.page(at: page - 1)?.string ?? ""
    }
}

private struct OCRPagePreview: NSViewRepresentable {
    let url: URL
    let page: Int
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.displayMode = .singlePage; view.autoScales = true; return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
        if let target = view.document?.page(at: page - 1) { view.go(to: target) }
        view.autoScales = true
    }
}
