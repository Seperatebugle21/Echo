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


   


    private var artists: [ArtistGroup] {

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


    private var albumGroups: [AlbumGroup] {

        let songs =
            library.songs.filter {

                guard
                    let album =
                        $0.album?
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


    // MARK: - Body

    var body: some View {

        NavigationStack {

            ScrollView {

                LazyVStack(
                    alignment: .leading,
                    spacing: 34
                ) {


                    // MARK: Your Library

                    VStack(
                        alignment: .leading,
                        spacing: 14
                    ) {

                        Text("Jouw bibliotheek")
                            .font(.title2.bold())
                            .padding(.horizontal)


                        ScrollView(
                            .horizontal,
                            showsIndicators: false
                        ) {

                            LazyHStack(
                                spacing: 16
                            ) {


                                NavigationLink {
    SongsView()
} label: {
    LibraryFeatureCard(
        title: "Nummers",
        subtitle: "\(library.songs.count) nummers"
    ) {
        SongsMosaicArtwork(
            songs: library.songs
        )
    }
}
.buttonStyle(.plain)



                                NavigationLink {
                PlaylistsView()
                    } label: {
                        LibraryFeatureCard(
                            title: "Playlists",
                           subtitle: "\(library.playlists.count) playlists"
                    ) {
                            PlaylistStackArtwork(
                            playlists: library.playlists
                        )
                }
            }
                        .buttonStyle(.plain)



                                // MARK: Favorites

                                NavigationLink {

                                    FavoritesView()

                                } label: {

                                    LibraryFeatureCard(
                                        title: "Favorieten",
                                        subtitle:
                                            "\(library.favoriteSongs.count) nummers"
                                    ) {

                                        FavoritesFeatureArtwork(
                                            songs:
                                                library.favoriteSongs
                                        )
                                    }
                                }

                                .buttonStyle(.plain)
                            }

                            .padding(.horizontal)
                        }
                    }



                    // MARK: Collections

                    VStack(
                        alignment: .leading,
                        spacing: 14
                    ) {

                        Text("Collecties")
                            .font(.title2.bold())
                            .padding(.horizontal)


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


                            // Artists

                            NavigationLink {

                                ArtistsView()

                            } label: {

                                CollectionCard(
                                    title: "Artiesten",
                                    subtitle:
                                        "\(artists.count) artiesten",
                                    symbol:
                                        "person.2.fill"
                                ) {

                                    ArtistCollectionArtwork(
                                        artists:
                                            artists
                                    )
                                }
                            }

                            .buttonStyle(.plain)



                            // Albums

                            NavigationLink {

                                AlbumsView()

                            } label: {

                                CollectionCard(
                                    title: "Albums",
                                    subtitle:
                                        "\(albumGroups.count) albums",
                                    symbol:
                                        "square.stack.fill"
                                ) {

                                    AlbumCollectionArtwork(
                                        albums:
                                            albumGroups
                                    )
                                }
                            }

                            .buttonStyle(.plain)



                            // Recent Added

                            NavigationLink {

                                RecentAddedView()

                            } label: {

                                CollectionCard(
                                    title:
                                        "Recent toegevoegd",
                                    subtitle:
                                        recentAddedSubtitle,
                                    symbol:
                                        "plus"
                                ) {

                                    CoverStackArtwork(
                                        songs:
                                            recentlyAddedSongs
                                    )
                                }
                            }

                            .buttonStyle(.plain)



                            // Recent Played

                            NavigationLink {

                                RecentPlayedView()

                            } label: {

                                CollectionCard(
                                    title:
                                        "Recent afgespeeld",
                                    subtitle:
                                        recentPlayedSubtitle,
                                    symbol:
                                        "clock.arrow.circlepath"
                                ) {

                                    CoverStackArtwork(
                                        songs:
                                            recentlyPlayedSongs
                                    )
                                }
                            }

                            .buttonStyle(.plain)
                        }

                        .padding(.horizontal)
                    }
                }

                .padding(.top, 8)
                .padding(.bottom, 120)
            }

            .navigationTitle(
                "Bibliotheek"
            )

            .navigationBarTitleDisplayMode(
                .large
            )


          
        }
    }


    // MARK: - Recent Data

    private var recentlyAddedSongs: [Song] {

        Array(
            library.songs
                .sorted {
                    $0.dateAdded > $1.dateAdded
                }
                .prefix(4)
        )
    }


    private var recentlyPlayedSongs: [Song] {

        Array(
            library.songs
                .filter {
                    $0.lastPlayed != nil
                }
                .sorted {
                    ($0.lastPlayed ?? .distantPast)
                    >
                    ($1.lastPlayed ?? .distantPast)
                }
                .prefix(4)
        )
    }


    private var recentAddedSubtitle: String {

        guard
            let first =
                recentlyAddedSongs.first
        else {

            return "Nog geen nummers"
        }


        return first.title
    }


    private var recentPlayedSubtitle: String {

        guard
            let first =
                recentlyPlayedSongs.first
        else {

            return "Nog niets afgespeeld"
        }


        return first.title
    }
}



// MARK: - Main Feature Card

struct LibraryFeatureCard<
    Artwork: View
>: View {

    let title: String
    let subtitle: String

    @ViewBuilder
    let artwork: Artwork


    init(
        title: String,
        subtitle: String,
        @ViewBuilder artwork:
            () -> Artwork
    ) {

        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork()
    }


    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            artwork

                .frame(
                    width: 168,
                    height: 168
                )

                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 22,
                        style: .continuous
                    )
                )


            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)


            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        .frame(
            width: 168,
            alignment: .leading
        )
    }
}



