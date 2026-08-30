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

        guard
            !searchText.isEmpty
        else {

            return []
        }


        return library.songs.filter {

            $0.title
                .localizedCaseInsensitiveContains(
                    searchText
                )

            ||

            $0.artist
                .localizedCaseInsensitiveContains(
                    searchText
                )

            ||

            (
                $0.album?
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

        guard
            !searchText.isEmpty
        else {

            return []
        }


        let grouped =
            Dictionary(
                grouping: library.songs
            ) {

                let artist =
                    $0.artist
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
                grouping: validSongs
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
    }


    private var matchingAlbums: [AlbumGroup] {

        guard
            !searchText.isEmpty
        else {

            return []
        }


        return allAlbums
            .filter {

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

        guard
            !searchText.isEmpty
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

            Group {

                if searchText.isEmpty {

                    ContentUnavailableView(
                        "Zoeken",
                        systemImage:
                            "magnifyingglass",
                        description: Text(
                            "Zoek naar nummers, artiesten, albums en playlists in Echo."
                        )
                    )

                } else if !hasResults {

                    ContentUnavailableView.search(
                        text: searchText
                    )

                } else {

                    List {


                        // MARK: Songs

                        if !matchingSongs.isEmpty {

                            Section(
                                "Nummers"
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
                                    }

                                    .buttonStyle(.plain)
                                }


                                if
                                    matchingSongs.count > 10,
                                    !showAllSongs
                                {

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
                                                    .weight(.medium)
                                            )


                                            Spacer()


                                            Image(
                                                systemName:
                                                    "chevron.down"
                                            )
                                            .font(.caption)
                                        }
                                    }
                                }
                            }
                        }



                        // MARK: Artists

                        if !matchingArtists.isEmpty {

                            Section(
                                "Artiesten"
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
                                                width: 50,
                                                height: 50
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
                                        }
                                    }
                                }
                            }
                        }



                        // MARK: Albums

                        if !matchingAlbums.isEmpty {

                            Section(
                                "Albums"
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
                                        }
                                    }
                                }
                            }
                        }



                        // MARK: Playlists

                        if !matchingPlaylists.isEmpty {

                            Section(
                                "Playlists"
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
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            .navigationTitle(
                "Zoeken"
            )

            .navigationBarTitleDisplayMode(
                .large
            )


            // MARK: Settings

            .toolbar {

                ToolbarItem(
                    placement: .topBarTrailing
                ) {

                    Button {

                        showSettings = true

                    } label: {

                        Image(
                            systemName:
                                "gearshape"
                        )
                    }
                }
            }


            .sheet(
                isPresented: $showSettings
            ) {

                SettingsView()
            }


            .searchable(
                text: $searchText,
                placement:
                    .navigationBarDrawer(
                        displayMode:
                            .always
                    ),
                prompt:
                    "Nummers, artiesten, albums en playlists"
            )


            .onChange(
                of: searchText
            ) {

                showAllSongs = false
            }
        }
    }


    // MARK: - Play

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
