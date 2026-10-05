import SwiftUI

struct FetchURLPreviewView: View {
    let content: FetchURLResolvedContent
    @Environment(\.dismiss) private var dismiss
    private var needsDoneButton: Bool {
        switch content { case .spotifyTrack, .spotifyPlaylist: false; default: true }
    }
    var body: some View {
        Group {
        switch content {
        case .artist(let artist): OnlineArtistCatalogView(artist: artist)
        case .album(let album): OnlineAlbumDetailView(album: album)
        case .youtubeTrack(let track):
            OnlineTrackCollectionView(title: track.title, artworkURL: track.artworkURL,
                tracks: [track.catalogTrack], skippedCount: 0, importable: false)
        case .youtubePlaylist(let playlist):
            OnlineTrackCollectionView(title: playlist.title, artworkURL: playlist.artworkURL,
                tracks: playlist.tracks.map(\.catalogTrack), skippedCount: playlist.skippedCount, importable: true)
        default: LegacyFetchURLPreviewView(content: content)
        }
        }
        .toolbar {
            if needsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("catalog_done") { dismiss() }
                }
            }
        }
    }
}

struct CatalogArtwork: View {
    let url: URL?
    var size: CGFloat = 128
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
            RoundedRectangle(cornerRadius: 14).fill(.secondary.opacity(0.15))
                .overlay { Image(systemName: "opticaldisc").font(.largeTitle).foregroundStyle(.secondary) }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityHidden(true)
    }
}

