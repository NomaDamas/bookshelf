import SwiftUI
import PDFKit
import CryptoKit
import BookshelfCore

struct BookSidebar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "books.vertical").foregroundStyle(.secondary)
                Text("나의 서재").font(.system(size: 16, weight: .semibold))
                Spacer()
                if model.activeBook != nil {
                    ReaderIconButton(symbol: "scope", label: "현재 읽는 책 찾기") { model.revealCurrentBook() }
                }
                Text("\(model.books.count)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(ReaderStyle.muted, in: Capsule())
                    .accessibilityLabel("\(model.books.count)권")
            }.padding(.horizontal, 20).frame(height: ReaderStyle.toolbarHeight)
            ReaderSearchField(prompt: "제목 또는 분야 검색", label: "책 검색", text: $model.libraryQuery)
                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 16)
            HStack {
                Text(model.libraryQuery.isEmpty ? "책장" : "검색 결과")
                Spacer()
                if !model.libraryQuery.isEmpty { Text("\(model.filteredBooks.count)권").monospacedDigit() }
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.bottom, 8)
            if model.isImporting {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("PDF 목록을 읽고 있습니다.") }
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(16)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.filteredBooks) { book in
                            BookRow(book: book, currentPage: model.activeBook?.id == book.id ? model.page : nil) { model.selectBook(book) }
                                .id(book.id)
                        }
                    }.padding(.horizontal, 10).padding(.vertical, 2)
                }
                    .overlay {
                        if model.filteredBooks.isEmpty && !model.isImporting {
                            VStack(spacing: 10) {
                                Image(systemName: model.libraryQuery.isEmpty ? "books.vertical" : "magnifyingglass").font(.system(size: 24, weight: .light))
                                Text(model.libraryQuery.isEmpty ? "PDF를 추가해 서재를 시작하세요." : "검색한 책이 없습니다.")
                                    .font(.system(size: 12)).multilineTextAlignment(.center)
                            }.foregroundStyle(.secondary).padding(20).allowsHitTesting(false)
                        }
                    }
                    .onAppear { if let id = model.activeBook?.id { proxy.scrollTo(id, anchor: .center) } }
                    .onChange(of: model.libraryRevealRequest) { _, _ in
                        if let id = model.activeBook?.id {
                            Task { @MainActor in await Task.yield(); proxy.scrollTo(id, anchor: .center) }
                        }
                    }
            }
            ReaderHairline().padding(.horizontal, 16)
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                Text("이 Mac의 서재")
                Spacer()
                ReaderIconButton(symbol: "folder.badge.plus", label: "폴더 추가") { model.chooseFiles(folder: true) }
            }.font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.leading, 20).padding(.trailing, 12).frame(height: ReaderStyle.footerHeight)
        }.background(ReaderMaterial())
    }
}

private struct BookRow: View {
    let book: Book
    let currentPage: Int?
    let action: () -> Void
    @State private var hovering = false
    private var selected: Bool { currentPage != nil }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                BookThumbnail(book: book).frame(width: 34, height: 48)
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title).font(.system(size: ReaderTokens.controlFont, weight: selected ? .semibold : .medium))
                        .lineLimit(2).foregroundStyle(.primary)
                    if let currentPage {
                        Label("읽는 중  \(currentPage)쪽", systemImage: "book.fill")
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(ReaderStyle.accent).lineLimit(1)
                    } else {
                        Text(book.lastOpened > 0 ? "\(book.lastPage)쪽에서 이어 읽기" : book.displayCategory)
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if !FileAccess.hasLocalData(book.url) {
                    Image(systemName: "icloud.and.arrow.down").font(.system(size: 12)).foregroundStyle(.secondary)
                        .accessibilityLabel("iCloud 다운로드 필요")
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? ReaderStyle.selection : (hovering ? ReaderStyle.muted : .clear),
                            in: RoundedRectangle(cornerRadius: ReaderTokens.radiusLarge, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: ReaderTokens.radiusLarge))
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .help(book.title).accessibilityLabel(book.title).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(currentPage.map { "읽는 중, PDF \($0)쪽" } ?? book.displayCategory)
    }
}

struct BookThumbnail: View {
    let book: Book
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else { RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.12)).overlay(Image(systemName: "book.closed").foregroundStyle(.secondary)) }
        }.clipped().clipShape(RoundedRectangle(cornerRadius: 3))
            .task(id: book.activePath, priority: .utility) {
                let loaded = await BookCoverLoader.shared.cover(for: book)
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }
}

/// Serialize uncached cover rendering so opening a large library cannot launch
/// dozens of PDFKit parses alongside the book the user is trying to read.
private actor BookCoverLoader {
    static let shared = BookCoverLoader()
    private let cache = NSCache<NSString, NSImage>()
    func cover(for book: Book) -> NSImage? {
        guard !Task.isCancelled else { return nil }
        if let cover = cache.object(forKey: book.activePath as NSString) { return cover }
        let image: NSImage? = autoreleasepool {
            for source in [book.activePath, book.sourcePath] where source.hasPrefix(book.rootPath + "/") {
                let relative = String(source.dropFirst(book.rootPath.count + 1))
                for value in [relative, relative.decomposedStringWithCanonicalMapping] {
                    let digest = Insecure.SHA1.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined().prefix(20)
                    let cached = URL(fileURLWithPath: book.rootPath).appendingPathComponent(".bookshelf-cache/thumbs/\(digest).jpg")
                    if FileAccess.hasLocalData(cached), let cover = NSImage(contentsOf: cached) { return cover }
                }
            }
            guard !Task.isCancelled, book.isAvailable else { return nil }
            return PDFDocument(url: book.url)?.page(at: 0)?.thumbnail(of: CGSize(width: 90, height: 130), for: .mediaBox)
        }
        if let image { cache.countLimit = 80; cache.setObject(image, forKey: book.activePath as NSString) }
        return image
    }
}
