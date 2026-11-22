import SwiftUI

struct HomeView: View {
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(HomeConfiguration.storageKey) private var storedLayout = ""
    @AppStorage(AISettingsStore.enabledKey) private var intelligenceEnabled = false
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
    @Namespace private var zoom
    /// Written while scrolling; only the small motion views read it, so Home's body is never rebuilt per frame.
    @State private var scroll = HomeScrollState()
    private let smartModel = HomeSmartSectionsModel.shared
    private let session = HomeSessionManager.shared
    private let recommendations = RecommendationManager.shared

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let layout = HomeCardLayout(width: geometry.size.width)
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header.echoReveal(0)
                        ForEach(Array(HomeConfiguration.decode(storedLayout).sections.enumerated()), id: \.element.id) { index, section in
                            homeSection(section, layout: layout)
                                .echoReveal(index + 1)
                                .echoScrollSection()
                        }
                    }
                    // The compact bar below adds 44 points on top; this keeps the header where it was.
                    .padding(.top, -36)
                    // The playing song's colors wash over the top of Home and scroll away with it.
                    .background(alignment: .top) {
                        HomeGlowMotion(scroll: scroll) { EchoAmbientGlow(height: 520) }.offset(y: -260)
                    }
                    // ContentView already reserves the live MiniPlayer and tab safe areas.
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offset in
                    scroll.offset = offset
                }
                // iOS's own soft edge blur under the compact title: a light blur, no white.
                .scrollEdgeEffectStyle(.soft, for: .top)
                .safeAreaBar(edge: .top) { HomeCompactBar(scroll: scroll) }
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
            .task(id: library.songRevision) { await smartModel.prepare(library: library); await smartModel.updateListening() }
            .task(id: library.favoriteRevision) { await smartModel.prepare(library: library) }
            .task(id: recommendations.revision) { await smartModel.updateListening() }
            .onChange(of: player.playbackErrorKey) { if let key = player.playbackErrorKey { smartModel.reportPlaybackError(key) } }
            .alert("smart_playback_error", isPresented: Binding(get: { smartModel.errorKey != nil }, set: { if !$0 { smartModel.dismissError() } })) {
                Button("action_close") { smartModel.dismissError() }
            } message: { Text(LocalizedStringKey(smartModel.errorKey ?? "smart_file_unavailable")) }
            .task(id: podcastRecommendations.taskID) { await podcastRecommendations.load() }
            .onAppear(perform: prepare)
            .onChange(of: library.songRevision) { prepare() }
            .onChange(of: library.favoriteRevision) { prepare() }
            .onChange(of: library.artistGroups.map(\.id)) { prepareArtists() }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    prepare()
                    Task { await smartModel.prepare(library: library); await smartModel.updateListening() }
                }
            }
            .sensoryFeedback(.selection, trigger: optionsFeedback)
        }
    }

    @ViewBuilder
    private func homeSection(_ section: HomeSection, layout: HomeCardLayout) -> some View {
        switch section {
        case .nowPlaying:
            HomeNowPlayingSpotlight(fallback: recent.first ?? added.first, queue: localSongs)
                .padding(.horizontal, 20)
        case .quickAccess: quickAccess(layout: layout)
        case .quickPicks:
            if !picks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HomeSectionTitle(title: "home_quick_picks").padding(.horizontal, 20)
                    songRail(picks, width: layout.song)
                }
            }
        case .forYou:
            if !mixes.isEmpty { HomeForYouSection(mixes: mixes, width: layout.mix, play: play, zoom: zoom) }
        case .recentlyPlayed:
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HomeSectionLink(title: "homeview_recent_played") { RecentPlayedView() }
                    songRail(Array(recent.prefix(12)), width: layout.song)
                }
            }
        case .artists:
            if !artistIDs.isEmpty { artistSection(width: layout.song) }
        case .recentlyAdded:
            if !added.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HomeSectionLink(title: "homeview_recent_added") { RecentAddedView() }
                    songRail(Array(added.prefix(12)), width: layout.song)
                }
            }
        case .discovery:
            HomeDiscoverySection(recommendations: podcastRecommendations.shows, playSong: play, width: layout.discovery)
        case .albums: HomeLocalAlbumSection(coverWidth: layout.song, zoom: zoom)
        case .favorites:
            if !favorites.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HomeSectionLink(title: "homeview_favorites") { FavoritesView() }
                    songRail(Array(favorites.prefix(12)), width: layout.song)
                }
            }
        case .podcasts:
            PodcastRecommendationsSection(
                shows: podcastRecommendations.shows, loading: podcastRecommendations.loading,
                failed: podcastRecommendations.failed, retry: { podcastRecommendations.retry += 1 }
            )
        case .onlineAlbums: HomeOnlineAlbumSection(coverWidth: layout.song)
        case .playlists:
            homeLibraryShortcut(title: "libraryview_playlists", symbol: "music.note.list") { PlaylistsView() }
        case .favoriteAlbums:
            homeLibraryShortcut(title: "library_favorite_albums", symbol: "heart.fill") { FavoriteAlbumsView() }
        default:
            HomeSmartSections(coverWidth: layout.song, selectedSection: section, zoom: zoom)
        }
    }

    private func homeLibraryShortcut<Destination: View>(title: LocalizedStringKey, symbol: String,
                                                       @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink { destination().toolbarVisibility(.visible, for: .navigationBar) } label: {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }.frame(minHeight: 44).smartCard()
        }.buttonStyle(HomePressStyle()).padding(.horizontal, 20)
    }

    private var header: some View {
        HStack(spacing: 8) {
            // The title grows from the left edge and the buttons from the right edge,
            // so pulling Home down never pushes anything off screen.
            HomeHeaderMotion(scroll: scroll, anchor: .leading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("homeview_title").font(.largeTitle.weight(.heavy))
                    Text("home_tagline").font(.system(size: 9, weight: .medium)).tracking(3)
                        .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 4)
            HomeHeaderMotion(scroll: scroll, anchor: .trailing) {
                HStack(spacing: 8) {
                    if intelligenceEnabled {
                        headerButton("sparkles", label: "ai_title") { AppRouter.shared.showIntelligence = true }
                    }
                    headerButton("magnifyingglass", label: "tab_search") { showSearch = true }
                    headerButton("gearshape", label: "tab_settings") { showSettings = true }
                }
            }
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
                    NavigationLink { FavoritesView().toolbarVisibility(.visible, for: .navigationBar).echoZoomDestination("home-fav", in: zoom) } label: {
                        HomeQuickAccessCard(title: "libraryview_favorites", symbol: "heart.fill", count: favorites.count,
                                            playlists: false, song: favorites.first, width: layout.access, accent: true)
                            .echoZoomSource("home-fav", in: zoom)
                    }
                    NavigationLink { RecentPlayedView().toolbarVisibility(.visible, for: .navigationBar).echoZoomDestination("home-recent", in: zoom) } label: {
                        HomeQuickAccessCard(title: "home_recent", symbol: "clock", count: recent.count,
                                            playlists: false, song: recent.first, width: layout.access)
                            .echoZoomSource("home-recent", in: zoom)
                    }
                    NavigationLink { SongsView().toolbarVisibility(.visible, for: .navigationBar).echoZoomDestination("home-songs", in: zoom) } label: {
                        HomeQuickAccessCard(title: "tab_songs", symbol: "music.note", count: localSongs.count,
                                            playlists: false, song: added.first, width: layout.access)
                            .echoZoomSource("home-songs", in: zoom)
                    }
                    NavigationLink { PlaylistsView().toolbarVisibility(.visible, for: .navigationBar).echoZoomDestination("home-playlists", in: zoom) } label: {
                        HomeQuickAccessCard(title: "libraryview_playlists", symbol: "music.note.list", count: library.playlists.count,
                                            playlists: true, song: playlistArtworkSong, width: layout.access)
                            .echoZoomSource("home-playlists", in: zoom)
                    }
                }.buttonStyle(HomePressStyle())
                    .scrollTargetLayout()
                    .padding(.vertical, 8)
            }.scrollIndicators(.hidden)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
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
                            NavigationLink {
                                ArtistDetailView(artist: artist).toolbarVisibility(.visible, for: .navigationBar)
                                    .echoZoomDestination("home-artist-" + id, in: zoom)
                            } label: {
                                VStack(spacing: 7) {
                                    ArtistArtworkView(songs: artist.songs).frame(width: width, height: width)
                                        .clipShape(.circle)
                                        .echoZoomSource("home-artist-" + id, in: zoom)
                                        .homeCoverShadow().accessibilityHidden(true)
                                    Text(artist.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }.frame(width: width)
                            }.buttonStyle(HomePressStyle())
                                .echoRailItem()
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 8)
            }.scrollIndicators(.hidden)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
        }
    }

    private func prepare() {
        // getURL builds a path; check the file to exclude missing/download-in-progress tracks.
        // Files only need checking once: a play date or other metadata change would
        // otherwise check every song on disk while a song-change animation runs.
        localSongs = library.songs.filter {
            $0.podcastEpisodeID == nil && HomeFileCheck.exists($0, library: library)
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

@Observable
final class HomeScrollState {
    var offset: CGFloat = 0
}

/// The title stretches when Home is pulled down, and drifts and fades as it scrolls away.
private struct HomeHeaderMotion<Content: View>: View {
    let scroll: HomeScrollState
    let anchor: UnitPoint
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let y = reduceMotion ? 0 : scroll.offset
        content
            .scaleEffect(y < 0 ? 1 + min(0.14, -y / 500) : 1, anchor: anchor)
            .offset(y: y > 0 ? y * 0.3 : 0)
            .opacity(y > 0 ? max(0, 1 - y / 140) : 1)
    }
}

/// The song's color wash moves slower than the page and stretches on overscroll.
private struct HomeGlowMotion<Content: View>: View {
    let scroll: HomeScrollState
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let y = reduceMotion ? 0 : scroll.offset
        content
            .scaleEffect(y < 0 ? 1 + min(0.5, -y / 320) : 1, anchor: .top)
            .offset(y: y > 0 ? y * 0.45 : y)
    }
}

/// A compact title on frosted glass fades in once the large title has scrolled away.
private struct HomeCompactBar: View {
    let scroll: HomeScrollState

    var body: some View {
        let progress = min(1, max(0, (scroll.offset - 70) / 50))
        Text("homeview_title")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .offset(y: 8 * (1 - progress))
            .opacity(progress)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Remembers which song files exist; only songs not seen before touch the disk.
@MainActor
enum HomeFileCheck {
    private static var present = Set<String>()

    static func exists(_ song: Song, library: MusicLibraryManager) -> Bool {
        let key = "\(song.id)|\(song.fileName)"
        if present.contains(key) { return true }
        guard let url = library.getURL(for: song), FileManager.default.fileExists(atPath: url.path) else { return false }
        present.insert(key)
        return true
    }
}
