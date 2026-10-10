import SwiftUI

struct FetchCatalogSearchView: View {
    let provider: MusicCatalogProvider
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var results = MusicCatalogSearchResults()
    @State private var loading = false
    @State private var error: String?
    @State private var searched = false
    @State private var retry = 0

    var body: some View {
        List {
            if loading { ProgressView("catalog_loading") }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    if provider == .spotify && !SpotifyManager.shared.isConnected {
                        Button("catalog_connect_spotify") { SpotifyManager.shared.connect() }
                    } else { Button("catalog_retry") { retry += 1 } }
                }
            }
            if provider == .spotify && !results.artists.isEmpty {
                Section("catalog_artists") {
                    ForEach(results.artists) { artist in
                        NavigationLink { OnlineArtistCatalogView(artist: artist) } label: {
                            HStack(spacing: 12) {
                                CatalogArtwork(url: artist.artworkURL, size: 56)
                                Text(artist.name).font(.headline)
                            }
                        }
                    }
                }
            }
            if !results.albums.isEmpty {
                Section("catalog_albums") {
                    ForEach(results.albums) { album in
                        NavigationLink { OnlineAlbumDetailView(album: album) } label: { CatalogAlbumRow(album: album) }
                            .albumFavoriteActions(FavoriteAlbum(album: album), swipe: true)
                    }
                }
            }
            if !results.tracks.isEmpty {
                Section("catalog_songs") {
                    ForEach(results.tracks) { track in
                        NavigationLink {
                            OnlineSongDetailView(track: track)
                        } label: {
                            HStack(spacing: 12) {
                                CatalogArtwork(url: track.artworkURL, size: 48)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title).font(.headline)
                                    Text(track.artistName).foregroundStyle(.secondary)
                                    if let album = track.album { Text(album).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            }
            if results.isEmpty && !loading && error == nil {
                ContentUnavailableView(LocalizedStringKey(searched ? "catalog_no_search_results" : "catalog_search_discover"),
                    systemImage: "magnifyingglass", description: Text(LocalizedStringKey(provider == .spotify
                        ? "catalog_search_hint" : "catalog_search_songs_albums_hint")))
            }
        }
        .echoBackground()
        .navigationTitle(provider.name)
        .searchable(text: $query, prompt: Text(LocalizedStringKey(provider == .spotify
            ? "catalog_search_all" : "catalog_search_songs_albums")))
        .onSubmit(of: .search) { submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines); retry += 1 }
        .onChange(of: query) {
            if query.isEmpty { submittedQuery = ""; results = MusicCatalogSearchResults(); searched = false }
        }
        .task(id: "\(submittedQuery):\(retry):\(SpotifyManager.shared.isConnected)") { await search() }
    }

    private func search() async {
        guard !submittedQuery.isEmpty else { loading = false; error = nil; return }
        loading = true
        error = nil
        results = MusicCatalogSearchResults()
        do {
            let found: MusicCatalogSearchResults
            switch provider {
            case .spotify: found = try await SpotifyAPI.shared.searchCatalog(query: submittedQuery)
            case .youtubeMusic: found = try await YouTubeMusicMetadata.shared.searchCatalog(query: submittedQuery)
            }
            try Task.checkCancellation()
            results = MusicCatalogSearchResults(tracks: found.tracks,
                artists: provider == .spotify ? found.artists : [], albums: found.albums)
            searched = true
            loading = false
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
    }
}
