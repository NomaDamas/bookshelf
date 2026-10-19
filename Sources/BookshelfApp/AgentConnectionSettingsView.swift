import SwiftUI
import BookshelfCore

struct ChatModelMenu: View {
    @ObservedObject var chat: BookChatModel
    var openSettings: (() -> Void)?
    var body: some View {
        Menu {
            ForEach(ChatBackend.allCases) { backend in
                Section(backend == .claude ? "Claude Code" : "Codex") {
                    choice("자동 선택", id: "", backend: backend)
                    ForEach(chat.models[backend] ?? []) { option in choice(option.label, id: option.id, backend: backend) }
                }
            }
            if let openSettings { Divider(); Button("연결 설정…", action: openSettings) }
        } label: {
            Text("\(chat.backend.title) / \(chat.modelTitle)").font(.system(size: 12, weight: .medium)).lineLimit(1)
        }.menuStyle(.borderlessButton).frame(maxWidth: 170, alignment: .leading)
            .accessibilityLabel("AI 모델 선택").disabled(chat.busy)
    }
    private func choice(_ label: String, id: String, backend: ChatBackend) -> some View {
        Button {
            chat.chooseBackend(backend); chat.chooseModel(id)
        } label: {
            if chat.backend == backend && chat.selectedModel == id { Label(label, systemImage: "checkmark") }
            else { Text(label) }
        }
    }
}

struct AgentConnectionSettingsView: View {
    @ObservedObject var chat: BookChatModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Pi 학습 에이전트 사용", isOn: Binding(get: { chat.usePi }, set: { chat.setPi($0) }))
                .toggleStyle(.switch).disabled(chat.busy)
            Text("책과 대화 기록을 바탕으로 설명합니다. 계정 연결은 각 서비스의 공식 로그인으로 진행합니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            ReaderHairline()
            ForEach(ChatBackend.allCases) { backend in
                HStack(spacing: 12) {
                    Image(systemName: chat.accounts[backend]?.connected == true ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(chat.accounts[backend]?.connected == true ? Color.green : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(backend == .claude ? "Claude Code" : "Codex").font(.system(size: 13, weight: .medium))
                        Text(chat.accounts[backend]?.label ?? "연결 확인 전").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(chat.accounts[backend]?.connected == true ? "다시 연결" : "연결") { chat.login(using: backend) }
                        .controlSize(.small).disabled(chat.busy || !AgentRuntime.ready)
                        .accessibilityLabel(backend.title + " 계정 연결")
                }
            }
            if chat.operation == "login" {
                HStack { ProgressView().controlSize(.small); Text("브라우저에서 로그인을 완료해 주세요.").font(.caption)
                    if let url = chat.loginURL { Link("로그인 열기", destination: url) }
                    Button("취소") { chat.stop() }.controlSize(.small)
                }
            }
            if let error = chat.errorMessage { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            ReaderHairline()
            HStack {
                Text("대화 모델").font(.system(size: 13))
                Spacer(); ChatModelMenu(chat: chat)
            }
            HStack {
                if !AgentRuntime.ready { Text("Node.js와 공식 실행기를 설치해야 연결할 수 있습니다.").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("연결 상태 확인") { Task { await chat.refreshConnections() } }.controlSize(.small).disabled(chat.busy)
            }
        }.task { await chat.refreshConnections() }
    }
}