// MARK: - Songs Mosaic Artwork

struct SongsMosaicArtwork: View {

    let songs: [Song]


    private var displayedSongs: [Song] {

        Array(
            songs.prefix(4)
        )
    }


    var body: some View {

        GeometryReader { geometry in

            let gap: CGFloat = 2

            let side =
                (
                    geometry.size.width
                    - gap
                )
                / 2


            ZStack {

                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .fill(.thinMaterial)


                if displayedSongs.isEmpty {

                    Image(
                        systemName:
                            "music.note"
                    )
                    .font(
                        .system(
                            size: 48,
                            weight: .medium
                        )
                    )

                } else {

                    LazyVGrid(
                        columns: [
                            GridItem(
                                .fixed(side),
                                spacing: gap
                            ),
                            GridItem(
                                .fixed(side),
                                spacing: gap
                            )
                        ],
                        spacing: gap
                    ) {

                        ForEach(
                            0..<4,
                            id: \.self
                        ) { index in

                            if
                                displayedSongs.indices
                                    .contains(index)
                            {

                                RawSongArtwork(
                                    song:
                                        displayedSongs[index]
                                )
                                .frame(
                                    width: side,
                                    height: side
                                )

                            } else {

                                Rectangle()
                                    .fill(.thinMaterial)
                                    .frame(
                                        width: side,
                                        height: side
                                    )
                            }
                        }
                    }
                }
            }

            .clipped()
        }
    }
}



// MARK: - Playlist Stack Artwork

struct PlaylistStackArtwork: View {

    let playlists: [Playlist]


    var body: some View {

        GeometryReader { geometry in

            ZStack {

                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .fill(.thinMaterial)


                if playlists.isEmpty {

                    Image(
                        systemName:
                            "music.note.list"
                    )
                    .font(
                        .system(
                            size: 46,
                            weight: .medium
                        )
                    )

                } else {

                    ZStack {

                        playlistCard(
                            index: 2,
                            size:
                                geometry.size.width
                                * 0.59
                        )
                        .rotationEffect(
                            .degrees(9)
                        )
                        .offset(
                            x: 19,
                            y: -4
                        )


                        playlistCard(
                            index: 1,
                            size:
                                geometry.size.width
                                * 0.65
                        )
                        .rotationEffect(
                            .degrees(-7)
                        )
                        .offset(
                            x: -17,
                            y: 7
                        )


                        playlistCard(
                            index: 0,
                            size:
                                geometry.size.width
                                * 0.72
                        )
                    }
                }
            }
        }
    }


