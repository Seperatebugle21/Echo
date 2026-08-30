import SwiftUI


struct SearchView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(AudioPlayerManager.self)
    private var audioPlayer


    @State private var searchText = ""


    // MARK: - Songs

    private var matchingSongs: [Song] {

        guard !searchText.isEmpty
        else {
            return []
        }


        return library.songs.filter {

            $0.title.localizedCaseInsensitiveContains(
                searchText
            )

            ||

            $0.artist.localizedCaseInsensitiveContains(
                searchText
            )

            ||

            ($0.album?
                .localizedCaseInsensitiveContains(
                    searchText
                ) ?? false)
        }
    }


    // MARK: - Playlists

    private var matchingPlaylists: [Playlist] {

        guard !searchText.isEmpty
        else {
            return []
        }


        return library.playlists.filter {

            $0.name.localizedCaseInsensitiveContains(
                searchText
            )
        }
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

                $0.key.localizedCaseInsensitiveContains(
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

                $0.name.localizedCaseInsensitiveCompare(
                    $1.name
                ) == .orderedAscending
            }
    }


    private var hasResults: Bool {

        !matchingSongs.isEmpty
        ||
        !matchingPlaylists.isEmpty
        ||
        !matchingArtists.isEmpty
    }


    // MARK: - Body

    var body: some View {

        NavigationStack {

            Group {

                if searchText.isEmpty {

                    ContentUnavailableView(
                        "Zoeken",
                        systemImage: "magnifyingglass",
                        description: Text(
                            "Zoek naar nummers, artiesten en playlists in Echo."
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
                                    matchingSongs
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
                                            artist: artist
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
                                                alignment: .leading,
                                                spacing: 2
                                            ) {

                                                Text(
                                                    artist.name
                                                )
                                                .font(.headline)


                                                Text(
                                                    "\(artist.songs.count) nummers"
                                                )
                                                .font(.caption)
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
                                                alignment: .leading,
                                                spacing: 2
                                            ) {

                                                Text(
                                                    playlist.name
                                                )
                                                .font(.headline)


                                                Text(
                                                    "\(playlist.songIDs.count) nummers"
                                                )
                                                .font(.caption)
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

            .searchable(
                text: $searchText,
                placement:
                    .navigationBarDrawer(
                        displayMode: .always
                    ),
                prompt:
                    "Nummers, artiesten en playlists"
            )

            .padding(
                .bottom,
                searchText.isEmpty
                ? 80
                : 0
            )
        }
    }


    // MARK: - Play

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

                Image(
                    systemName:
                        "music.note.list"
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
                cornerRadius: 12,
                style: .continuous
            )
        )
    }
}
