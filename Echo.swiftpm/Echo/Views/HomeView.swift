import SwiftUI

struct HomeView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(AudioPlayerManager.self)
    private var audioPlayer

    private let recommendationManager =
        RecommendationManager.shared

    private let homeSession =
        HomeSessionManager.shared

    @State private var recommendedSnapshot: [Song] = []
    @State private var recentlyPlayedSnapshot: [Song] = []
    @State private var favoritesSnapshot: [Song] = []

    @State private var showSettings = false
    @State private var selectedSong: Song?


    // MARK: - Recently Added

    private var recentlyAdded: [Song] {

        Array(
            library.songs
                .sorted {
                    $0.dateAdded > $1.dateAdded
                }
                .prefix(10)
        )
    }


    // MARK: - Artists

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
                    ? String(
                        localized:
                            "homeview_unknown_artist"
                    )
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
                $0.name
                    .localizedCaseInsensitiveCompare(
                        $1.name
                    )
                ==
                .orderedAscending
            }
    }


    // MARK: - Body

    var body: some View {

        NavigationStack {

            ScrollView {

                LazyVStack(
                    alignment: .leading,
                    spacing: 32
                ) {

                    // MARK: Header

                    HStack(
                        alignment: .center
                    ) {

                        Text("homeview_title")
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
                                .title3
                                    .weight(.medium)
                            )
                            .foregroundStyle(.primary)
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


                    // MARK: - Recommended

                    if !recommendedSnapshot.isEmpty {

                        songSection(
                            title:
                                "homeview_recommended_for_you",
                            songs:
                                recommendedSnapshot
                        )
                    }


                    // MARK: - Recently Played

                    if !recentlyPlayedSnapshot.isEmpty {

                        songSection(
                            title:
                                "homeview_recent_played",
                            songs:
                                recentlyPlayedSnapshot
                        )
                    }


                    // MARK: - Recently Added

                    if !recentlyAdded.isEmpty {

                        songSection(
                            title:
                                "homeview_recent_added",
                            songs:
                                recentlyAdded
                        )
                    }


                    // MARK: - Favorites

                    if !favoritesSnapshot.isEmpty {

                        songSection(
                            title:
                                "homeview_favorites",
                            songs:
                                favoritesSnapshot,
                            queue:
                                favoritesSnapshot
                        )
                    }


                    // MARK: - Artists

                    if !artists.isEmpty {
                        artistSection
                    }


                    // MARK: - Empty Library

                    if library.songs.isEmpty {

                        ContentUnavailableView(
                            "homeview_empty_title",
                            systemImage:
                                "music.note",
                            description:
                                Text(
                                    "homeview_empty_description"
                                )
                        )
                        .frame(
                            maxWidth: .infinity
                        )
                        .padding(.top, 80)
                    }
                }
                .padding(.bottom, 120)
            }


            // MARK: - Settings

            .sheet(
                isPresented:
                    $showSettings
            ) {
                SettingsView()
            }

            .sheet(
                item: $selectedSong
            ) { song in
                SongOptionsView(
                    song: song
                )
            }

            .sheet(
                item:
                    Bindable(library)
                        .songToAddToPlaylist
            ) { song in
                PlaylistPickerView(
                    songs: [song]
                )
            }

            .sheet(
                isPresented:
                    Bindable(library)
                        .showEditSheet
            ) {
                if let song =
                    library.editingSong
                {
                    EditSongView(
                        song: song
                    )
                }
            }


            // MARK: - Session Snapshot

            .onAppear {

                prepareSessionSnapshots()
            }


            // Alleen nodig om een lege/new library tijdens
            // dezelfde sessie bruikbaar te houden.
            //
            // Bestaande recommendations worden NIET opnieuw
            // berekend wanneer de learning engine verandert.
            .onChange(
                of:
                    library.songs
                        .map(\.id)
            ) {
                _, _ in

                prepareSessionSnapshots()
            }
        }
    }


    // MARK: - Prepare Session Snapshots

    private func prepareSessionSnapshots() {

        homeSession.prepareIfNeeded(
            songs:
                library.songs,
            favorites:
                library.favoriteSongs,
            favoriteSongIDs:
                library.favoriteSongIDs,
            recommendationManager:
                recommendationManager
        )

        recommendedSnapshot =
            homeSession.recommendedSongs
            ?? []

        recentlyPlayedSnapshot =
            homeSession.recentlyPlayedSongs
            ?? []

        favoritesSnapshot =
            homeSession.favoriteSongs
            ?? []
    }


    // MARK: - Song Section

    @ViewBuilder
    private func songSection(
        title: LocalizedStringKey,
        songs: [Song],
        queue: [Song]? = nil
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 13
        ) {

            Text(title)
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {

                LazyHStack(spacing: 15) {

                    ForEach(songs) { song in

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
                                .foregroundStyle(
                                    .primary
                                )
                                .lineLimit(1)

                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                                .lineLimit(1)
                        }
                        .frame(
                            width: 150,
                            alignment: .leading
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            play(
                                song,
                                queue:
                                    queue
                                    ?? [song]
                            )
                        }
                        .onLongPressGesture {
                            selectedSong = song
                        }
                        .accessibilityAddTraits(
                            .isButton
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }


    // MARK: - Artist Section

    private var artistSection: some View {

        VStack(
            alignment: .leading,
            spacing: 13
        ) {

            HStack {

                Text(
                    "homeview_your_artists"
                )
                .font(.title2.bold())

                Spacer()

                NavigationLink {

                    ArtistsView()

                } label: {

                    Text(
                        "homeview_show_all"
                    )
                    .font(
                        .subheadline
                            .weight(.medium)
                    )
                }
            }
            .padding(.horizontal)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {

                LazyHStack(spacing: 18) {

                    ForEach(
                        Array(
                            artists.prefix(12)
                        )
                    ) { artist in

                        NavigationLink {

                            ArtistDetailView(
                                artist: artist
                            )

                        } label: {

                            VStack(spacing: 8) {

                                ArtistArtworkView(
                                    songs:
                                        artist.songs
                                )
                                .frame(
                                    width: 112,
                                    height: 112
                                )
                                .clipShape(
                                    Circle()
                                )

                                Text(
                                    artist.name
                                )
                                .font(
                                    .subheadline
                                        .weight(
                                            .medium
                                        )
                                )
                                .foregroundStyle(
                                    .primary
                                )
                                .lineLimit(1)
                                .frame(
                                    width: 112
                                )
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
            from:
                library.songs
        )
    }
}
