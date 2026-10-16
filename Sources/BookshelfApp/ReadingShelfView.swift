import SwiftUI
import BookshelfCore

struct ReadingShelfView: View {
    @ObservedObject var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 440), spacing: 16, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("읽고 있는 책").font(.system(size: 24, weight: .semibold))
                        .accessibilityIdentifier("reading-shelf-heading")
                    Text("\(model.readingBooks.count)권, 최근 읽은 순")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.activeBook != nil {
                    Button { model.readingShelfVisible = false } label: {
                        Label("읽던 책으로", systemImage: "arrow.uturn.backward")
                    }.controlSize(.large).accessibilityLabel("읽던 책으로 돌아가기")
                }
            }.padding(28)
            ReaderHairline().padding(.horizontal, 28)
            if model.readingBooks.isEmpty { emptyShelf }
            else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(model.readingBooks) { book in
                            ReadingBookCard(book: book, current: model.activeBook?.id == book.id,
                                            open: { model.selectBook(book) },
                                            exclude: { model.setReadingMembership(book, included: false) })
                        }
                    }.padding(28)
                    HStack(spacing: 7) {
                        Image(systemName: "info.circle")
                        Text("책 메뉴에서 이 목록에 추가하거나 제외할 수 있습니다.")
                    }.font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28).padding(.bottom, 24)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyShelf: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
                .frame(width: 84, height: 84)
                .background(ReaderStyle.muted, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusPanel))
            Text("이어서 읽을 책을 모아보세요").font(.system(size: 20, weight: .medium))
            Text("서재에서 책을 열면 읽던 위치와 함께 여기에 표시됩니다.\n책 메뉴에서 읽는 중 목록에 직접 추가할 수도 있습니다.")
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(6).multilineTextAlignment(.center)
            Button("전체 책장 보기") { model.showLibrary() }.buttonStyle(.borderedProminent).controlSize(.large)
                .padding(.top, 6)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReadingBookCard: View {
    let book: Book
    let current: Bool
    let open: () -> Void
    let exclude: () -> Void
    @State private var hovering = false
    private var hasProgress: Bool { book.lastOpened > 0 && book.pageCount > 0 }
    private var progress: Double { hasProgress ? min(max(Double(book.lastPage) / Double(book.pageCount), 0), 1) : 0 }
    private var position: String { hasProgress ? "PDF \(book.lastPage) / \(book.pageCount)쪽" : "아직 읽기 전" }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        BookThumbnail(book: book).frame(width: 56, height: 80)
                            .shadow(color: .black.opacity(0.09), radius: 3, y: 2)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.title).font(.system(size: 16, weight: .semibold)).lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if current {
                                Label("지금 펼친 책", systemImage: "book.fill")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(ReaderStyle.accent)
                            } else {
                                Text(book.displayCategory).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.padding(.trailing, 16)
                    }.frame(height: 84, alignment: .top)
                    VStack(spacing: 8) {
                        HStack {
                            Text(position)
                            Spacer()
                            if hasProgress { Text("\(Int((progress * 100).rounded()))%").foregroundStyle(.secondary) }
                        }.font(.system(size: 12)).monospacedDigit()
                        ProgressView(value: progress).tint(ReaderStyle.accent).accessibilityHidden(true)
                    }
                    ReaderHairline()
                    HStack {
                        Label(hasProgress ? "이어 읽기" : "책 펼치기", systemImage: "arrow.up.right")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        if !FileAccess.hasLocalData(book.url) {
                            Image(systemName: "icloud.and.arrow.down").foregroundStyle(.secondary)
                                .accessibilityLabel("iCloud 다운로드 필요")
                        }
                    }
                }.foregroundStyle(.primary).padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ReaderStyle.panel, in: RoundedRectangle(cornerRadius: ReaderTokens.radiusPanel, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ReaderTokens.radiusPanel, style: .continuous)
                            .fill(hovering ? ReaderStyle.muted : .clear).allowsHitTesting(false)
                    }
                    .modifier(ReaderSurfaceBorder(radius: ReaderTokens.radiusPanel))
                    .contentShape(RoundedRectangle(cornerRadius: ReaderTokens.radiusPanel))
            }.buttonStyle(.plain).onHover { hovering = $0 }
                .accessibilityLabel("\(book.title) \(hasProgress ? "이어 읽기" : "책 펼치기")").accessibilityValue(position)
            Menu {
                Button("읽는 중 목록에서 제외", action: exclude)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14))
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(8)
                .accessibilityLabel("\(book.title) 읽는 중 목록 관리")
        }
    }
}
