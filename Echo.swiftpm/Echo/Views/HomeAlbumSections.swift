import SwiftUI

struct HomeLocalAlbumSection: View {
    let coverWidth: CGFloat
    var zoom: Namespace.ID? = nil
    @Environment(MusicLibraryManager.self) private var library
    @State private var selection: [String] = []
    /// Grouped off the main thread once per library change, not in every body pass.
    @State private var albums: [AlbumGroup] = []
    private let session = HomeSessionManager.shared
    private var shown: [AlbumGroup] {
        let byID = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return selection.compactMap { byID[$0] }
    }
    var body: some View {
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                HomeSectionLink(title: "home_local_albums") { AlbumsView() }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(shown) { album in
                            NavigationLink {
                                AlbumDetailView(album: album).toolbarVisibility(.visible, for: .navigationBar)
                                    .echoZoomDestination("home-album-" + album.id, in: zoom)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    if let song = album.songs.first {
                                        SongArtworkView(song: song, cornerRadius: 14).frame(width: coverWidth, height: coverWidth)
                                            .echoZoomSource("home-album-" + album.id, in: zoom)
                                            .homeCoverShadow()
                                    }
                                    Text(album.name).font(.headline).lineLimit(2)
                                    Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(width: coverWidth, alignment: .leading)
                            }.buttonStyle(HomePressStyle())
                                .albumFavoriteActions(FavoriteAlbum(album: album))
                                .echoRailItem()
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 8)
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
            }
            .task(id: library.songRevision) { await refresh() }
        } else {
            Color.clear.frame(height: 0)
                .task(id: library.songRevision) { await refresh() }
        }
    }
}

private extension HomeLocalAlbumSection {
    func refresh() async {
        let songs = library.songs
        let grouped = await Task.detached(priority: .userInitiated) { LibraryAlbums.groups(from: songs) }.value
        guard !Task.isCancelled else { return }
        albums = grouped
        selection = session.albumSelection(from: grouped.map(\.id))
    }
}

struct HomeOnlineAlbumSection: View {
    let coverWidth: CGFloat
    private let store = OnlineMusicCatalogStore.shared
    var body: some View {
        Group {
            if !store.homeAlbums.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    Text("home_online_albums").font(.title2.bold()).padding(.horizontal, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(store.homeAlbums) { album in
                                NavigationLink { OnlineAlbumDetailView(album: album).toolbarVisibility(.visible, for: .navigationBar) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        CatalogArtwork(url: album.artworkURL, size: coverWidth).homeCoverShadow()
                                        Text(album.title).font(.headline).lineLimit(2)
                                        Text(album.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }.frame(width: coverWidth, alignment: .leading)
                                }.buttonStyle(HomePressStyle())
                                    .albumFavoriteActions(FavoriteAlbum(album: album))
                                    .echoRailItem()
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.vertical, 8)
                    }
                    .contentMargins(.horizontal, 20, for: .scrollContent)
                    .scrollClipDisabled()
                    .scrollTargetBehavior(.viewAligned)
                }
            }
        }
    }
}
