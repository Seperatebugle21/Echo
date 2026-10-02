import SwiftUI

@MainActor @Observable final class AppRouter {
    static let shared = AppRouter()
    enum Route { case fetch, podcast(PodcastShow) }
    var pending: Route?
    var revision = 0
    func open(_ route: Route) { pending = route; revision &+= 1 }
}

struct LibraryAddSheet: View {
    enum Action: String, CaseIterable, Identifiable {
        case playlist, smart, files, fetch
        var id: String { rawValue }
        var key: String { "library_add_" + rawValue }
        var symbol: String {
            switch self { case .playlist: "music.note.list"; case .smart: "sparkles"; case .files: "doc.badge.plus"; case .fetch: "arrow.down.circle" }
        }
    }
    let choose: (Action) -> Void
    var body: some View {
        NavigationStack {
            List(Action.allCases) { action in
                Button { choose(action) } label: {
                    Label(LocalizedStringKey(action.key), systemImage: action.symbol).padding(.vertical, 12)
                }
            }.echoBackground().navigationTitle("library_add_title").navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}
