import SwiftUI
import BookshelfCore

struct ChatModelMenu: View {
    @ObservedObject var chat: BookChatModel
    var body: some View {
        Menu {
            ForEach(ChatBackend.allCases) { backend in
                Section(backend.title) {
                    choice("자동", id: "", backend: backend)
                    ForEach(chat.models[backend] ?? []) { option in choice(option.label, id: option.id, backend: backend) }
                }
            }
        } label: {
            Text("\(chat.backend.title) / \(chat.modelTitle)").font(.system(size: 12, weight: .medium)).lineLimit(1)
        }.menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("실행기와 모델").accessibilityValue("\(chat.backend.title) / \(chat.modelTitle)")
            .help("Pi가 답변에 쓸 실행기와 모델")
            .disabled(chat.busy)
    }
    private func choice(_ label: String, id: String, backend: ChatBackend) -> some View {
        PiMenuChoice(title: label, selected: chat.backend == backend && chat.selectedModel == id) {
            chat.chooseBackend(backend); chat.chooseModel(id)
        }
    }
}

struct AgentConnectionSettingsView: View {
    @ObservedObject var chat: BookChatModel
    private func executor(_ backend: ChatBackend) -> String { backend == .claude ? "Claude Code" : "Codex" }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pi는 이 책과 대화 기록을 바탕으로 설명합니다. 답변은 아래에서 연결한 Claude Code 또는 Codex 계정으로 받습니다. 계정 연결은 각 서비스의 공식 로그인으로 진행합니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            ReaderHairline()
            ForEach(ChatBackend.allCases) { backend in
                HStack(spacing: 12) {
                    Image(systemName: chat.accounts[backend]?.connected == true ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(chat.accounts[backend]?.connected == true ? Color.green : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(executor(backend)).font(.system(size: 13, weight: .medium))
                            if chat.backend == backend { Text("대화에 사용 중").font(.system(size: 10)).foregroundStyle(.secondary) }
                        }
                        Text(chat.accounts[backend]?.label ?? (chat.checkingStatus ? "확인하고 있습니다" : "연결 확인 전")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(chat.accounts[backend]?.connected == true ? "다시 연결" : "연결") { chat.login(using: backend) }
                        .controlSize(.small).disabled(chat.busy || !AgentRuntime.ready)
                        .accessibilityLabel(executor(backend) + " 계정 연결")
                        .help("\(executor(backend)) 공식 로그인을 엽니다. 대화에 쓰는 실행기는 바뀌지 않습니다.")
                }
            }
            if chat.operation == "login" {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("브라우저에서 \(executor(chat.loginBackend ?? chat.backend)) 로그인을 완료해 주세요.").font(.caption)
                    if let url = chat.loginURL { Link("로그인 열기", destination: url) }
                    Button("취소") { chat.stop() }.controlSize(.small)
                }
            }
            if let error = chat.errorMessage {
                HStack(alignment: .top) {
                    Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button { chat.errorMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("오류 닫기").help("오류 닫기")
                }
            }
            ReaderHairline()
            HStack {
                Text("대화 실행기와 모델").font(.system(size: 13))
                Spacer(); ChatModelMenu(chat: chat)
            }
            HStack {
                if !AgentRuntime.ready { Text("Node.js와 공식 실행기를 설치해야 연결할 수 있습니다.").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if chat.checkingStatus { ProgressView().controlSize(.small) }
                // Rechecking also looks for Node.js again, so an install made while the app runs shows up.
                Button("연결 상태 확인") { AgentRuntime.node.refresh(); Task { await chat.refreshConnections() } }.controlSize(.small).disabled(chat.busy || chat.checkingStatus)
            }
            ReaderHairline()
            Toggle(isOn: Binding(get: { !chat.usePi }, set: { chat.setPi(!$0) })) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pi 계층을 끄고 실행기에 직접 요청").font(.system(size: 13))
                    Text("답변을 비교할 때 쓰는 고급 설정입니다. 끄면 Pi가 대화를 관리합니다.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch).disabled(chat.busy)
        }.task { AgentRuntime.node.refresh(); await chat.refreshConnections() }
    }
}
