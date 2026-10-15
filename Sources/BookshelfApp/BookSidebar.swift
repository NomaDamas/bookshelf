import SwiftUI
import PDFKit
import CryptoKit
import BookshelfCore

struct BookSidebar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("나의 서재").font(.system(size: 16, weight: .semibold)); Text("\(model.books.count)").font(.system(size: 11)).foregroundStyle(.secondary); Spacer() }.padding(18)
            TextField("책 찾아보기", text: $model.libraryQuery).textFieldStyle(.roundedBorder).padding(.horizontal, 14).padding(.bottom, 12).accessibilityLabel("책 검색")
            if model.isImporting { HStack { ProgressView().controlSize(.small); Text("PDF 목록을 읽고 있습니다.").font(.caption) }.padding(14) }
            List(model.filteredBooks) { book in
                Button { model.selectBook(book) } label: {
                    HStack(alignment: .center, spacing: 11) {
                        BookThumbnail(book: book).frame(width: 39, height: 55)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title).font(.system(size: 12, weight: .medium)).lineLimit(2).foregroundStyle(.primary)
                            Text(book.displayCategory).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                            if book.lastOpened > 0 { Text("PDF \(book.lastPage)쪽에서 이어 읽기").font(.system(size: 9)).foregroundStyle(Color.accentColor) }
                        }
                        Spacer(minLength: 0)
                        if !book.isAvailable { Image(systemName: "icloud.and.arrow.down").font(.system(size: 11)).foregroundStyle(.secondary) }
                    }.padding(.vertical, 5).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(book.title)
                    .listRowBackground(model.activeBook?.id == book.id ? Color.accentColor.opacity(0.12) : Color.clear)
            }.listStyle(.sidebar)
            Divider()
            HStack { Image(systemName: "internaldrive"); Text("이 Mac의 서재"); Spacer(); Button { model.chooseFiles(folder: true) } label: { Image(systemName: "folder.badge.plus") }.buttonStyle(.plain).accessibilityLabel("폴더 추가") }.font(.system(size: 11)).foregroundStyle(.secondary).padding(16)
        }
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
