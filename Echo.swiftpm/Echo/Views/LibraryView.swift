import SwiftUI


// MARK: - Artist Model

struct ArtistGroup: Identifiable {

    var id: String {
        name
    }

    let name: String
    let songs: [Song]
}


// MARK: - Album Model

struct AlbumGroup: Identifiable {

    var id: String {
        "\(artist)-\(name)"
    }

    let name: String
    let artist: String
    let songs: [Song]
}



// MARK: - Library

struct LibraryView: View {

    @Environment(MusicLibraryManager.self)
    private var library


    @State private var showSongs = false
    @State private var showPlaylists = false


    private var artists: [ArtistGroup] {

        let grouped =
            Dictionary(
                grouping: library.songs
            ) { song in

                let artist =
                    song.artist
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                return artist.isEmpty
                ? "Onbekende artiest"
                : artist
            }


        return grouped
            .map {

                ArtistGroup(
                    name: $0.key,
                    songs: $0.value
                )
            }
            .sorted {

                $0.name.localizedCaseInsensitiveCompare(
                    $1.name
                ) == .orderedAscending
            }
    }


   private var albumCount: Int {

    let albumKeys: [String] =
        library.songs.compactMap { song in

            guard
                let album = song.album?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                !album.isEmpty
            else {
                return nil
            }

            return "\(song.artist)|\(album)"
        }

    return Set<String>(albumKeys).count
}


    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(
                    alignment: .leading,
                    spacing: 26
                ) {

                    // MARK: Main

                    LazyVGrid(
                        columns: [
                            GridItem(
                                .flexible(),
                                spacing: 12
                            ),

                            GridItem(
                                .flexible(),
                                spacing: 12
                            )
                        ],
                        spacing: 12
                    ) {


                        LibraryMainButton(
                            title: "Nummers",
                            subtitle:
                                "\(library.songs.count) nummers",
                            icon: "music.note"
                        ) {

                            showSongs = true
                        }


                        LibraryMainButton(
                            title: "Playlists",
                            subtitle:
                                "\(library.playlists.count) playlists",
                            icon: "music.note.list"
                        ) {

                            showPlaylists = true
                        }
                    }
                    .padding(.horizontal)



                    // MARK: Library Categories

                    VStack(
                        spacing: 0
                    ) {

                        NavigationLink {

                            FavoritesView()

                        } label: {

                            LibraryNavigationRow(
                                title: "Favorieten",
                                subtitle:
                                    "\(library.favoriteSongs.count) nummers",
                                icon: "heart.fill"
                            )
                        }


                        Divider()
                            .padding(.leading, 58)


                        NavigationLink {

                            ArtistsView()

                        } label: {

                            LibraryNavigationRow(
                                title: "Artiesten",
                                subtitle:
                                    "\(artists.count) artiesten",
                                icon: "person.2.fill"
                            )
                        }


                        Divider()
                            .padding(.leading, 58)


                        NavigationLink {

                            AlbumsView()

                        } label: {

                            LibraryNavigationRow(
                                title: "Albums",
                                subtitle:
                                    "\(albumCount) albums",
                                icon: "square.stack.fill"
                            )
                        }


                        Divider()
                            .padding(.leading, 58)


                        NavigationLink {

                            RecentAddedView()

                        } label: {

                            LibraryNavigationRow(
                                title: "Recent toegevoegd",
                                subtitle: nil,
                                icon: "clock.badge.plus"
                            )
                        }


                        Divider()
                            .padding(.leading, 58)


                        NavigationLink {

                            RecentPlayedView()

                        } label: {

                            LibraryNavigationRow(
                                title: "Recent afgespeeld",
                                subtitle: nil,
                                icon: "clock.arrow.circlepath"
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
                .padding(.bottom, 120)
            }

            .navigationTitle(
                "Bibliotheek"
            )

            .fullScreenCover(
                isPresented: $showSongs
            ) {

                LibrarySheetContainer {

                    SongsView()
                }
            }

            .fullScreenCover(
                isPresented: $showPlaylists
            ) {

                LibrarySheetContainer {

                    PlaylistsView()
                }
            }
        }
    }
}



// MARK: - Sheet Container

struct LibrarySheetContainer<Content: View>: View {

    @Environment(\.dismiss)
    private var dismiss

    let content: () -> Content


    var body: some View {

        ZStack(
            alignment: .topTrailing
        ) {

            content()


            Button {

                dismiss()

            } label: {

                Image(
                    systemName: "xmark.circle.fill"
                )
                .font(.title2)
                .symbolRenderingMode(
                    .hierarchical
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 16)
            .zIndex(100)
        }
    }
}



// MARK: - Main Library Button

struct LibraryMainButton: View {

    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void


