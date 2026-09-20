import SwiftUI

/// Selection is owned by this view, so playback updates never reshuffle visible cards.
struct HomeDiscoverySection: View {
    let recommendations: [PodcastShow]
    let playSong: (Song, [Song]) -> Void
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var player
    @State private var order = DiscoveryKind.allCases.shuffled()
    @State private var cardLimit = Int.random(in: 1...3)
    @State private var artistIDs: [String] = []
    @State private var songIDs: [UUID] = []
    @State private var spotlight: PodcastShow?
    @State private var spotlightDescription = ""
    @State private var newEpisodes: [PodcastEpisode] = []
    private let store = PodcastStore.shared

    private enum DiscoveryKind: String, CaseIterable, Identifiable {
        case podcast, artists, episode, songs
        var id: String { rawValue }
    }

    private var artists: [ArtistGroup] {
        artistIDs.compactMap { library.artistGroupsByID[$0] }
    }

    private var songs: [Song] {
        let byID = Dictionary(uniqueKeysWithValues: library.songs.map { ($0.id, $0) })
        return songIDs.compactMap { byID[$0] }.filter { $0.lastPlayed == nil }
    }

    private var newEpisode: PodcastEpisode? {
        newEpisodes.first { episode in
            let status = store.state.listening[episode.id]
            return status?.played != true && (status?.position ?? 0) == 0
        }
    }

    private var visibleKinds: [DiscoveryKind] {
        Array(order.filter { kind in
            switch kind {
            case .podcast: spotlight != nil && !spotlightDescription.isEmpty
            case .artists: !artists.isEmpty
            case .episode: newEpisode != nil
            case .songs: !songs.isEmpty
            }
        }.prefix(cardLimit))
    }

    // Only meaningful eligibility changes restart the task, never playback ticks.
    private var musicTaskID: [String] {
        library.songs.map { "\($0.id):\($0.lastPlayed == nil)" } + library.artistGroups.map(\.id)
    }

