import SwiftUI
import AVKit
import Combine
import BookshelfCore

/// Equatable so a streamed delta re-parses only the reply whose text changed. `selectPage` is left out:
/// SwiftUI cannot compare closures, and a reply's view stays with the book its message belongs to.
struct ChatResponseView: View, Equatable {
    let text: String
    var streaming = false
    var sourcePages: Set<Int> = []
    var selectPage: ((Int) -> Void)?
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.streaming == rhs.streaming && lhs.sourcePages == rhs.sourcePages
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ChatContent.blocks(text)) { block in
                switch block.kind {
                case "mermaid", "svg", "html":
                    if block.complete { ChatArtifactView(kind: block.kind, source: block.source) }
                    else if streaming { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("시각 자료를 구성하고 있습니다.").font(.system(size: 12)).foregroundStyle(.secondary) }.padding(14) }
                    else { code(block.source, title: "시각 자료의 닫는 코드 표시를 확인해 주세요.") }
                case "code": code(block.source, title: block.label)
                case "image", "audio", "video": RemoteChatMedia(source: block.source, title: block.label, kind: block.kind)
                default: ChatMarkdownText(text: block.source, sourcePages: sourcePages).textSelection(.enabled)
                }
            }
        }.environment(\.openURL, OpenURLAction { url in
            if let page = ChatCitations.page(in: url, allowed: sourcePages) { selectPage?(page); return .handled }
            return ["https", "http"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
        })
    }
    private func code(_ value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty { Text(title).font(.system(size: 10)).foregroundStyle(.secondary) }
            ScrollView(.horizontal) { Text(value).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(ReaderStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ChatAttachmentView: View {
    let attachment: ChatAttachment
    let directory: URL
    var body: some View {
        if let url = ChatAssetStore.url(for: attachment, directory: directory) {
            VStack(alignment: .leading, spacing: 8) {
                Text(attachment.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                if ["mermaid", "html", "svg"].contains(attachment.kind) {
                    if let source = try? String(contentsOf: url, encoding: .utf8) { ChatArtifactView(kind: attachment.kind, source: source) }
                    else { Text("UTF-8 자료로 열 수 없습니다.").font(.caption).foregroundStyle(.secondary) }
                } else { ChatMediaPlayer(url: url, kind: attachment.kind) }
            }
        } else { Label("자료 파일을 찾을 수 없습니다.", systemImage: "doc.questionmark").font(.caption).foregroundStyle(.secondary) }
    }
}

private struct RemoteChatMedia: View {
    let source: String
    let title: String
    let kind: String
    @State private var loaded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = URL(string: source), url.scheme == "https", url.host != nil {
                if loaded { ChatMediaPlayer(url: url, kind: kind) }
                else {
                    Button { loaded = true } label: {
                        Label(title.isEmpty ? (kind == "audio" ? "음성 불러오기" : "시각 자료 불러오기") : title,
                              systemImage: kind == "audio" ? "waveform" : "photo")
                    }.buttonStyle(.bordered)
                    Text(url.host ?? "").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else {
                Label(title.isEmpty ? "로컬 자료" : title, systemImage: "doc").font(.system(size: 12))
                Text("자료 열기 버튼으로 파일을 선택하면 이 대화에서 볼 수 있습니다.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatMediaPlayer: View {
    let url: URL
    let kind: String
    @State private var imageExpanded = false
    var body: some View {
        if kind == "image" {
            Button { imageExpanded = true } label: { mediaImage.scaledToFit().frame(maxHeight: 300) }.buttonStyle(.plain)
                .accessibilityLabel("이미지 크게 보기")
                .sheet(isPresented: $imageExpanded) {
                    VStack { HStack {
                        Text("이미지").font(.headline); Spacer()
                        if url.isFileURL {
                            Button("복사") { if let image = NSImage(contentsOf: url) { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image]) } }
                                .accessibilityLabel("이미지 복사")
                            Button("저장…", action: saveImage).accessibilityLabel("이미지 저장")
                        }
                        Button("닫기") { imageExpanded = false }.keyboardShortcut(.cancelAction)
                    }; mediaImage.scaledToFit() }
                        .padding(20).frame(minWidth: 660, idealWidth: 900, minHeight: 500, idealHeight: 700)
                }
        } else { NativeMediaPlayback(url: url, video: kind == "video") }
    }
    private func saveImage() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "생성 이미지." + url.pathExtension
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let destination = panel.url else { return }
            do { try Data(contentsOf: url).write(to: destination, options: .atomic) }
            catch { NSAlert(error: error).runModal() }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    @ViewBuilder private var mediaImage: some View {
        if url.isFileURL, let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable() }
        else {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable() }
                else if phase.error != nil { Label("이미지를 불러오지 못했습니다.", systemImage: "photo.badge.exclamationmark").font(.caption) }
                else { ProgressView().frame(height: 100) }
            }
        }
    }
}

private struct NativeMediaPlayback: View {
    let url: URL
    let video: Bool
    @State private var player: AVPlayer?
    @State private var position = 0.0
    @State private var duration = 0.0
    @State private var playing = false
    @State private var rate: Float = 1
    @State private var error: String?
    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if video, let player { VideoPlayer(player: player).frame(height: 240) }
            HStack(spacing: 12) {
                Button {
                    guard let player else { return }
                    if playing { player.pause() } else {
                        if duration > 0 && position >= duration - 0.1 { player.seek(to: .zero) }
                        player.playImmediately(atRate: rate)
                    }
                    playing.toggle()
                } label: { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 30, height: 30) }
                    .buttonStyle(.borderless).accessibilityLabel(playing ? "음성 일시정지" : "음성 재생").disabled(player == nil || error != nil)
                VStack(spacing: 4) {
                    Slider(value: Binding(get: { position }, set: { value in position = value; player?.seek(to: CMTime(seconds: value, preferredTimescale: 600)) }), in: 0...max(duration, 1))
                        .disabled(duration <= 0).accessibilityLabel("재생 위치")
                    HStack { Text(clock(position)); Spacer(); Text(clock(duration)) }.font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                }
                Picker("재생 속도", selection: $rate) { ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { Text("\(Double($0).formatted())x").tag($0) } }
                    .labelsHidden().frame(width: 68).controlSize(.small)
                    .onChange(of: rate) { _, value in if playing { player?.rate = value } }
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.secondary) }
        }.padding(10).background(ReaderStyle.muted, in: RoundedRectangle(cornerRadius: 10))
            .task(id: url) {
                let asset = AVURLAsset(url: url); player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                do {
                    let value = try await asset.load(.duration).seconds
                    guard !Task.isCancelled else { return }
                    duration = value.isFinite ? max(0, value) : 0
                } catch { self.error = "이 미디어를 불러오지 못했습니다." }
            }
            .onReceive(ticker) { _ in
                guard let player else { return }
                let value = player.currentTime().seconds
                if value.isFinite { position = max(0, value) }
                playing = player.rate > 0
                if player.currentItem?.status == .failed { error = "이 미디어 형식을 재생할 수 없습니다." }
            }
            .onDisappear { player?.pause(); playing = false }
    }
    private func clock(_ value: Double) -> String { let seconds = Int(max(0, value)); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
}
