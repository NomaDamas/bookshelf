import SwiftUI
import BookshelfCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("readerAppearance") private var appearance = ReaderAppearance.system
    private var ocrReady: Bool { OCRService.executable() != nil }

    // A TabView in the Settings scene gives the standard toolbar tabs; the window title follows the tab.
    var body: some View {
        TabView(selection: $model.settingsTab) {
            page { general }.tabItem { Label("일반", systemImage: "gearshape") }.tag("general")
            page { ai }.tabItem { Label("AI 연결", systemImage: "bubble.left.and.bubble.right") }.tag("ai")
            page { shortcuts }.tabItem { Label("단축키", systemImage: "keyboard") }.tag("shortcuts")
        }.frame(width: 560, height: 600)
            .tint(ReaderStyle.accent)
            .preferredColorScheme(appearance.colorScheme)
    }

    private func page(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) { content() }.padding(24) }
    }

    @ViewBuilder private var general: some View {
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
                Text("툴바의 책 제목 메뉴나 책 메뉴에서 새로 인식하거나 기존 OCR을 개선할 수 있습니다. 결과를 원문과 비교한 뒤 사용할 사본을 선택하세요.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
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
    }

    @ViewBuilder private var ai: some View {
        if AgentRuntime.bridgeURL != nil {
            settingsSection("Pi와 모델 연결", symbol: "bubble.left.and.bubble.right") { AgentConnectionSettingsView(chat: model.chat) }
        }
        settingsSection("외부 CLI / MCP", symbol: "link") {
            VStack(alignment: .leading, spacing: 14) {
                Text("외부 CLI의 MCP 서버를 연결하면 책 찾기, 페이지 읽기, 본문 검색, 책별 메모 조회를 사용할 수 있습니다.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5)
                HStack {
                    Label("읽기 전용 연결", systemImage: "lock").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("MCP 실행 명령 복사") {
                        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/bookside-cli")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\"\(url.path)\" mcp", forType: .string)
                    }.controlSize(.small)
                }
                Text(AgentRuntime.bridgeURL != nil ? "외부 CLI에서 서재에 접근하려면 위 MCP 명령을 사용할 수 있습니다. 앱의 대화 기록은 책별로 이 Mac에 보관됩니다." : "질문과 AI 답변은 연결한 CLI에서 이어갈 수 있습니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var shortcuts: some View {
        HStack {
            Text("버튼을 클릭한 뒤 사용할 키를 누르세요. Escape로 취소하고 Delete로 비울 수 있습니다.").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Button("모두 기본값으로") { model.resetShortcuts() }.controlSize(.small)
        }
        if let error = model.shortcutError { Text(error).font(.caption).foregroundStyle(.orange) }
        ForEach(ShortcutGroup.allCases) { group in
            settingsSection(group.title, symbol: group.symbol) {
                ForEach(group.actions) { action in shortcutRow(action) }
            }
        }
    }

    private func shortcutRow(_ action: ReaderAction) -> some View {
        HStack(spacing: 6) {
            Text(action.title).font(.system(size: 13))
            Spacer()
            ShortcutRecorder(label: model.shortcuts[action].label, action: action.title) { model.setShortcut($0, for: action) }
                .frame(width: 140, height: 28)
            Menu {
                Button("기본값으로 되돌리기 (\(action.defaultBinding.label))") { model.restoreShortcut(action) }
                    .disabled(model.shortcuts[action] == action.defaultBinding)
                Button("단축키 없음") { model.setShortcut(AppKeyBinding.unassigned, for: action) }
                    .disabled(model.shortcuts[action].isUnassigned)
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("\(action.title) 단축키 옵션")
        }
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
