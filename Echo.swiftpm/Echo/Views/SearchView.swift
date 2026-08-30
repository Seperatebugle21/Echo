import SwiftUI


struct SearchView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(AudioPlayerManager.self)
    private var audioPlayer


    @State private var searchText = ""
    @State private var showAllSongs = false
    @State private var showSettings = false


    // MARK: - Songs

    private var matchingSongs: [Song] {

        guard !searchText.isEmpty
        else {
            return []
        }


        return library.songs.filter { song in

            song.title.localizedCaseInsensitiveContains(
                searchText
            )

            ||

            song.artist.localizedCaseInsensitiveContains(
                searchText
            )

            ||

            (
                song.album?
                    .localizedCaseInsensitiveContains(
                        searchText
                    )
                ?? false
            )
        }
    }


    private var displayedSongs: [Song] {

        if showAllSongs {
            return matchingSongs
        }


        return Array(
            matchingSongs.prefix(10)
        )
    }



    // MARK: - Artists

    private var matchingArtists: [ArtistGroup] {

        guard !searchText.isEmpty
        else {
            return []
        }


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
            .filter {

                $0.key
                    .localizedCaseInsensitiveContains(
                        searchText
                    )
            }

            .map {

                ArtistGroup(
                    name: $0.key,
                    songs: $0.value
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



    // MARK: - Albums

    private var allAlbums: [AlbumGroup] {

        let validSongs =
            library.songs.filter { song in

                guard
                    let album =
                        song.album?
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
                grouping: validSongs
            ) { song in

                "\(song.artist)|\(song.album ?? "")"
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
    }


    private var matchingAlbums: [AlbumGroup] {

        guard !searchText.isEmpty
        else {
            return []
        }


        return allAlbums
            .filter { album in

                album.name
                    .localizedCaseInsensitiveContains(
                        searchText
                    )

                ||

                album.artist
                    .localizedCaseInsensitiveContains(
                        searchText
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



    // MARK: - Playlists

    private var matchingPlaylists: [Playlist] {

        guard !searchText.isEmpty
        else {
            return []
        }


        return library.playlists.filter {

            $0.name
                .localizedCaseInsensitiveContains(
                    searchText
                )
        }
    }



    // MARK: - Results

    private var hasResults: Bool {

        !matchingSongs.isEmpty
        ||
        !matchingArtists.isEmpty
        ||
        !matchingAlbums.isEmpty
        ||
        !matchingPlaylists.isEmpty
    }



    // MARK: - Body

    var body: some View {

        NavigationStack {

            ScrollView {

                LazyVStack(
                    alignment: .leading,
                    spacing: 22
                ) {


                    // MARK: - Header

                    HStack(
                        alignment: .center
                    ) {

                        Text("Zoeken")
                            .font(
                                .largeTitle.bold()
                            )


                        Spacer()


                        Button {

                            showSettings = true

                        } label: {

                            Image(
                                systemName:
                                    "gearshape"
                            )
                            .font(
                                .title3.weight(
                                    .medium
                                )
                            )
                            .foregroundStyle(
                                .primary
                            )

                            .frame(
                                width: 42,
                                height: 42
                            )

                            .background(
                                .thinMaterial,
                                in: Circle()
                            )
                        }

                        .buttonStyle(.plain)
                    }

                    .padding(.horizontal)
                    .padding(.top, 6)



                    // MARK: - Search Bar

                    HStack(
                        spacing: 10
                    ) {

                        Image(
                            systemName:
                                "magnifyingglass"
                        )
                        .foregroundStyle(
                            .secondary
                        )


                        TextField(
                            "Nummers, artiesten, albums en playlists",
                            text: $searchText
                        )

                        .textInputAutocapitalization(
                            .never
                        )

                        .autocorrectionDisabled()


                        if !searchText.isEmpty {

                            Button {

                                searchText = ""

                            } label: {

                                Image(
                                    systemName:
                                        "xmark.circle.fill"
                                )
                                .foregroundStyle(
                                    .secondary
                                )
                            }

                            .buttonStyle(.plain)
                        }
                    }

                    .padding(.horizontal, 14)
                    .frame(height: 42)

                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )

                    .padding(.horizontal)



                    // MARK: - Empty Search

                    if searchText.isEmpty {

                        VStack(
                            spacing: 12
                        ) {

                            Image(
                                systemName:
                                    "magnifyingglass"
                            )
                            .font(
                                .system(
                                    size: 38,
                                    weight: .medium
                                )
                            )
                            .foregroundStyle(
                                .secondary
                            )


                            Text(
                                "Zoek in Echo"
                            )
                            .font(
                                .title3.bold()
                            )


                            Text(
                                "Zoek naar nummers, artiesten, albums en playlists."
                            )
                            .font(.subheadline)
                            .foregroundStyle(
                                .secondary
                            )
                            .multilineTextAlignment(
                                .center
                            )
                        }

                        .frame(
                            maxWidth: .infinity
                        )

                        .padding(.horizontal, 30)
                        .padding(.top, 70)
                    }



                    // MARK: - No Results

                    else if !hasResults {

                        VStack(
                            spacing: 12
                        ) {

                            Image(
                                systemName:
                                    "magnifyingglass"
                            )
                            .font(
                                .system(
                                    size: 38,
                                    weight: .medium
                                )
                            )
                            .foregroundStyle(
                                .secondary
                            )


                            Text(
                                "Geen resultaten"
                            )
                            .font(
                                .title3.bold()
                            )


                            Text(
                                "Geen resultaten gevonden voor “\(searchText)”."
                            )
                            .font(.subheadline)
                            .foregroundStyle(
                                .secondary
                            )
                            .multilineTextAlignment(
                                .center
                            )
                        }

                        .frame(
                            maxWidth: .infinity
                        )

                        .padding(.horizontal, 30)
                        .padding(.top, 70)
                    }



                    // MARK: - Results

                    else {


                        // MARK: Songs

                        if !matchingSongs.isEmpty {

                            SearchSection(
                                title: "Nummers"
                            ) {

                                VStack(
                                    spacing: 0
                                ) {

                                    ForEach(
                                        displayedSongs
                                    ) { song in

                                        Button {

                                            play(song)

                                        } label: {

                                            LibrarySongRow(
                                                song: song
                                            )
                                            .padding(
                                                .vertical,
                                                9
                                            )
                                        }

                                        .buttonStyle(.plain)


                                        if
                                            song.id
                                            !=
                                            displayedSongs.last?.id
                                        {

                                            Divider()
                                                .padding(
                                                    .leading,
                                                    62
                                                )
                                        }
                                    }


                                    if
                                        matchingSongs.count > 10,
                                        !showAllSongs
                                    {

                                        Divider()
                                            .padding(
                                                .leading,
                                                62
                                            )


                                        Button {

                                            withAnimation {

                                                showAllSongs =
                                                    true
                                            }

                                        } label: {

                                            HStack {

                                                Text(
                                                    "Toon alle \(matchingSongs.count) resultaten"
                                                )
                                                .font(
                                                    .subheadline
                                                        .weight(
                                                            .medium
                                                        )
                                                )


                                                Spacer()


                                                Image(
                                                    systemName:
                                                        "chevron.down"
                                                )
                                                .font(
                                                    .caption.bold()
                                                )
                                            }

                                            .padding(
                                                .vertical,
                                                13
                                            )
                                        }

                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }



                        // MARK: Artists

                        if !matchingArtists.isEmpty {

                            SearchSection(
                                title: "Artiesten"
                            ) {

                                VStack(
                                    spacing: 0
                                ) {

                                    ForEach(
                                        matchingArtists
                                    ) { artist in

                                        NavigationLink {

                                            ArtistDetailView(
                                                artist:
                                                    artist
                                            )

                                        } label: {

                                            HStack(
                                                spacing: 12
                                            ) {

                                                ArtistArtworkView(
                                                    songs:
                                                        artist.songs
                                                )
                                                .frame(
                                                    width: 52,
                                                    height: 52
                                                )
                                                .clipShape(
                                                    Circle()
                                                )


                                                VStack(
                                                    alignment:
                                                        .leading,
                                                    spacing: 2
                                                ) {

                                                    Text(
                                                        artist.name
                                                    )
                                                    .font(
                                                        .headline
                                                    )
                                                    .foregroundStyle(
                                                        .primary
                                                    )


                                                    Text(
                                                        "\(artist.songs.count) nummers"
                                                    )
                                                    .font(
                                                        .caption
                                                    )
                                                    .foregroundStyle(
                                                        .secondary
                                                    )
                                                }


                                                Spacer()


                                                Image(
                                                    systemName:
                                                        "chevron.right"
                                                )
                                                .font(
                                                    .caption.bold()
                                                )
                                                .foregroundStyle(
                                                    .tertiary
                                                )
                                            }

                                            .padding(
                                                .vertical,
                                                8
                                            )
                                        }

                                        .buttonStyle(.plain)


                                        if
                                            artist.id
                                            !=
                                            matchingArtists.last?.id
                                        {

                                            Divider()
                                                .padding(
                                                    .leading,
                                                    64
                                                )
                                        }
                                    }
                                }
                            }
                        }



                        // MARK: Albums

                        if !matchingAlbums.isEmpty {

                            SearchSection(
                                title: "Albums"
                            ) {

                                VStack(
                                    spacing: 0
                                ) {

                                    ForEach(
                                        matchingAlbums
                                    ) { album in

                                        NavigationLink {

                                            AlbumDetailView(
                                                album:
                                                    album
                                            )

                                        } label: {

                                            HStack(
                                                spacing: 12
                                            ) {

                                                if
                                                    let song =
                                                        album
                                                            .songs
                                                            .first
                                                {

                                                    SongArtworkView(
                                                        song:
                                                            song,
                                                        cornerRadius:
                                                            10
                                                    )
                                                    .frame(
                                                        width: 52,
                                                        height: 52
                                                    )

                                                } else {

                                                    Image(
                                                        systemName:
                                                            "square.stack"
                                                    )
                                                    .frame(
                                                        width: 52,
                                                        height: 52
                                                    )
                                                    .background(
                                                        .thinMaterial
                                                    )
                                                    .clipShape(
                                                        RoundedRectangle(
                                                            cornerRadius:
                                                                10
                                                        )
                                                    )
                                                }


                                                VStack(
                                                    alignment:
                                                        .leading,
                                                    spacing: 2
                                                ) {

                                                    Text(
                                                        album.name
                                                    )
                                                    .font(
                                                        .headline
                                                    )
                                                    .foregroundStyle(
                                                        .primary
                                                    )


                                                    Text(
                                                        album.artist
                                                    )
                                                    .font(
                                                        .caption
                                                    )
                                                    .foregroundStyle(
                                                        .secondary
                                                    )
                                                }


                                                Spacer()


                                                Image(
                                                    systemName:
                                                        "chevron.right"
                                                )
                                                .font(
                                                    .caption.bold()
                                                )
                                                .foregroundStyle(
                                                    .tertiary
                                                )
                                            }

                                            .padding(
                                                .vertical,
                                                8
                                            )
                                        }

                                        .buttonStyle(.plain)


                                        if
                                            album.id
                                            !=
                                            matchingAlbums.last?.id
                                        {

                                            Divider()
                                                .padding(
                                                    .leading,
                                                    64
                                                )
                                        }
                                    }
                                }
                            }
                        }



                        // MARK: Playlists

                        if !matchingPlaylists.isEmpty {

                            SearchSection(
                                title: "Playlists"
                            ) {

                                VStack(
                                    spacing: 0
                                ) {

                                    ForEach(
                                        matchingPlaylists
                                    ) { playlist in

                                        NavigationLink {

                                            PlaylistDetailView(
                                                playlist:
                                                    playlist
                                            )

                                        } label: {

                                            HStack(
                                                spacing: 12
                                            ) {

                                                PlaylistSearchArtwork(
                                                    playlist:
                                                        playlist
                                                )
                                                .frame(
                                                    width: 52,
                                                    height: 52
                                                )


                                                VStack(
                                                    alignment:
                                                        .leading,
                                                    spacing: 2
                                                ) {

                                                    Text(
                                                        playlist.name
                                                    )
                                                    .font(
                                                        .headline
                                                    )
                                                    .foregroundStyle(
                                                        .primary
                                                    )


                                                    Text(
                                                        "\(playlist.songIDs.count) nummers"
                                                    )
                                                    .font(
                                                        .caption
                                                    )
                                                    .foregroundStyle(
                                                        .secondary
                                                    )
                                                }


                                                Spacer()


                                                Image(
                                                    systemName:
                                                        "chevron.right"
                                                )
                                                .font(
                                                    .caption.bold()
                                                )
                                                .foregroundStyle(
                                                    .tertiary
                                                )
                                            }

                                            .padding(
                                                .vertical,
                                                8
                                            )
                                        }

                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }

                .padding(.bottom, 120)
            }


            // Geen normale navigation title.
            // Daardoor komt er bovenaan geen tweede
            // lege navigation-bar ruimte.

            .toolbar(.hidden, for: .navigationBar)


            .sheet(
                isPresented:
                    $showSettings
            ) {

                SettingsView()
            }


            .onChange(
                of: searchText
            ) {

                showAllSongs = false
            }
        }
    }



    // MARK: - Playback

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
            queue: library.songs
        )


        audioPlayer.allSongs =
            library.songs


        audioPlayer.fillAutoNext(
            from: library.songs
        )
    }
}



// MARK: - Search Section

private struct SearchSection<
    Content: View
>: View {

    let title: String

    @ViewBuilder
    let content: Content


    init(
        title: String,
        @ViewBuilder content:
            () -> Content
    ) {

        self.title = title
        self.content = content()
    }


    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 9
        ) {

            Text(title)
                .font(
                    .title2.bold()
                )
                .padding(.horizontal)


            content
                .padding(.horizontal, 14)
                .background(
                    .thinMaterial,
                    in:
                        RoundedRectangle(
                            cornerRadius: 18,
                            style:
                                .continuous
                        )
                )
                .padding(.horizontal)
        }
    }
}



// MARK: - Playlist Artwork

struct PlaylistSearchArtwork: View {

    let playlist: Playlist


    var body: some View {

        GeometryReader { geometry in

            Group {

                if
                    let data =
                        playlist.imageData,
                    let image =
                        UIImage(
                            data: data
                        )
                {

                    Image(
                        uiImage: image
                    )
                    .resizable()
                    .scaledToFill()

                } else {

                    ZStack {

                        Rectangle()
                            .fill(
                                .thinMaterial
                            )


                        Image(
                            systemName:
                                "music.note.list"
                        )
                        .font(.title2)
                    }
                }
            }

            .frame(
                width:
                    geometry.size.width,
                height:
                    geometry.size.height
            )

            .clipped()
        }

        .clipShape(
            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
    }
}