    @ViewBuilder
    private func playlistCard(
        index: Int,
        size: CGFloat
    ) -> some View {

        if
            playlists.indices
                .contains(index)
        {

            let playlist =
                playlists[index]


            ZStack {

                if
                    let data =
                        playlist.imageData,
                    let image =
                        UIImage(data: data)
                {

                    Image(
                        uiImage: image
                    )
                    .resizable()
                    .scaledToFill()

                } else {

                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                    .fill(.regularMaterial)


                    VStack(
                        spacing: 6
                    ) {

                        Image(
                            systemName:
                                "music.note.list"
                        )
                        .font(.title2)


                        Text(
                            playlist.name
                        )
                        .font(.caption.bold())
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                    }
                }
            }

            .frame(
                width: size,
                height: size
            )

            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )

            .shadow(
                radius: 8,
                y: 4
            )

        } else {

            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .fill(.regularMaterial)
            .frame(
                width: size,
                height: size
            )
        }
    }
}



// MARK: - Favorites Feature Artwork

struct FavoritesFeatureArtwork: View {

    let songs: [Song]


    private var covers: [Song] {

        Array(
            songs.prefix(4)
        )
    }


    var body: some View {

        GeometryReader { geometry in

            ZStack {

                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .fill(.thinMaterial)


                if !covers.isEmpty {

                    HStack(
                        spacing: -22
                    ) {

                        ForEach(
                            Array(
                                covers.prefix(3)
                            )
                        ) { song in

                            RawSongArtwork(
                                song: song
                            )

                            .frame(
                                width:
                                    geometry.size.width
                                    * 0.44,
                                height:
                                    geometry.size.width
                                    * 0.44
                            )

                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 13,
                                    style:
                                        .continuous
                                )
                            )

                            .shadow(
                                radius: 5,
                                y: 3
                            )
                        }
                    }

                    .opacity(0.72)
                    .offset(y: 14)
                }


                Circle()
                    .fill(.regularMaterial)
                    .frame(
                        width: 72,
                        height: 72
                    )

                    .shadow(
                        radius: 10,
                        y: 4
                    )


                Image(
                    systemName: "heart.fill"
                )
                .font(
                    .system(
                        size: 34,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.red)
            }
        }
    }
}



// MARK: - Collection Card

struct CollectionCard<
    Artwork: View
>: View {

    let title: String
    let subtitle: String
    let symbol: String

    @ViewBuilder
    let artwork: Artwork


    init(
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder artwork:
            () -> Artwork
    ) {

        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.artwork = artwork()
    }


    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 10
        ) {

            ZStack(
                alignment: .bottomLeading
            ) {

                artwork

                .frame(
                    maxWidth: .infinity
                )

                .frame(
                    height: 105
                )


                Image(
                    systemName: symbol
                )

                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )

                .frame(
                    width: 32,
                    height: 32
                )

                .background(
                    .regularMaterial,
                    in: Circle()
                )

                .padding(10)
            }

            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )


            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)


            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )

        .padding(10)

        .background(
            .thinMaterial,
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
    }
}



// MARK: - Artist Collection Artwork

struct ArtistCollectionArtwork: View {

    let artists: [ArtistGroup]


    var body: some View {

        GeometryReader { geometry in

            ZStack {

                Rectangle()
                    .fill(.thinMaterial)


                HStack(
                    spacing: -16
                ) {

                    ForEach(
                        Array(
                            artists.prefix(3)
                        )
                    ) { artist in

                        ArtistArtworkView(
                            songs: artist.songs
                        )

                        .frame(
                            width: 66,
                            height: 66
                        )

                        .clipShape(
                            Circle()
                        )

                        .overlay {

                            Circle()
                                .stroke(
                                    .background,
                                    lineWidth: 2
                                )
                        }
                    }
                }
            }
        }
    }
}



// MARK: - Album Collection Artwork

struct AlbumCollectionArtwork: View {

    let albums: [AlbumGroup]


    var body: some View {

        ZStack {

            Rectangle()
                .fill(.thinMaterial)


            if
                albums.count > 1,
                let second =
                    albums[1].songs.first
            {

                SongArtworkView(
                    song: second,
                    cornerRadius: 13
                )

                .frame(
                    width: 70,
                    height: 70
                )

                .rotationEffect(
                    .degrees(8)
                )

                .offset(
                    x: 20,
                    y: -4
                )
            }


            if
                let firstAlbum =
                    albums.first,
                let song =
                    firstAlbum.songs.first
            {

                SongArtworkView(
                    song: song,
                    cornerRadius: 13
                )

                .frame(
                    width: 75,
                    height: 75
                )

                .rotationEffect(
                    .degrees(-5)
                )

                .offset(
                    x: -15,
                    y: 7
                )
            }
        }
    }
}



