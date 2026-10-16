import SwiftUI
import BookshelfCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("readerAppearance") private var appearance = ReaderAppearance.system
    @Environment(\.dismiss) private var dismiss
    private var ocrReady: Bool { OCRService.executable() != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(ReaderStyle.muted, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusLarge))
                VStack(alignment: .leading, spacing: 4) {
                    Text("서재 설정").font(.system(size: 18, weight: .semibold))
                    Text("텍스트 인식과 AI 연결").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("완료") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(24)
            ReaderHairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Label("화면 모양", systemImage: "circle.lefthalf.filled").font(.system(size: 13, weight: .medium))
                        Spacer()
                        ReaderPicker(choices: ReaderAppearance.allCases.map { ($0.title, $0) }, selection: $appearance, label: "화면 모양")
                            .frame(width: 220, height: 28)
                    }
                    settingsSection("텍스트 인식", symbol: "text.viewfinder") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Apple Vision으로 글자를 인식해 선택하고 검색할 수 있는 PDF 사본을 만듭니다.")
                                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5)
                            HStack {
                                Text("인식 언어").font(.system(size: 13))
                                Spacer()
                                Picker("인식 언어", selection: $model.ocrLanguage) {
                                    Text("한국어").tag("kor")
                                    Text("English").tag("eng")
                                    Text("日本語").tag("jpn")
                                    Text("자동 감지").tag("und")
                                }.labelsHidden().frame(width: 150)
                                    .onChange(of: model.ocrLanguage) { _, value in try? model.store.setSetting("ocrLanguage", value: value) }
                            }
                            ReaderHairline()
                            HStack(spacing: 7) {
                                Image(systemName: ocrReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                                    .foregroundStyle(ocrReady ? Color.green : Color.orange)
                                Text(ocrReady ? "OCR 도구 준비됨" : "OCR 도구 설치 필요")
                                Spacer()
                                Link("설치 안내", destination: URL(string: "https://github.com/mkyt/OCRmyPDF-AppleOCR")!)
                            }.font(.system(size: 12))
                            Text("책 옵션에서 새로 인식하거나 기존 OCR을 개선할 수 있습니다. 결과를 원문과 비교한 뒤 사용할 사본을 선택하세요.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                        }
                    }
                    settingsSection("앱 내 대화와 외부 연결", symbol: "bubble.left.and.bubble.right") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(AgentRuntime.bridgeURL != nil ? "책 패널의 대화 탭에서 Claude 또는 Codex를 선택하고 공식 계정으로 연결할 수 있습니다. 학습 전용 영어 지침을 사용하고 답변은 질문의 언어를 따릅니다." : "CLI의 MCP 서버를 연결하면 책 찾기, 페이지 읽기, 본문 검색, 책별 메모 조회를 사용할 수 있습니다.")
                                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5)
                            HStack {
                                Label("읽기 전용 연결", systemImage: "lock").font(.system(size: 12)).foregroundStyle(.secondary)
                                Spacer()
                                Button("MCP 실행 명령 복사") {
                                    let url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/bookshelf-cli")
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString("\"\(url.path)\" mcp", forType: .string)
                                }.controlSize(.small)
                            }
                            Text(AgentRuntime.bridgeURL != nil ? "외부 CLI에서 서재에 접근하려면 위 MCP 명령을 사용할 수 있습니다. 앱의 대화 기록은 책별로 이 Mac에 보관됩니다." : "질문과 AI 답변은 연결한 CLI에서 이어갈 수 있습니다.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "internaldrive").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("메모와 설정은 이 Mac에 저장됩니다.").font(.system(size: 12))
                            Text("원본 PDF와 OCR 사본은 각 책의 폴더에 보관합니다.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Finder에서 보기") { NSWorkspace.shared.open(model.store.directory) }.controlSize(.small)
                    }.padding(.horizontal, 4)
                }.padding(24)
            }
        }.frame(width: 560, height: 650)
            .background(ReaderMaterial(material: .underWindowBackground)).tint(ReaderStyle.accent)
            .preferredColorScheme(appearance.colorScheme)
    }

    private func settingsSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .semibold))
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(ReaderStyle.panel, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusPanel, style: .continuous))
            .modifier(ReaderSurfaceBorder(radius: ReaderTokens.radiusPanel))
    }
}
