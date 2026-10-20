import SwiftUI
import BookshelfCore

struct ReadingShelfView: View {
    @ObservedObject var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 440), spacing: 16, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.shelfStatus.title).font(.system(size: 24, weight: .semibold))
                        .accessibilityIdentifier("reading-shelf-heading")
                    Text("\(model.shelfBooks.count)권, \(model.sortPreferences.label)")
                        .font(.system(size: ReaderTokens.controlFont)).foregroundStyle(.secondary)
                }
                Spacer()
                LibrarySortMenu(model: model)
                if model.activeBook != nil {
                    Button("펼친 책으로") { model.readingShelfVisible = false }
                        .controlSize(.large).accessibilityLabel("펼친 책으로 돌아가기")
                }
            }.padding(28)
            ReaderHairline().padding(.horizontal, 28)
            if model.shelfBooks.isEmpty { emptyShelf }
            else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(model.shelfBooks) { book in ReadingBookCard(book: book, model: model) }
                    }.padding(28)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyShelf: some View {
        VStack(spacing: 16) {
            Image(systemName: model.shelfStatus.symbol).font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
                .frame(width: 84, height: 84)
                .background(ReaderStyle.muted, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusPanel))
            Text(model.libraryQuery.isEmpty ? emptyTitle : "검색한 책이 없습니다.")
                .font(.system(size: 20, weight: .medium))
            Text(model.libraryQuery.isEmpty ? emptyMessage : "검색어를 지우면 이 책장의 모든 책을 볼 수 있습니다.")
                .font(.system(size: ReaderTokens.controlFont)).foregroundStyle(.secondary).lineSpacing(6).multilineTextAlignment(.center)
            if !model.libraryQuery.isEmpty {
                Button("검색어 지우기") { model.libraryQuery = "" }.controlSize(.large)
            } else {
                Button("전체 책장 보기") { model.showLibrary() }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var emptyTitle: String {
        switch model.shelfStatus {
        case .unread: return model.books.isEmpty ? "서재에 책을 추가해보세요" : "모든 책의 읽기를 시작했어요"
        case .reading: return "이어서 읽을 책을 모아보세요"
        case .finished: return "한 권을 다 읽은 순간을 남겨보세요"
        }
    }
    private var emptyMessage: String {
        switch model.shelfStatus {
        case .unread: return "새로 추가한 PDF는 여기에 모입니다."
        case .reading: return "서재에서 책을 펼치거나 ‘읽기 시작’을 눌러보세요.\n읽던 위치와 회독 수를 함께 볼 수 있습니다."
        case .finished: return "책 메뉴에서 ‘읽기 완료’를 누르면 여기에 모입니다.\n다시 읽어도 이전 회독 기록은 남습니다."
        }
    }
}

private struct ReadingBookCard: View {
    let book: Book
    @ObservedObject var model: AppModel
    private var summary: ReadingSummary { model.readingSummary(book) }
    private var count: NoteCount { model.noteCount(book) }
    private var progress: Double { book.pageCount > 0 ? min(max(Double(book.lastPage) / Double(book.pageCount), 0), 1) : 0 }
    private var openLabel: String {
        switch summary.status {
        case .unread: return "책 펼치기"
        case .reading: return "이어 읽기"
        case .finished: return "다시 펼치기"
        }
    }
    private func open() {
        if summary.status == .unread { model.startReading(book) }
        else { model.selectBook(book) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 4) {
                Button(action: open) {
                    HStack(alignment: .top, spacing: 16) {
                        BookThumbnail(book: book).frame(width: 56, height: 80)
                            .shadow(color: .black.opacity(0.09), radius: 3, y: 2)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.title).font(.system(size: 16, weight: .semibold)).lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(model.activeBook?.id == book.id ? "지금 펼친 책" : book.displayCategory)
                                .font(.system(size: ReaderTokens.detailFont)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.frame(height: 84, alignment: .top).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(book.title) \(openLabel)")
                Menu { ReadingActions(model: model, book: book) } label: {
                    Image(systemName: "ellipsis").font(.system(size: ReaderTokens.bodyFont)).frame(width: 24, height: 28)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("\(book.title) 읽기 상태 변경")
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label(summary.label, systemImage: summary.status.symbol).font(.system(size: ReaderTokens.captionFont, weight: .medium))
                    Spacer()
                    if summary.status == .reading && book.pageCount > 0 {
                        Text("\(Int((progress * 100).rounded()))%").font(.system(size: ReaderTokens.captionFont)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if summary.status == .reading {
                    ProgressView(value: progress).tint(ReaderStyle.accent).accessibilityHidden(true)
                    Text(book.pageCount > 0 ? "PDF \(book.lastPage) / \(book.pageCount)쪽" : "페이지 확인 전")
                        .font(.system(size: ReaderTokens.detailFont)).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text(summary.lastCompletedAt.map { "최근 완료 " + Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted) }
                         ?? "읽기를 시작하면 진행 상황이 기록됩니다.")
                        .font(.system(size: ReaderTokens.detailFont)).foregroundStyle(.secondary)
                }
            }.frame(height: 60, alignment: .top)
            ReaderHairline()
            HStack(spacing: 8) {
                Button(action: open) { Label(openLabel, systemImage: "book.pages").font(.system(size: ReaderTokens.captionFont, weight: .medium)) }
                    .buttonStyle(.plain).accessibilityLabel("\(book.title) \(openLabel)")
                Spacer(minLength: 4)
                if !FileAccess.hasLocalData(book.url) {
                    Image(systemName: "icloud.and.arrow.down").foregroundStyle(.secondary).accessibilityLabel("iCloud 다운로드 필요")
                }
                if count.total > 0 {
                    Button { model.showNotes(book) } label: {
                        HStack(spacing: 5) { Image(systemName: "note.text").foregroundStyle(.secondary); NoteCountBadge(count: count) }
                    }.buttonStyle(.plain).help(count.description)
                        .accessibilityLabel("\(book.title) 메모 \(count.total)개 보기")
                }
            }.frame(height: 24)
        }.foregroundStyle(.primary).padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(ReaderStyle.panel, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusPanel, style: .continuous))
            .modifier(ReaderSurfaceBorder(radius: ReaderTokens.radiusPanel))
    }
}