    private var podcastTaskID: [String] {
        recommendations.map { String($0.id) } + store.state.listening.compactMap { id, status in
            status.played || status.position > 0 ? id : nil
        }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !visibleKinds.isEmpty {
                Text("home_discovery_title")
                    .font(.title2.bold())
                ForEach(visibleKinds) { kind in
                    discoveryCard(kind)
                }
            }
        }
        .padding(.horizontal)
        .task(id: musicTaskID) { prepareMusic() }
        .task(id: podcastTaskID) { await preparePodcasts() }
    }

    @ViewBuilder
    private func discoveryCard(_ kind: DiscoveryKind) -> some View {
        switch kind {
        case .podcast:
            if let show = spotlight {
                NavigationLink {
                    PodcastDetailView(show: show)
                } label: {
                    HomeDiscoveryCard(title: "home_discovery_podcast", symbol: "dot.radiowaves.left.and.right", tint: .purple) {
                        PodcastArtwork(url: show.artworkURL, size: 124)
                        Text(show.title).font(.title2.bold())
                        Text(show.author).font(.subheadline).foregroundStyle(.secondary)
                        Text(spotlightDescription).font(.body).foregroundStyle(.secondary).lineLimit(3)
                        Label("home_discovery_explore_podcast", systemImage: "arrow.right")
                            .font(.headline).foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
        case .artists:
            HomeDiscoveryCard(title: "home_discovery_artists", symbol: "person.2.fill", tint: .orange) {
                Text("home_discovery_artists_detail").foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { artistLinks }
                    VStack(alignment: .leading, spacing: 16) { artistLinks }
                }
                NavigationLink {
                    ArtistsView()
                } label: {
                    Label("home_discovery_all_artists", systemImage: "arrow.right").font(.headline)
                }
            }
        case .episode:
            if let episode = newEpisode {
                HomeDiscoveryCard(title: "home_discovery_new_episode", symbol: "sparkles", tint: .blue) {
                    PodcastArtwork(url: episode.artworkURL ?? episode.show.artworkURL, size: 124)
                    Text(episode.show.title).font(.subheadline).foregroundStyle(.secondary)
                    Text(episode.title).font(.title2.bold()).lineLimit(3)
                    if !episode.description.isEmpty {
                        Text(episode.description).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Button {
                        player.playPodcast(episode)
                    } label: {
                        Label("home_discovery_listen_episode", systemImage: "play.fill")
                            .font(.headline).padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case .songs:
            HomeDiscoveryCard(title: "home_discovery_unheard", symbol: "music.note", tint: .pink) {
                Text("home_discovery_unheard_detail").foregroundStyle(.secondary)
                ForEach(songs) { song in
                    Button {
                        playSong(song, songs)
                    } label: {
                        HStack(spacing: 14) {
                            SongArtworkView(song: song, cornerRadius: 14)
                                .frame(width: 64, height: 64)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title).font(.headline).lineLimit(2)
                                Text(song.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("home_discovery_play_song \(song.title)"))
                }
            }
        }
    }

    private var artistLinks: some View {
        ForEach(artists) { artist in
            NavigationLink {
                ArtistDetailView(artist: artist)
            } label: {
                VStack(spacing: 8) {
                    ArtistArtworkView(songs: artist.songs)
                        .frame(width: 76, height: 76).clipShape(.circle)
                        .accessibilityHidden(true)
                    Text(artist.name).font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center).lineLimit(2)
                        .frame(width: 80)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func prepareMusic() {
        let validArtists = Set(library.artistGroups.map(\.id))
        artistIDs = artistIDs.filter { validArtists.contains($0) }
        let remainingArtists = library.artistGroups.filter { !artistIDs.contains($0.id) }.shuffled()
        artistIDs += remainingArtists.prefix(max(0, 3 - artistIDs.count)).map(\.id)

        let unheard = library.songs.filter { $0.lastPlayed == nil && $0.podcastEpisodeID == nil }
        let validSongs = Set(unheard.map(\.id))
        songIDs = songIDs.filter { validSongs.contains($0) }
        // Favor recent additions, but vary the selection between visits/sessions.
        let pool = unheard.filter { !songIDs.contains($0.id) }
            .sorted { $0.dateAdded > $1.dateAdded }.prefix(20).shuffled()
        songIDs += pool.prefix(max(0, 3 - songIDs.count)).map(\.id)
    }

    private func preparePodcasts() async {
        let state = store.state
        let listened = state.listening.filter { $0.value.played || $0.value.position > 0 }
            .sorted { $0.value.updatedAt > $1.value.updatedAt }
            .compactMap { state.episodes[$0.key] }
        var seen = Set<Int>()
        let familiarShows = Array(listened.map(\.show).filter { seen.insert($0.id).inserted }.prefix(3))
        if spotlight == nil || !recommendations.contains(where: { $0.id == spotlight?.id }) {
            spotlight = recommendations.filter { !seen.contains($0.id) }.randomElement()
            spotlightDescription = ""
        }
        if let spotlight {
            spotlightDescription = state.showDescriptions[spotlight.id] ?? ""
        }
        updateNewEpisodes(for: familiarShows)

        var toLoad = familiarShows
        if let spotlight, !toLoad.contains(where: { $0.id == spotlight.id }) { toLoad.append(spotlight) }
        // Fetch at most four feeds concurrently; one unavailable feed cannot hide other cards.
        await withTaskGroup(of: (PodcastShow, PodcastFeed?).self) { group in
            for show in toLoad {
                group.addTask { (show, try? await PodcastCatalog.shared.feed(for: show)) }
            }
            for await (show, feed) in group {
                guard !Task.isCancelled else { group.cancelAll(); return }
                guard let feed else { continue }
                store.cache(feed.episodes, description: feed.description, for: show)
                if show.id == spotlight?.id { spotlightDescription = feed.description }
                updateNewEpisodes(for: familiarShows)
            }
        }
    }

    private func updateNewEpisodes(for shows: [PodcastShow]) {
        let state = store.state
        newEpisodes = shows.compactMap { show in
            HomeDiscoverySelection.newEpisode(
                in: state.cachedFeeds[show.id] ?? [],
                knownEpisodes: Array(state.episodes.values),
                listening: state.listening
            )
        }.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
    }
}

private struct HomeDiscoveryCard<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: symbol).font(.title3.bold()).foregroundStyle(tint)
            content
        }
        .foregroundStyle(.primary)
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28).strokeBorder(tint.opacity(0.15), lineWidth: 1)
        }
    }
}
