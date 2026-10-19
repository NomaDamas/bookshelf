import SwiftUI
import BookshelfCore

struct NoteCountBadge: View {
    let count: NoteCount
    var body: some View {
        if count.total > 0 {
            Text(count.badge).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white).padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                .background(Color(red: 0.79, green: 0.13, blue: 0.18), in: Capsule())
                .accessibilityLabel("메모 \(count.total)개").help(count.description)
        }
    }
}

struct ReadingActions: View {
    @ObservedObject var model: AppModel
    let book: Book
    private var summary: ReadingSummary { model.readingSummary(book) }
    var body: some View {
        if summary.status != .reading {
            Button(summary.completedCount > 0 ? "다시 읽기 시작" : "읽기 시작", systemImage: "book") { model.startReading(book) }
        }
        if summary.status != .finished {
            Button("읽기 완료", systemImage: "checkmark.circle") { model.completeReading(book) }
        }
        if summary.status == .reading {
            Button(summary.completedCount > 0 ? "이번 다시 읽기 취소" : "읽기 전으로 옮기기") { model.shelveReading(book) }
        }
        if summary.status == .finished {
            Button("최근 완료 기록 취소") { model.undoReadingCompletion(book) }
        }
        Divider()
        Button("회독 기록 보기", systemImage: "clock") { model.showReadingHistory(book) }
    }
}

struct ReadingHistoryView: View {
    @ObservedObject var model: AppModel
    let book: Book
    @Environment(\.dismiss) private var dismiss
    private var summary: ReadingSummary { model.readingSummary(book) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("회독 기록").font(.system(size: 22, weight: .semibold))
                    Text(book.title).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Label(summary.label, systemImage: summary.status.symbol).font(.system(size: 14, weight: .medium))
                Spacer()
                if summary.status == .reading && summary.completedCount > 0 {
                    Text("\(summary.completedCount)회독 완료").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            ReaderHairline()
            if model.historyEntries.isEmpty {
                Text("아직 완료한 회독이 없습니다.\n책을 다 읽고 ‘읽기 완료’를 누르면 날짜와 함께 기록됩니다.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(6).padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.historyEntries.enumerated()), id: \.element.id) { index, entry in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("\(model.historyEntries.count - index)회독 완료").font(.system(size: 14, weight: .medium))
                                    Text(Date(timeIntervalSince1970: entry.completedAt).formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 12)).foregroundStyle(.secondary)
                                    if let started = entry.startedAt {
                                        Text("시작: " + Date(timeIntervalSince1970: started).formatted(date: .abbreviated, time: .omitted))
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if index == 0 && summary.status == .finished {
                                    Button("완료 취소") { model.undoReadingCompletion(book) }.controlSize(.small)
                                        .help("최근 완료 기록을 취소하고 읽는 중으로 옮깁니다.")
                                }
                            }.padding(.vertical, 16)
                            ReaderHairline()
                        }
                    }
                }.frame(maxHeight: 360)
            }
        }.padding(28).frame(width: 480)
    }
}
