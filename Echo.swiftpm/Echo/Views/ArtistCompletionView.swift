import SwiftUI

/// Let the listener choose the correct online artist before opening their catalog.
struct ArtistCompletionView: View {
    let name: String
    @State private var provider: MusicCatalogProvider = .youtubeMusic
    @State private var artists: [OnlineArtistReference] = []
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0

    var body: some View {
        List {
            Section {
                Text(name).font(.title2.bold())
                Text("artist_online_hint").foregroundStyle(.secondary)
                Picker("artist_search_provider", selection: $provider) {
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
            ForEach(artists) { artist in
                NavigationLink {
                    OnlineArtistCatalogView(artist: artist)
                } label: {
                    HStack(spacing: 12) {
                        CatalogArtwork(url: artist.artworkURL, size: 60)
                        Text(artist.name).font(.headline)
                    }
                }
            }
            if !loading && error == nil && artists.isEmpty {
                Text("artist_no_matching_catalog").foregroundStyle(.secondary)
            }
        }
        .echoBackground()
        .navigationTitle("artist_find_online")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(provider.rawValue):\(retry):\(SpotifyManager.shared.isConnected)") {
            loading = true; error = nil; artists = []
            do {
                let found: [OnlineArtistReference]
                switch provider {
                case .spotify: found = try await SpotifyAPI.shared.searchCatalog(query: name).artists
                case .youtubeMusic: found = try await YouTubeMusicMetadata.shared.searchArtists(query: name)
                }
                try Task.checkCancellation()
                artists = found
                loading = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}
