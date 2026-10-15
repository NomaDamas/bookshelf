import SwiftUI
import BookshelfCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("서재 설정").font(.title2.weight(.semibold)); Spacer(); Button("완료") { dismiss() }.keyboardShortcut(.defaultAction) }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Mac에서 텍스트 인식", systemImage: "text.viewfinder").font(.headline)
                    Text("Apple Vision으로 글자를 인식하고, 선택 가능한 텍스트가 있는 새 PDF를 만듭니다. 원본 파일은 보존합니다.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Picker("인식 언어", selection: $model.ocrLanguage) { Text("한국어").tag("kor"); Text("English").tag("eng"); Text("日本語").tag("jpn"); Text("자동 감지").tag("und") }.onChange(of: model.ocrLanguage) { _, value in try? model.store.setSetting("ocrLanguage", value: value) }
                    Label(OCRService.executable() == nil ? "OCR 도구 설치 필요" : "OCRmyPDF 실행 파일 확인됨", systemImage: OCRService.executable() == nil ? "exclamationmark.circle" : "checkmark.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("OCR 설치 안내 보기") { NSWorkspace.shared.open(URL(string: "https://github.com/mkyt/OCRmyPDF-AppleOCR")!) }.font(.system(size: 11))
                    Text("공개 Vision API의 accurate 모드 사용. 일부 페이지에만 텍스트가 있는 PDF는 나머지 페이지를 인식합니다.").font(.system(size: 10)).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Codex와 Claude Code에서 읽기", systemImage: "terminal").font(.headline)
                    Text("함께 제공되는 bookshelf-cli의 MCP 서버를 연결하면 책 찾기, 페이지 읽기, 본문 검색, 책별 메모 조회를 사용할 수 있습니다.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("이 버전은 외부 CLI에서 질문할 수 있는 읽기 전용 MCP를 제공합니다. 앱 안에서 AI 답변을 생성하지 않습니다.").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("MCP 실행 명령 복사") {
                        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/bookshelf-cli")
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\"\(url.path)\" mcp", forType: .string)
                    }.font(.system(size: 11))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            HStack { Label("메모와 설정 저장 위치", systemImage: "internaldrive").font(.system(size: 11)); Spacer(); Button("Finder에서 보기") { NSWorkspace.shared.open(model.store.directory) }.font(.system(size: 11)) }
            Text(model.store.directory.path).font(.system(size: 10)).foregroundStyle(.tertiary).textSelection(.enabled)
        }.padding(26).frame(width: 510)
    }
}