    var body: some View {

        Button(
            action: action
        ) {

            VStack(
                alignment: .leading,
                spacing: 14
            ) {

                Image(
                    systemName: icon
                )
                .font(.title2)
                .foregroundStyle(.primary)


                Spacer()


                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)


                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 125,
                alignment: .leading
            )
            .padding(16)

            .background(
                .thinMaterial,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }
}



// MARK: - Navigation Row

struct LibraryNavigationRow: View {

    let title: String
    let subtitle: String?
    let icon: String


    var body: some View {

        HStack(
            spacing: 14
        ) {

            Image(
                systemName: icon
            )
            .font(.title3)
            .frame(
                width: 30
            )


            VStack(
                alignment: .leading,
                spacing: 2
            ) {

                Text(title)
                    .foregroundStyle(.primary)
                    .font(.body)


                if let subtitle {

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }


            Spacer()


            Image(
                systemName: "chevron.right"
            )
            .font(.caption.bold())
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}



// MARK: - Artists

struct ArtistsView: View {

    @Environment(MusicLibraryManager.self)
    private var library


    private var artists: [ArtistGroup] {

        Dictionary(
            grouping: library.songs
        ) {

            let value =
                $0.artist
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

            return value.isEmpty
            ? "Onbekende artiest"
            : value
        }

        .map {

            ArtistGroup(
                name: $0.key,
                songs: $0.value
            )
        }

        .sorted {

            $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
        }
    }


    var body: some View {

        List(artists) { artist in

            NavigationLink {

                ArtistDetailView(
                    artist: artist
                )

            } label: {

                HStack(
                    spacing: 12
                ) {

                    ArtistArtworkView(
                        songs: artist.songs
                    )
                    .frame(
                        width: 55,
                        height: 55
                    )
                    .clipShape(Circle())


                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {

                        Text(artist.name)
                            .font(.headline)


                        Text(
                            "\(artist.songs.count) nummers"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(
            "Artiesten"
        )
    }
}



// MARK: - Artist Detail

struct ArtistDetailView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(AudioPlayerManager.self)
    private var audioPlayer


    let artist: ArtistGroup


    var body: some View {

        List {

            Section {

                HStack {

                    Spacer()


                    VStack(
                        spacing: 12
                    ) {

                        ArtistArtworkView(
                            songs: artist.songs
                        )
                        .frame(
                            width: 160,
                            height: 160
                        )
                        .clipShape(Circle())


                        Text(artist.name)
                            .font(.title2.bold())


                        Text(
                            "\(artist.songs.count) nummers"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }


                    Spacer()
                }
                .listRowBackground(
                    Color.clear
                )
            }


            Section(
                "Nummers"
            ) {

                ForEach(
                    artist.songs.sorted {
                        $0.title.localizedCaseInsensitiveCompare(
                            $1.title
                        ) == .orderedAscending
                    }
                ) { song in

                    Button {

                        play(
                            song,
                            queue: artist.songs
                        )

                    } label: {

                        LibrarySongRow(
                            song: song
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(
            artist.name
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
    }


    private func play(
        _ song: Song,
        queue: [Song]
    ) {

        guard let url =
                library.getURL(
                    for: song
                )
        else {
            return
        }


        library.markAsPlayed(song)

        audioPlayer.lastPlaybackDirection =
            .fade

        audioPlayer.play(
            song: song,
            url: url,
            queue: queue
        )

        audioPlayer.allSongs =
            library.songs

        audioPlayer.fillAutoNext(
            from: library.songs
        )
    }
}



// MARK: - Albums

struct AlbumsView: View {

    @Environment(MusicLibraryManager.self)
    private var library


    private var albums: [AlbumGroup] {

        let songs =
            library.songs.filter {

                guard
                    let album = $0.album?
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                else {
                    return false
                }

                return !album.isEmpty
            }


        let grouped =
            Dictionary(
                grouping: songs
            ) {

                "\($0.artist)|\($0.album ?? "")"
            }


        return grouped
            .compactMap { _, songs in

                guard
                    let first = songs.first,
                    let album = first.album
                else {
                    return nil
                }


                return AlbumGroup(
                    name: album,
                    artist: first.artist,
                    songs: songs
                )
            }

            .sorted {

                $0.name.localizedCaseInsensitiveCompare(
                    $1.name
                ) == .orderedAscending
            }
    }


    var body: some View {

        List(albums) { album in

            NavigationLink {

                AlbumDetailView(
                    album: album
                )

            } label: {

                HStack(
                    spacing: 12
                ) {

                    if let first =
                        album.songs.first {

                        SongArtworkView(
                            song: first,
                            cornerRadius: 12
                        )
                        .frame(
                            width: 58,
                            height: 58
                        )
                    }


                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {

                        Text(album.name)
                            .font(.headline)


                        Text(album.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(
            "Albums"
        )
    }
}



// MARK: - Album Detail

struct AlbumDetailView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(AudioPlayerManager.self)
    private var audioPlayer


    let album: AlbumGroup


    var body: some View {

        List {

            Section {

                HStack {

                    Spacer()


                    VStack(
                        spacing: 12
                    ) {

                        if let first =
                            album.songs.first {

                            SongArtworkView(
                                song: first,
                                cornerRadius: 20
                            )
                            .frame(
                                width: 180,
                                height: 180
                            )
                        }


                        Text(album.name)
                            .font(.title2.bold())


                        Text(album.artist)
                            .foregroundStyle(.secondary)
                    }


                    Spacer()
                }
                .listRowBackground(
                    Color.clear
                )
            }


            Section(
                "Nummers"
            ) {

                ForEach(
                    album.songs
                ) { song in

                    Button {

                        play(song)

                    } label: {

                        LibrarySongRow(
                            song: song
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(
            album.name
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
    }


    private func play(
        _ song: Song
    ) {

        guard let url =
                library.getURL(
                    for: song
                )
        else {
            return
        }


        library.markAsPlayed(song)

        audioPlayer.lastPlaybackDirection =
            .fade

        audioPlayer.play(
            song: song,
            url: url,
            queue: album.songs
        )

        audioPlayer.allSongs =
            library.songs

        audioPlayer.fillAutoNext(
            from: library.songs
        )
    }
}



// MARK: - Recently Added

struct RecentAddedView: View {

    @Environment(MusicLibraryManager.self)
    private var library


    var body: some View {

        SongCollectionView(
            title: "Recent toegevoegd",
            songs:
                library.songs.sorted {
                    $0.dateAdded > $1.dateAdded
                }
        )
    }
}



// MARK: - Recently Played

struct RecentPlayedView: View {

    @Environment(MusicLibraryManager.self)
    private var library


    var body: some View {

        SongCollectionView(
            title: "Recent afgespeeld",
            songs:
                library.songs
                    .filter {
                        $0.lastPlayed != nil
                    }
                    .sorted {
                        ($0.lastPlayed ?? .distantPast) >
                        ($1.lastPlayed ?? .distantPast)
                    }
        )
    }
}



// MARK: - Generic Song Collection

struct SongCollectionView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(AudioPlayerManager.self)
    private var audioPlayer


    let title: String
    let songs: [Song]


    var body: some View {

        List(songs) { song in

            Button {

                play(song)

            } label: {

                LibrarySongRow(
                    song: song
                )
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(title)
    }


    private func play(
        _ song: Song
    ) {

        guard let url =
                library.getURL(
                    for: song
                )
        else {
            return
        }


        library.markAsPlayed(song)

        audioPlayer.lastPlaybackDirection =
            .fade

        audioPlayer.play(
            song: song,
            url: url,
            queue: songs
        )

        audioPlayer.allSongs =
            library.songs

        audioPlayer.fillAutoNext(
            from: library.songs
        )
    }
}



// MARK: - Reusable Song Row

struct LibrarySongRow: View {

    let song: Song


    var body: some View {

        HStack(
            spacing: 12
        ) {

            SongArtworkView(
                song: song,
                cornerRadius: 10
            )
            .frame(
                width: 50,
                height: 50
            )


            VStack(
                alignment: .leading,
                spacing: 2
            ) {

                Text(song.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)


                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }


            Spacer()
        }
    }
}



// MARK: - Song Artwork

struct SongArtworkView: View {

    let song: Song
    let cornerRadius: CGFloat


    var body: some View {

        Group {

            if
                let data = song.coverData,
                let image =
                    UIImage(data: data)
            {

                Image(
                    uiImage: image
                )
                .resizable()
                .scaledToFill()

            } else {

                Image(
                    systemName: "music.note"
                )
                .font(.title2)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .background(
                    .thinMaterial
                )
            }
        }

        .clipShape(
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
    }
}



// MARK: - Artist Artwork

struct ArtistArtworkView: View {

    let songs: [Song]


    var body: some View {

        Group {

            if
                let song =
                    songs.first(
                        where: {
                            $0.coverData != nil
                        }
                    ),
                let data =
                    song.coverData,
                let image =
                    UIImage(data: data)
            {

                Image(
                    uiImage: image
                )
                .resizable()
                .scaledToFill()

            } else {

                Image(
                    systemName:
                        "person.crop.circle.fill"
                )
                .font(
                    .system(size: 50)
                )
                .foregroundStyle(
                    .secondary
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .background(
                    .thinMaterial
                )
            }
        }
    }
}
