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
            List(model.filteredBooks) { book in
                BookRow(book: book, selected: model.activeBook?.id == book.id) { model.selectBook(book) }
                    .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }.listStyle(.plain).scrollContentBackground(.hidden)
                .overlay {
                    if model.filteredBooks.isEmpty && !model.isImporting {
                        VStack(spacing: 10) {
                            Image(systemName: model.libraryQuery.isEmpty ? "books.vertical" : "magnifyingglass").font(.system(size: 24, weight: .light))
                            Text(model.libraryQuery.isEmpty ? "PDF를 추가해 서재를 시작하세요." : "검색한 책이 없습니다.")
                                .font(.system(size: 12)).multilineTextAlignment(.center)
                        }.foregroundStyle(.secondary).padding(20).allowsHitTesting(false)
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
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                BookThumbnail(book: book).frame(width: 34, height: 48)
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title).font(.system(size: ReaderTokens.controlFont, weight: selected ? .semibold : .medium))
                        .lineLimit(2).foregroundStyle(.primary)
                    Text(book.lastOpened > 0 ? "\(book.lastPage)쪽에서 이어 읽기" : book.displayCategory)
                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if !book.isAvailable {
                    Image(systemName: "icloud.and.arrow.down").font(.system(size: 12)).foregroundStyle(.secondary)
                        .accessibilityLabel("iCloud 다운로드 필요")
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? ReaderStyle.selection : (hovering ? ReaderStyle.muted : .clear),
                            in: RoundedRectangle(cornerRadius: ReaderTokens.radiusLarge, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: ReaderTokens.radiusLarge))
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .help(book.title).accessibilityLabel(book.title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct BookThumbnail: View {
    let book: Book
    @State private var image: NSImage?
    private static let cache = NSCache<NSString, NSImage>()
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else { RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.12)).overlay(Image(systemName: "book.closed").foregroundStyle(.secondary)) }
        }.clipped().clipShape(RoundedRectangle(cornerRadius: 3))
            .task(id: book.activePath) {
                if let cached = Self.cache.object(forKey: book.activePath as NSString) { image = cached; return }
                let b = book
                let loaded = await Task.detached(priority: .utility) { () -> NSImage? in
                    autoreleasepool {
                        for source in [b.activePath, b.sourcePath] where source.hasPrefix(b.rootPath + "/") {
                            let relative = String(source.dropFirst(b.rootPath.count + 1))
                            for value in [relative, relative.decomposedStringWithCanonicalMapping] {
                                let digest = Insecure.SHA1.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined().prefix(20)
                                let cached = URL(fileURLWithPath: b.rootPath).appendingPathComponent(".bookshelf-cache/thumbs/\(digest).jpg")
                                if FileAccess.isResident(cached), let cover = NSImage(contentsOf: cached) { return cover }
                            }
                        }
                        guard b.isAvailable else { return nil }
                        return PDFDocument(url: b.url)?.page(at: 0)?.thumbnail(of: CGSize(width: 90, height: 130), for: .mediaBox)
                    }
                }.value
                guard !Task.isCancelled else { return }
                if let loaded { Self.cache.countLimit = 80; Self.cache.setObject(loaded, forKey: book.activePath as NSString); image = loaded }
            }
    }
}