struct CatalogTrackRow: View {
    let track: OnlineMusicTrack
    let action: () -> Void
    private let downloads = CatalogDownloads.shared
    var body: some View {
        let status = downloads.statusKey(track)
        Button(action: action) {
            HStack(spacing: 12) {
                CatalogArtwork(url: track.artworkURL, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text(track.artistName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    if let album = track.album, !album.isEmpty { Text(album).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    if let status { Text(LocalizedStringKey(status)).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                Image(systemName: status == "catalog_downloaded" ? "checkmark.circle" : status == "catalog_queued" ? "clock" : "arrow.down.circle")
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(status == "catalog_downloaded" || status == "catalog_queued" || downloads.busy)
        .accessibilityLabel(Text("catalog_download_track \(track.title)"))
    }
}

struct OnlineArtistCatalogView: View {
    @State private var model: OnlineArtistCatalogModel
    @State private var query = ""
    @State private var albumsSelected = false
    @State private var showConfirmation = false
    @State private var result: String?
    @State private var downloading = false
    private let downloads = CatalogDownloads.shared
    init(artist: OnlineArtistReference) { _model = State(initialValue: OnlineArtistCatalogModel(artist: artist)) }
    private var filteredTracks: [OnlineMusicTrack] { model.tracks.filter { OnlineCatalogLogic.matches($0, query: query) } }
    private var filteredAlbums: [OnlineMusicAlbum] {
        model.albums.filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.artistName.localizedStandardContains(query) }
    }
    var body: some View {
        List {
            Section {
                HStack {
                    CatalogArtwork(url: model.artist.artworkURL, size: 88)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.artist.name.isEmpty ? model.artist.provider.name : model.artist.name).font(.title2.bold())
                        Text(model.artist.provider.name).foregroundStyle(.secondary)
                        Text("catalog_tracks_count \(model.tracks.count)").font(.caption)
                    }
                }
                if model.loading {
                    ProgressView()
                    Text("catalog_loading_albums \(model.loadedAlbums) \(model.albums.count)").font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.error {
                    Text(error).foregroundStyle(.secondary)
                    if model.artist.provider == .spotify, !SpotifyManager.shared.isConnected {
                        Button("catalog_connect_spotify") { SpotifyManager.shared.connect() }
                    } else { Button("catalog_retry") { Task { await model.retry() } } }
                }
                if model.skippedCount > 0 { Text("catalog_skipped_tracks \(model.skippedCount)").font(.caption).foregroundStyle(.secondary) }
                Button("catalog_download_artist") { showConfirmation = true }
                    .disabled(!model.complete || downloads.pending(model.tracks).isEmpty || downloading || downloads.busy)
                Picker("catalog_content", selection: $albumsSelected) {
                    Text("catalog_songs").tag(false)
                    Text("catalog_albums").tag(true)
                }.pickerStyle(.segmented)
            }
            if albumsSelected {
                ForEach(filteredAlbums) { album in
                    NavigationLink { OnlineAlbumDetailView(album: album) } label: {
                        CatalogAlbumRow(album: album)
                    }
                }
            } else {
                ForEach(filteredTracks) { track in
                    CatalogTrackRow(track: track) { Task { await download([track]) } }
                }
            }
            if model.complete && (albumsSelected ? filteredAlbums.isEmpty : filteredTracks.isEmpty) {
                Text(LocalizedStringKey(query.isEmpty ? "catalog_empty" : "catalog_no_search_results")).foregroundStyle(.secondary)
            }
        }
        .echoBackground()
        .navigationTitle("catalog_artist")
        .searchable(text: $query, prompt: "catalog_search")
        .task(id: SpotifyManager.shared.isConnected) { await model.load() }
        .confirmationDialog("catalog_confirm_download", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("catalog_download_new \(downloads.pending(model.tracks).count)") { Task { await download(model.tracks) } }
        } message: { Text("catalog_bulk_detail") }
        .alert("catalog_download_result_title", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("catalog_done", role: .cancel) { result = nil }
        } message: { Text(result ?? "") }
    }
    private func download(_ tracks: [OnlineMusicTrack]) async {
        guard !downloading else { return }
        downloading = true
        result = await downloads.enqueue(tracks).message
        downloading = false
    }
}

struct CatalogAlbumRow: View {
    let album: OnlineMusicAlbum
    var body: some View {
        HStack(spacing: 12) {
            CatalogArtwork(url: album.artworkURL, size: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(album.title).font(.headline)
                Text(album.artistName).font(.subheadline).foregroundStyle(.secondary)
                if let year = album.year { Text(year).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct OnlineAlbumDetailView: View {
    let album: OnlineMusicAlbum
    @State private var collection: OnlineTrackCollection?
    @State private var error: String?
    @State private var retry = 0
    var body: some View {
        Group {
            if let collection {
                OnlineTrackCollectionView(title: album.title, artworkURL: collection.artworkURL,
                    tracks: collection.tracks, skippedCount: collection.skippedCount, importable: false, isAlbum: true)
            } else if let error {
                VStack(spacing: 16) {
                    Text(error)
                    if album.provider == .spotify, !SpotifyManager.shared.isConnected {
                        Button("catalog_connect_spotify") { SpotifyManager.shared.connect() }
                    } else { Button("catalog_retry") { retry += 1 } }
                }.padding()
            } else { ProgressView("catalog_loading") }
        }
        .echoBackground()
        .navigationTitle(album.title)
        .task(id: "\(retry):\(SpotifyManager.shared.isConnected)") {
            guard collection == nil else { return }
            error = nil
            do { collection = try await OnlineMusicCatalogStore.shared.tracks(for: album) }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct OnlineTrackCollectionView: View {
    let title: String
    let artworkURL: URL?
    let tracks: [OnlineMusicTrack]
    let skippedCount: Int
    let importable: Bool
    var isAlbum = false
    @State private var query = ""
    @State private var confirmDownload = false
    @State private var confirmImport = false
    @State private var busy = false
    @State private var result: String?
    private let downloads = CatalogDownloads.shared
    private var filtered: [OnlineMusicTrack] { tracks.filter { OnlineCatalogLogic.matches($0, query: query) } }
    var body: some View {
        List {
            Section {
                HStack { Spacer(); CatalogArtwork(url: artworkURL, size: 180); Spacer() }
                Text(title).font(.title2.bold())
                Text("catalog_tracks_count \(tracks.count)").foregroundStyle(.secondary)
                if skippedCount > 0 { Text("catalog_skipped_tracks \(skippedCount)").font(.caption).foregroundStyle(.secondary) }
                Button {
                    if tracks.count == 1 { Task { await download(tracks) } }
                    else { confirmDownload = true }
                } label: {
                    Text(LocalizedStringKey(isAlbum ? "catalog_download_album" : "catalog_download_all"))
                }.disabled(downloads.pending(tracks).isEmpty || busy || downloads.busy)
                if importable {
                    Button("fetchurlviews_transfer_to_echo") { confirmImport = true }.disabled(tracks.isEmpty || busy || downloads.busy)
                }
            }
            ForEach(OnlineCatalogLogic.uniqueTracks(filtered)) { track in
                CatalogTrackRow(track: track) { Task { await download([track]) } }
            }
            if filtered.isEmpty { Text(LocalizedStringKey(query.isEmpty ? "catalog_empty" : "catalog_no_search_results")).foregroundStyle(.secondary) }
        }
        .echoBackground()
        .navigationTitle(LocalizedStringKey(isAlbum ? "catalog_album" : importable ? "catalog_playlist" : "catalog_songs"))
        .searchable(text: $query, prompt: "catalog_search")
        .confirmationDialog("catalog_confirm_download", isPresented: $confirmDownload, titleVisibility: .visible) {
            Button("catalog_download_new \(downloads.pending(tracks).count)") { Task { await download(tracks) } }
        } message: { Text("catalog_bulk_detail") }
        .confirmationDialog("fetchurlviews_transfer_confirmation", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("fetchurlviews_transfer_to_echo") { Task { await transfer() } }
        } message: { Text("fetchurlviews_transfer_message") }
        .alert("catalog_download_result_title", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("catalog_done", role: .cancel) { result = nil }
        } message: { Text(result ?? "") }
    }
    private func download(_ tracks: [OnlineMusicTrack]) async {
        guard !busy else { return }
        busy = true
        result = await downloads.enqueue(tracks).message
        busy = false
    }
    private func transfer() async {
        guard !busy else { return }
        busy = true
        result = await downloads.importPlaylist(title: title, artworkURL: artworkURL, tracks: tracks).message
        busy = false
    }
}
