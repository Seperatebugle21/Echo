import SwiftUI

struct HomeLocalAlbumSection: View {
    @Environment(MusicLibraryManager.self) private var library
    @State private var selection: [String] = []
    private let session = HomeSessionManager.shared
    private var albums: [AlbumGroup] { LibraryAlbums.groups(from: library.songs) }
    private var shown: [AlbumGroup] {
        let byID = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return selection.compactMap { byID[$0] }
    }
    var body: some View {
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                Text("home_local_albums").font(.title2.bold()).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(shown) { album in
                            NavigationLink { AlbumDetailView(album: album) } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    if let song = album.songs.first {
                                        SongArtworkView(song: song, cornerRadius: 14).frame(width: 144, height: 144)
                                    }
                                    Text(album.name).font(.headline).lineLimit(2)
                                    Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(width: 144, alignment: .leading)
                            }.buttonStyle(.plain)
                                .albumFavoriteActions(FavoriteAlbum(album: album))
                        }
                    }.padding(.horizontal).padding(.vertical, 6)
                }
            }
            .task(id: albums.map(\.id)) { selection = session.albumSelection(from: albums.map(\.id)) }
        } else {
            Color.clear.frame(height: 0)
                .task(id: albums.map(\.id)) { selection = session.albumSelection(from: albums.map(\.id)) }
        }
    }
}

struct HomeOnlineAlbumSection: View {
    private let store = OnlineMusicCatalogStore.shared
    var body: some View {
        Group {
            if !store.homeAlbums.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    Text("home_online_albums").font(.title2.bold()).padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(store.homeAlbums) { album in
                                NavigationLink { OnlineAlbumDetailView(album: album) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        CatalogArtwork(url: album.artworkURL, size: 144)
                                        Text(album.title).font(.headline).lineLimit(2)
                                        Text(album.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }.frame(width: 144, alignment: .leading)
                                }.buttonStyle(.plain)
                                    .albumFavoriteActions(FavoriteAlbum(album: album))
                            }
                        }.padding(.horizontal).padding(.vertical, 6)
                    }
                }
            }
        }
    }
}
