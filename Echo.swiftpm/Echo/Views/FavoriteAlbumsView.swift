import SwiftUI

struct AlbumFavoriteButton: View {
    let album: FavoriteAlbum
    private let favorites = FavoriteAlbumsStore.shared
    var body: some View {
        Button {
            favorites.toggle(album)
        } label: {
            Label(LocalizedStringKey(favorites.contains(album) ? "album_remove_favorite" : "album_add_favorite"),
                systemImage: favorites.contains(album) ? "heart.slash" : "heart")
        }
    }
}

private struct AlbumFavoriteActions: ViewModifier {
    let album: FavoriteAlbum
    let swipe: Bool
    func body(content: Content) -> some View {
        if swipe {
            content
                .contextMenu { AlbumFavoriteButton(album: album) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    AlbumFavoriteButton(album: album).tint(.pink)
                }
        } else {
            content.contextMenu { AlbumFavoriteButton(album: album) }
        }
    }
}

extension View {
    func albumFavoriteActions(_ album: FavoriteAlbum, swipe: Bool = false) -> some View {
        modifier(AlbumFavoriteActions(album: album, swipe: swipe))
    }
}

struct FavoriteAlbumsView: View {
    @Environment(MusicLibraryManager.self) private var library
    @State private var query = ""
    private let favorites = FavoriteAlbumsStore.shared
    private var albums: [FavoriteAlbum] {
        favorites.albums.filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query) }
    }
    var body: some View {
        List(albums) { album in
            NavigationLink {
                if let online = album.onlineAlbum { OnlineAlbumDetailView(album: online) }
                else if let local = album.localAlbum(in: library.songs) { AlbumDetailView(album: local) }
                else { AlbumCompletionView(title: album.title, artist: album.artist) }
            } label: {
                HStack(spacing: 12) {
                    FavoriteAlbumArtwork(album: album, size: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(album.title).font(.headline)
                        Text(album.artist).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .albumFavoriteActions(album, swipe: true)
        }
        .echoBackground()
        .navigationTitle("library_favorite_albums")
        .searchable(text: $query, prompt: "libraryview_search_albums")
        .overlay {
            if albums.isEmpty {
                ContentUnavailableView(query.isEmpty ? "favorite_albums_empty" : "catalog_no_search_results",
                    systemImage: "heart", description: Text("favorite_albums_hint"))
            }
        }
    }
}

struct FavoriteAlbumArtwork: View {
    @Environment(MusicLibraryManager.self) private var library
    let album: FavoriteAlbum
    let size: CGFloat
    var body: some View {
        Group {
            if let song = album.localAlbum(in: library.songs)?.songs.first {
                SongArtworkView(song: song, cornerRadius: 14)
            } else { CatalogArtwork(url: album.onlineAlbum?.artworkURL, size: size) }
        }.frame(width: size, height: size)
    }
}

struct FavoriteAlbumsFeatureArtwork: View {
    let albums: [FavoriteAlbum]
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(.thinMaterial)
                HStack(spacing: -22) {
                    ForEach(Array(albums.prefix(3))) { album in
                        FavoriteAlbumArtwork(album: album, size: geometry.size.width * 0.44)
                            .clipShape(.rect(cornerRadius: 13)).shadow(radius: 5, y: 3)
                    }
                }.opacity(0.72).offset(y: 14)
                Circle().fill(.regularMaterial).frame(width: 72, height: 72).shadow(radius: 10, y: 4)
                Image(systemName: "opticaldisc.fill").font(.system(size: 34, weight: .semibold)).foregroundStyle(.pink)
                    .overlay(alignment: .bottomTrailing) { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.red) }
            }
        }
    }
}