// MARK: - Cover Stack

struct CoverStackArtwork: View {

    let songs: [Song]


    var body: some View {

        ZStack {

            Rectangle()
                .fill(.thinMaterial)


            ForEach(
                Array(
                    songs.prefix(3)
                        .enumerated()
                ),
                id: \.offset
            ) { index, song in

                SongArtworkView(
                    song: song,
                    cornerRadius: 12
                )

                .frame(
                    width: 68,
                    height: 68
                )

                .rotationEffect(
                    .degrees(
                        Double(index - 1)
                        * 6
                    )
                )

                .offset(
                    x:
                        CGFloat(index - 1)
                        * 15,
                    y:
                        CGFloat(index)
                        * 2
                )
            }
        }
    }
}



// MARK: - Artists

struct ArtistsView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @State private var searchText = ""


    private var allArtists: [ArtistGroup] {

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


    private var artists: [ArtistGroup] {

        guard
            !searchText.isEmpty
        else {

            return allArtists
        }


        return allArtists.filter {

            $0.name
                .localizedCaseInsensitiveContains(
                    searchText
                )
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
                    .clipShape(
                        Circle()
                    )


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

        .searchable(
            text: $searchText,
            prompt: "Zoek artiesten"
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
                        .clipShape(
                            Circle()
                        )


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

                        $0.title
                            .localizedCaseInsensitiveCompare(
                                $1.title
                            )
                        ==
                        .orderedAscending
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

        guard
            let url =
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

    @State private var searchText = ""


    private var allAlbums: [AlbumGroup] {

        let songs =
            library.songs.filter {

                guard
                    let album =
                        $0.album?
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
                    let first =
                        songs.first,
                    let album =
                        first.album
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

                $0.name
                    .localizedCaseInsensitiveCompare(
                        $1.name
                    )
                ==
                .orderedAscending
            }
    }


    private var albums: [AlbumGroup] {

        guard
            !searchText.isEmpty
        else {

            return allAlbums
        }


        return allAlbums.filter {

            $0.name
                .localizedCaseInsensitiveContains(
                    searchText
                )

            ||

            $0.artist
                .localizedCaseInsensitiveContains(
                    searchText
                )
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

                    if
                        let first =
                            album.songs.first
                    {

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
                            .foregroundStyle(
                                .secondary
                            )
                    }
                }
            }
        }

        .navigationTitle(
            "Albums"
        )

        .searchable(
            text: $searchText,
            prompt: "Zoek albums"
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

                        if
                            let first =
                                album.songs.first
                        {

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
                            .font(
                                .title2.bold()
                            )


                        Text(album.artist)
                            .foregroundStyle(
                                .secondary
                            )
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

        guard
            let url =
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

                        ($0.lastPlayed ?? .distantPast)
                        >
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

        .navigationTitle(
            title
        )
    }


    private func play(
        _ song: Song
    ) {

        guard
            let url =
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



// MARK: - Song Row

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

        GeometryReader { geometry in

            RawSongArtwork(
                song: song
            )

            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )

            .clipped()
        }

        .clipShape(
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
    }
}



// MARK: - Raw Song Artwork

struct RawSongArtwork: View {

    let song: Song


    var body: some View {

        Group {

            if
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

                ZStack {

                    Rectangle()
                        .fill(.thinMaterial)


                    Image(
                        systemName:
                            "music.note"
                    )
                    .font(.title2)
                }
            }
        }
    }
}



// MARK: - Artist Artwork

struct ArtistArtworkView: View {

    let songs: [Song]


    var body: some View {

        GeometryReader { geometry in

            Group {

                if
                    let song =
                        songs.first(
                            where: {
                                $0.coverData
                                != nil
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

                    ZStack {

                        Rectangle()
                            .fill(.thinMaterial)


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
                    }
                }
            }

            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )

            .clipped()
        }
    }
}
