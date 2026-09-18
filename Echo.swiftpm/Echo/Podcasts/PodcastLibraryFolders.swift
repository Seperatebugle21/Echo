import SwiftUI

struct PodcastLibraryFolders: View {
    private let store = PodcastStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("podcasts_title").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                folder("podcasts_saved_shows", kind: .shows, count: store.savedShows.count,
                       symbol: "dot.radiowaves.left.and.right", color: .purple)
                folder("podcasts_saved_episodes", kind: .episodes, count: store.savedEpisodes.count,
                       symbol: "bookmark.fill", color: .orange)
                folder("podcasts_downloads", kind: .downloads, count: store.downloadedEpisodes.count,
                       symbol: "arrow.down.circle.fill", color: .blue)
            }
        }
    }

    private func folder(_ title: LocalizedStringKey, kind: PodcastLibraryView.Kind,
                        count: Int, symbol: String, color: Color) -> some View {
        NavigationLink {
            PodcastLibraryView(kind: kind)
        } label: {
            CollectionCard(title: title, subtitle: count.formatted(), symbol: symbol) {
                ZStack {
                    LinearGradient(colors: [color.opacity(0.30), color.opacity(0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 55, weight: .medium))
                        .foregroundStyle(color.gradient)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
