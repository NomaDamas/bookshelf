import SwiftUI

enum LibrarySort: String, CaseIterable, Codable {
    case recentlyRead, recentlyFinished, recentlyAdded, title, notes, readCount
    var title: String {
        switch self {
        case .recentlyRead: return "최근 읽은 순"
        case .recentlyFinished: return "최근 완료한 순"
        case .recentlyAdded: return "최근 추가한 순"
        case .title: return "제목순"
        case .notes: return "메모 많은 순"
        case .readCount: return "회독 많은 순"
        }
    }
}

struct LibrarySortPreferences: Codable, Equatable {
    var criterion: LibrarySort = .recentlyRead
    var ascending = false
    var label: String {
        if criterion == .title { return ascending ? "제목순" : "제목 역순" }
        guard ascending else { return criterion.title }
        switch criterion {
        case .recentlyRead: return "오래전에 읽은 순"
        case .recentlyFinished: return "오래전에 완료한 순"
        case .recentlyAdded: return "오래전에 추가한 순"
        case .notes: return "메모 적은 순"
        case .readCount: return "회독 적은 순"
        case .title: return "제목순"
        }
    }
}

struct LibrarySortMenu: View {
    @ObservedObject var model: AppModel
    var compact = false
    var body: some View {
        Menu {
            Picker("정렬 기준", selection: Binding(get: { model.sortPreferences.criterion }, set: { model.setSort($0) })) {
                ForEach(LibrarySort.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Divider()
            Picker("정렬 방향", selection: Binding(get: { model.sortPreferences.ascending }, set: { model.setSortAscending($0) })) {
                Text("오름차순").tag(true)
                Text("내림차순").tag(false)
            }
        } label: {
            if compact { Image(systemName: "arrow.up.arrow.down").frame(width: 24, height: 24) }
            else { Label(model.sortPreferences.label, systemImage: "arrow.up.arrow.down").font(.system(size: 12)) }
        }.menuStyle(.borderlessButton).fixedSize().help("책장 정렬: " + model.sortPreferences.label)
            .accessibilityLabel(compact ? "전체 책장 정렬" : "책장 정렬").accessibilityValue(model.sortPreferences.label)
    }
}
