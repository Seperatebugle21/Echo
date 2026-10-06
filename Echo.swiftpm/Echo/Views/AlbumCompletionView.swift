import SwiftUI

/// Let the listener choose the matching release before queuing any missing songs.
struct AlbumCompletionView: View {
    let title: String
    let artist: String
    @State private var provider: MusicCatalogProvider = .youtubeMusic
    @State private var albums: [OnlineMusicAlbum] = []
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    var body: some View {
        List {
            Section {
                Text("album_complete_hint").foregroundStyle(.secondary)
                Picker("album_search_provider", selection: $provider) {
                    Text("catalog_provider_youtube_music").tag(MusicCatalogProvider.youtubeMusic)
                    Text("catalog_provider_spotify").tag(MusicCatalogProvider.spotify)
                }.pickerStyle(.segmented)
            }
            if loading { ProgressView("catalog_loading") }
            if let error {
                Text(error).foregroundStyle(.secondary)
                if provider == .spotify && !SpotifyManager.shared.isConnected {
                    Button("catalog_connect_spotify") { SpotifyManager.shared.connect() }
                } else { Button("catalog_retry") { retry += 1 } }
            }
            ForEach(albums) { album in
                NavigationLink { OnlineAlbumDetailView(album: album) } label: { CatalogAlbumRow(album: album) }
                    .albumFavoriteActions(FavoriteAlbum(album: album), swipe: true)
            }
            if !loading && error == nil && albums.isEmpty { Text("album_no_matching_release").foregroundStyle(.secondary) }
        }
        .echoBackground()
        .navigationTitle("album_find_missing")
        .task(id: "\(provider.rawValue):\(retry):\(SpotifyManager.shared.isConnected)") {
            loading = true; error = nil; albums = []
            do {
                let query = title + " " + artist
                let results: MusicCatalogSearchResults
                switch provider {
                case .spotify: results = try await SpotifyAPI.shared.searchCatalog(query: query)
                case .youtubeMusic: results = try await YouTubeMusicMetadata.shared.searchCatalog(query: query)
                }
                try Task.checkCancellation()
                albums = results.albums
                loading = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}
