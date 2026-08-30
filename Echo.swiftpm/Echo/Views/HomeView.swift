import SwiftUI

struct HomeView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(AudioPlayerManager.self)
    private var audioPlayer


    // MARK: - Data

    private var recentlyPlayed: [Song] {

        Array(
            library.songs
                .filter { $0.lastPlayed != nil }
                .sorted {
                    ($0.lastPlayed ?? .distantPast) >
                    ($1.lastPlayed ?? .distantPast)
                }
                .prefix(10)
        )
    }


    private var recentlyAdded: [Song] {

        Array(
            library.songs
                .sorted {
                    $0.dateAdded > $1.dateAdded
                }
                .prefix(10)
        )
    }


    private var favorites: [Song] {

        Array(
            library.favoriteSongs
                .prefix(10)
        )
    }


    private var artists: [ArtistGroup] {

        let grouped = Dictionary(
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


    // MARK: - Body

    var body: some View {

        NavigationStack {

            ScrollView {

                LazyVStack(
                    alignment: .leading,
                    spacing: 30
                ) {

                    if !recentlyPlayed.isEmpty {

                        songSection(
                            title: "Recent afgespeeld",
                            songs: recentlyPlayed
                        )
                    }


                    if !recentlyAdded.isEmpty {

                        songSection(
                            title: "Recent toegevoegd",
                            songs: recentlyAdded
                        )
                    }


                    if !favorites.isEmpty {

                        songSection(
                            title: "Favorieten",
                            songs: favorites
                        )
                    }


                    if !artists.isEmpty {

                        artistSection
                    }


                    if library.songs.isEmpty {

                        ContentUnavailableView(
                            "Nog geen muziek",
                            systemImage: "music.note",
                            description: Text(
                                "Voeg muziek toe via Fetch of je bibliotheek."
                            )
                        )
                        .frame(
                            maxWidth: .infinity
                        )
                        .padding(.top, 80)
                    }
                }
                .padding(.vertical)
                .padding(.bottom, 120)
            }

            .navigationTitle("Home")
        }
    }


    // MARK: - Songs section

    @ViewBuilder
    private func songSection(
        title: String,
        songs: [Song]
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            Text(title)
                .font(.title2)
                .bold()
                .padding(.horizontal)


            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {

                LazyHStack(
                    spacing: 15
                ) {

                    ForEach(songs) { song in

                        Button {

                            play(song)

                        } label: {

                            VStack(
                                alignment: .leading,
                                spacing: 7
                            ) {

                                SongArtworkView(
                                    song: song,
                                    cornerRadius: 16
                                )
                                .frame(
                                    width: 150,
                                    height: 150
                                )


                                Text(song.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)


                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(
                                width: 150,
                                alignment: .leading
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }


    // MARK: - Artists

    private var artistSection: some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            HStack {

                Text("Jouw artiesten")
                    .font(.title2)
                    .bold()

                Spacer()

                NavigationLink {

                    ArtistsView()

                } label: {

                    Text("Toon alles")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal)


            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {

                LazyHStack(
                    spacing: 18
                ) {

                    ForEach(
                        Array(artists.prefix(12))
                    ) { artist in

                        NavigationLink {

                            ArtistDetailView(
                                artist: artist
                            )

                        } label: {

                            VStack(
                                spacing: 8
                            ) {

                                ArtistArtworkView(
                                    songs: artist.songs
                                )
                                .frame(
                                    width: 112,
                                    height: 112
                                )
                                .clipShape(Circle())


                                Text(artist.name)
                                    .font(
                                        .subheadline
                                            .weight(.medium)
                                    )
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(width: 112)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
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
