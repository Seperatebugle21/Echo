import SwiftUI

struct HomeView: View {
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @State private var picks: [Song] = []
    @State private var recent: [Song] = []
    @State private var added: [Song] = []
    @State private var favorites: [Song] = []
    @State private var localSongs: [Song] = []
    @State private var mixes: [HomePersonalMix] = []
    @State private var artistIDs: [String] = []
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var selectedSong: Song?
    @State private var optionsFeedback = 0
    @State private var podcastRecommendations = PodcastRecommendationsModel()
    private let session = HomeSessionManager.shared
    private let recommendations = RecommendationManager.shared

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let layout = HomeCardLayout(width: geometry.size.width)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        HomeNowPlayingSpotlight(fallback: recent.first ?? added.first, queue: localSongs)
                            .padding(.horizontal, 20)
                        quickAccess(layout: layout)
                        if !picks.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HomeSectionTitle(title: "home_quick_picks").padding(.horizontal, 20)
                                songRail(picks, width: layout.song)
                            }
                        }
                        if !mixes.isEmpty {
                            HomeForYouSection(mixes: mixes, width: layout.mix, play: play)
                        }
                        if !recent.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HomeSectionLink(title: "homeview_recent_played") { RecentPlayedView() }
                                songRail(Array(recent.prefix(12)), width: layout.song)
                            }
                        }
                        if !artistIDs.isEmpty { artistSection(width: layout.song) }
                        if !added.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HomeSectionLink(title: "homeview_recent_added") { RecentAddedView() }
                                songRail(Array(added.prefix(12)), width: layout.song)
                            }
                        }
                        HomeDiscoverySection(recommendations: podcastRecommendations.shows, playSong: play, width: layout.discovery)
                        // Keep Echo's existing album, favorite and podcast entry points.
                        HomeLocalAlbumSection(coverWidth: layout.song)
                        if !favorites.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HomeSectionLink(title: "homeview_favorites") { FavoritesView() }
                                songRail(Array(favorites.prefix(12)), width: layout.song)
                            }
                        }
                        PodcastRecommendationsSection(
                            shows: podcastRecommendations.shows, loading: podcastRecommendations.loading,
                            failed: podcastRecommendations.failed, retry: { podcastRecommendations.retry += 1 }
                        )
                        HomeOnlineAlbumSection(coverWidth: layout.song)
                        HomeSmartSections(coverWidth: layout.song)
                    }
                    .padding(.top, 8)
                    // ContentView already reserves the live MiniPlayer and tab safe areas.
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .echoBackground()
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showSearch) { SearchView() }
            .sheet(item: $selectedSong) { SongOptionsView(song: $0) }
            .sheet(item: Bindable(library).songToAddToPlaylist) { PlaylistPickerView(songs: [$0]) }
            .sheet(isPresented: Bindable(library).showEditSheet) {
                if let song = library.editingSong { EditSongView(song: song) }
            }
            .task(id: podcastRecommendations.taskID) { await podcastRecommendations.load() }
            .onAppear(perform: prepare)
            .onChange(of: library.songRevision) { prepare() }
            .onChange(of: library.favoriteRevision) { prepare() }
            .onChange(of: library.artistGroups.map(\.id)) { prepareArtists() }
            .onChange(of: scenePhase) { if scenePhase == .active { prepare() } }
            .sensoryFeedback(.selection, trigger: optionsFeedback)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("homeview_title").font(.largeTitle.weight(.heavy))
                Text("home_tagline").font(.system(size: 9, weight: .medium)).tracking(3)
                    .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            headerButton("sparkles", label: "ai_title") { AppRouter.shared.showIntelligence = true }
            headerButton("magnifyingglass", label: "tab_search") { showSearch = true }
            headerButton("gearshape", label: "tab_settings") { showSettings = true }
        }.padding(.horizontal, 20)
    }

    private func headerButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3.weight(.medium)).frame(width: 44, height: 44)
                .background(.thinMaterial, in: .circle)
                .overlay { Circle().strokeBorder(.primary.opacity(0.06)) }
                .contentShape(.circle)
        }.buttonStyle(HomePressStyle()).accessibilityLabel(label)
            .accessibilityIdentifier(symbol == "sparkles" ? "home-intelligence" : symbol == "gearshape" ? "home-settings" : "home-search")
    }

    private func quickAccess(layout: HomeCardLayout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionTitle(title: "home_quick_access").padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    NavigationLink { FavoritesView().toolbarVisibility(.visible, for: .navigationBar) } label: {
                        HomeQuickAccessCard(title: "libraryview_favorites", symbol: "heart.fill", count: favorites.count,
                                            playlists: false, song: favorites.first, width: layout.access, accent: true)
                    }
                    NavigationLink { RecentPlayedView().toolbarVisibility(.visible, for: .navigationBar) } label: {
                        HomeQuickAccessCard(title: "home_recent", symbol: "clock", count: recent.count,
                                            playlists: false, song: recent.first, width: layout.access)
                    }
                    NavigationLink { SongsView().toolbarVisibility(.visible, for: .navigationBar) } label: {
                        HomeQuickAccessCard(title: "home_downloads", symbol: "arrow.down.to.line", count: localSongs.count,
                                            playlists: false, song: added.first, width: layout.access)
                    }
                    NavigationLink { PlaylistsView().toolbarVisibility(.visible, for: .navigationBar) } label: {
                        HomeQuickAccessCard(title: "libraryview_playlists", symbol: "music.note.list", count: library.playlists.count,
                                            playlists: true, song: playlistArtworkSong, width: layout.access)
                    }
                }.buttonStyle(HomePressStyle()).padding(.horizontal, 20).padding(.vertical, 8)
            }.scrollIndicators(.hidden)
                .scrollClipDisabled()
        }
    }

    private var playlistArtworkSong: Song? {
        guard let playlist = library.playlists.first else { return nil }
        return library.songs(in: playlist).first
    }

    private func songRail(_ songs: [Song], width: CGFloat) -> some View {
        HomeSongRail(songs: songs, width: width, play: { play($0, songs) }, options: {
            optionsFeedback += 1
            selectedSong = $0
        })
    }

    private func artistSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionLink(title: "home_favorite_artists") { ArtistsView() }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(artistIDs, id: \.self) { id in
                        if let artist = library.artistGroupsByID[id] {
                            NavigationLink { ArtistDetailView(artist: artist).toolbarVisibility(.visible, for: .navigationBar) } label: {
                                VStack(spacing: 7) {
                                    ArtistArtworkView(songs: artist.songs).frame(width: width, height: width)
                                        .clipShape(.circle).homeCoverShadow().accessibilityHidden(true)
                                    Text(artist.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }.frame(width: width)
                            }.buttonStyle(HomePressStyle())
                        }
                    }
                }.padding(.horizontal, 20).padding(.vertical, 8)
            }.scrollIndicators(.hidden)
        }
    }

    private func prepare() {
        // getURL builds a path; check the file to exclude missing/download-in-progress tracks.
        localSongs = library.songs.filter {
            $0.podcastEpisodeID == nil && library.getURL(for: $0).map { FileManager.default.fileExists(atPath: $0.path) } == true
        }
        let localIDs = Set(localSongs.map(\.id))
        favorites = library.favoriteSongs.filter { localIDs.contains($0.id) }
        recent = localSongs.filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        added = localSongs.sorted { $0.dateAdded > $1.dateAdded }
        session.prepareIfNeeded(songs: localSongs, favorites: favorites, favoriteSongIDs: library.favoriteSongIDs,
                                recommendationManager: recommendations)
        picks = session.recommendedSongs ?? []
        let selections = session.mixes(songs: localSongs, favoriteSongIDs: library.favoriteSongIDs,
                                       recommendationManager: recommendations)
        mixes = zip(HomePersonalMix.Kind.allCases, selections).compactMap { kind, songs in
            songs.isEmpty ? nil : HomePersonalMix(kind: kind, songs: songs)
        }
        prepareArtists()
    }

    private func prepareArtists() {
        let favoriteIDs = Set(library.favoriteSongIDs)
        let available = Set(localSongs.map(\.id))
        let playCounts = recommendations.learningData.mapValues(\.playCount)
        let scores = Dictionary(uniqueKeysWithValues: library.artistGroups.map { artist in
            (artist.id, artist.songs.reduce(0) {
                $0 + playCounts[$1.id, default: 0] + (favoriteIDs.contains($1.id) ? 6 : 0)
            })
        })
        let ranked = library.artistGroups.filter { $0.songs.contains { available.contains($0.id) } }.sorted { lhs, rhs in
            let left = scores[lhs.id, default: 0], right = scores[rhs.id, default: 0]
            return left == right ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending : left > right
        }
        artistIDs = Array(ranked.prefix(12)).map(\.id)
    }

    private func play(_ song: Song, _ queue: [Song]) {
        guard let current = library.song(withID: song.id), let url = library.getURL(for: current) else { return }
        player.lastPlaybackDirection = .fade
        player.play(song: current, url: url, queue: queue)
        player.allSongs = library.songs
        player.fillAutoNext(from: library.songs)
    }
}
