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
                NavigationLink {
                    OnlineAlbumDetailView(album: album, showsFavoriteAction: false)
                } label: { CatalogAlbumRow(album: album) }
            }
            if !loading && error == nil && albums.isEmpty { Text("album_no_matching_release").foregroundStyle(.secondary) }
        }
        .echoBackground()
        .navigationTitle("album_find_missing")
        .task(id: "\(provider.rawValue):\(retry):\(SpotifyManager.shared.isConnected)") {
            loading = true; error = nil; albums = []
            do {
                let query = title + " " + artist
                let found: [OnlineMusicAlbum]
                switch provider {
                case .spotify: found = try await SpotifyAPI.shared.searchCatalog(query: query).albums
                case .youtubeMusic: found = try await YouTubeMusicMetadata.shared.searchAlbums(query: query)
                }
                try Task.checkCancellation()
                albums = found
                loading = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}
