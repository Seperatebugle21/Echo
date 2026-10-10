import SwiftUI

/// Selection is owned by this view, so playback updates never reshuffle visible cards.
struct HomeDiscoverySection: View {
    let recommendations: [PodcastShow]
    let playSong: (Song, [Song]) -> Void
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var player
    let width: CGFloat
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
        VStack(alignment: .leading, spacing: 10) {
            if !visibleKinds.isEmpty {
                HomeSectionTitle(title: "home_discovery_title").padding(.horizontal, 20)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(visibleKinds) { kind in discoveryCard(kind).frame(width: width) }
                    }.padding(.horizontal, 20).padding(.vertical, 3)
                }.scrollIndicators(.hidden)
            }
        }
        .task(id: musicTaskID) { prepareMusic() }
        .task(id: podcastTaskID) { await preparePodcasts() }
    }

    @ViewBuilder
    private func discoveryCard(_ kind: DiscoveryKind) -> some View {
        switch kind {
        case .podcast:
            if let show = spotlight {
                NavigationLink {
                    PodcastDetailView(show: show).toolbarVisibility(.visible, for: .navigationBar)
                } label: {
                    HomeDiscoveryCard(title: "home_discovery_podcast", symbol: "dot.radiowaves.left.and.right", tint: .purple) {
                        HStack(spacing: 10) {
                            PodcastArtwork(url: show.artworkURL, size: 48)
                            Text(show.title).font(.headline).lineLimit(2)
                        }
                        Text(spotlightDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.buttonStyle(HomePressStyle())
            }
        case .artists:
            if let artist = artists.first {
                NavigationLink {
                    ArtistDetailView(artist: artist).toolbarVisibility(.visible, for: .navigationBar)
                } label: {
                    HomeDiscoveryCard(title: "home_discovery_artists", symbol: "person.2.fill", tint: .orange) {
                        HStack(spacing: 10) {
                            ArtistArtworkView(songs: artist.songs).frame(width: 48, height: 48).clipShape(.circle)
                            Text(artist.name).font(.headline).lineLimit(2)
                        }
                        Text("home_discovery_artists_detail").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.buttonStyle(HomePressStyle())
            }
        case .episode:
            if let episode = newEpisode {
                Button { player.playPodcast(episode) } label: {
                    HomeDiscoveryCard(title: "home_discovery_new_episode", symbol: "play.circle.fill", tint: .blue) {
                        HStack(spacing: 10) {
                            PodcastArtwork(url: episode.artworkURL ?? episode.show.artworkURL, size: 48)
                            Text(episode.title).font(.headline).lineLimit(2)
                        }
                        Text(episode.show.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.buttonStyle(HomePressStyle())
            }
        case .songs:
            if let song = songs.first {
                Button { playSong(song, songs) } label: {
                    HomeDiscoveryCard(title: "home_discovery_unheard", symbol: "music.note", tint: .pink) {
                        HStack(spacing: 10) {
                            SongArtworkView(song: song, cornerRadius: 10).frame(width: 48, height: 48)
                            Text(song.title).font(.headline).lineLimit(2)
                        }
                        Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.buttonStyle(HomePressStyle())
            }
        }
    }

    private func prepareMusic() {
        let validArtists = Set(library.artistGroups.map(\.id))
        artistIDs = artistIDs.filter { validArtists.contains($0) }
        let remainingArtists = library.artistGroups.filter { !artistIDs.contains($0.id) }.shuffled()
        artistIDs += remainingArtists.prefix(max(0, 3 - artistIDs.count)).map(\.id)

        let unheard = library.songs.filter {
            $0.lastPlayed == nil && $0.podcastEpisodeID == nil
                && library.getURL(for: $0).map { FileManager.default.fileExists(atPath: $0.path) } == true
        }
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

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 156
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(tint).lineLimit(1)
            content
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary).padding(16)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(.thinMaterial, in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.07)) }
    }
}
