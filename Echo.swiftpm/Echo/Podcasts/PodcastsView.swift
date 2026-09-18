import SwiftUI

struct PodcastsView: View {
    @State private var query = ""
    @State private var results: [PodcastShow] = []
    @State private var loading = false
    @State private var failed = false
    @State private var retry = 0
    private let store = PodcastStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 18) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("podcasts_discover").font(.title2.bold())
                                Text("podcasts_search_hint").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 38, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(colors: [Color.accentColor.opacity(0.20), Color.accentColor.opacity(0.04)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 26)
                        )
                        PodcastLibraryLinks()
                        if !store.continueListening.isEmpty {
                            Text("podcasts_continue").font(.title2.bold())
                            ForEach(store.continueListening.prefix(2)) { PodcastEpisodeRow(episode: $0) }
                        }
                        if !store.savedShows.isEmpty {
                            Text("podcasts_saved_shows").font(.title2.bold())
                            ForEach(store.savedShows) { show in
                                PodcastShowLink(show: show)
                                    .padding(14)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
                            }
                        } else {
                            ContentUnavailableView("podcasts_discover", systemImage: "dot.radiowaves.left.and.right",
                                description: Text("podcasts_search_hint"))
                        }
                    } else if loading {
                        ProgressView("podcasts_loading").frame(maxWidth: .infinity)
                    } else if failed {
                        ContentUnavailableView {
                            Label("podcasts_search_error", systemImage: "wifi.exclamationmark")
                        } actions: { Button("podcasts_retry") { retry += 1 } }
                    } else if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        ForEach(results) { PodcastShowLink(show: $0) }
                    }
                }
                .padding()
            }
            .navigationTitle("podcasts_title")
            .searchable(text: $query, prompt: "podcasts_search")
            .task(id: "\(query):\(retry)") { await search() }
        }
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { results = []; loading = false; failed = false; return }
        loading = true
        failed = false
        do {
            try await Task.sleep(for: .milliseconds(500))
            let shows = try await PodcastCatalog.shared.search(term, country: Locale.current.region?.identifier ?? "US")
            try Task.checkCancellation()
            results = shows
            loading = false
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
            loading = false
        }
    }
}

struct PodcastLibraryLinks: View {
    var body: some View {
        VStack(spacing: 14) {
            NavigationLink { PodcastLibraryView(kind: .shows) } label: {
                Label("podcasts_saved_shows", systemImage: "dot.radiowaves.left.and.right").frame(maxWidth: .infinity, alignment: .leading)
            }
            NavigationLink { PodcastLibraryView(kind: .episodes) } label: {
                Label("podcasts_saved_episodes", systemImage: "bookmark.fill").frame(maxWidth: .infinity, alignment: .leading)
            }
            NavigationLink { PodcastLibraryView(kind: .downloads) } label: {
                Label("podcasts_downloads", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.headline)
        .buttonStyle(.plain)
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct PodcastLibraryView: View {
    enum Kind { case shows, episodes, downloads }
    let kind: Kind
    private let store = PodcastStore.shared
    private var title: LocalizedStringKey {
        switch kind {
        case .shows: "podcasts_saved_shows"
        case .episodes: "podcasts_saved_episodes"
        case .downloads: "podcasts_downloads"
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if kind == .shows {
                    if store.savedShows.isEmpty { empty }
                    ForEach(store.savedShows) { PodcastShowLink(show: $0) }
                } else {
                    let episodes = kind == .episodes ? store.savedEpisodes : store.downloadedEpisodes
                    if kind == .downloads {
                        Text("podcasts_storage \(ByteCountFormatter.string(fromByteCount: store.downloadBytes, countStyle: .file))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if episodes.isEmpty { empty }
                    ForEach(episodes) { PodcastEpisodeRow(episode: $0) }
                }
            }.padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
    private var empty: some View {
        ContentUnavailableView("podcasts_empty", systemImage: "dot.radiowaves.left.and.right", description: Text("podcasts_empty_hint"))
    }
}

struct PodcastArtwork: View {
    let url: URL?
    var size: CGFloat = 64
    @State private var cachedImage: UIImage?
    var body: some View {
        Group {
            if let image = cachedImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                    ZStack {
                        Color.accentColor.opacity(0.12)
                        Image(systemName: "dot.radiowaves.left.and.right").font(.title).foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 100 ? 28 : 14))
        .accessibilityHidden(true)
        .task(id: url) {
            cachedImage = PodcastStore.shared.artwork(for: url).flatMap { UIImage(data: $0) }
        }
    }
}

private struct PodcastShowLink: View {
    let show: PodcastShow
    @Namespace private var artworkTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationLink {
            PodcastDetailView(show: show)
                .navigationTransition(.zoom(sourceID: show.id, in: artworkTransition))
        } label: {
            HStack(spacing: 14) {
                PodcastArtwork(url: show.artworkURL)
                    .matchedTransitionSource(id: show.id, in: artworkTransition)
                VStack(alignment: .leading, spacing: 5) {
                    Text(show.title).font(.headline).foregroundStyle(.primary)
                    Text(show.author).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
    }
}

struct PodcastDetailView: View {
    let show: PodcastShow
    @State private var episodes: [PodcastEpisode] = []
    @State private var loading = true
    @State private var failed = false
    private let store = PodcastStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 16) {
                    PodcastArtwork(url: show.artworkURL, size: 210)
                    Text(show.title).font(.title.bold()).multilineTextAlignment(.center)
                    Text(show.author).foregroundStyle(.secondary)
                    if let description = store.state.showDescriptions[show.id], !description.isEmpty {
                        Text(description).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button {
                        store.toggleShow(show)
                    } label: {
                        Label(LocalizedStringKey(store.state.shows[show.id] == nil ? "podcasts_save_show" : "podcasts_remove_show"),
                              systemImage: store.state.shows[show.id] == nil ? "plus" : "checkmark")
                    }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity)
                if failed {
                    Label("podcasts_feed_error", systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                    Button("podcasts_retry") { Task { await load() } }
                }
                if loading && episodes.isEmpty { ProgressView("podcasts_loading") }
                if !loading && !failed && episodes.isEmpty {
                    ContentUnavailableView("podcasts_no_episodes", systemImage: "dot.radiowaves.left.and.right")
                }
                ForEach(episodes) { PodcastEpisodeRow(episode: $0) }
            }.padding()
        }
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: show.id) {
            episodes = store.state.cachedFeeds[show.id] ?? []
            await load()
        }
        .refreshable { await load() }
    }
    private func load() async {
        loading = true
        failed = false
        do {
            let feed = try await PodcastCatalog.shared.feed(for: show)
            try Task.checkCancellation()
            store.cache(feed.episodes, description: feed.description, for: show)
            episodes = feed.episodes
        } catch { if !Task.isCancelled { failed = true } }
        loading = false
    }
}

struct PodcastEpisodeRow: View {
    let episode: PodcastEpisode
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    private let store = PodcastStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                PodcastArtwork(url: episode.artworkURL, size: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Text(episode.title).font(.headline)
                    Text(episode.show.title).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if let date = episode.published { Text(date, format: .dateTime.day().month(.abbreviated).year()) }
                        if let duration = episode.duration {
                            Text(Duration.seconds(duration), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                PodcastEpisodeMenu(episode: episode)
            }
            if !episode.description.isEmpty {
                Text(episode.description).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
                Button(LocalizedStringKey(expanded ? "podcasts_less" : "podcasts_more")) {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9)) { expanded.toggle() }
                }.font(.caption.bold())
            }
            HStack(spacing: 12) {
                Button {
                    if player.currentSong?.podcastEpisodeID == episode.id { player.togglePlayPause() }
                    else { player.playPodcast(episode) }
                } label: {
                    Label(LocalizedStringKey(player.currentSong?.podcastEpisodeID == episode.id && player.isPlaying ? "podcasts_pause" : "podcasts_play"),
                          systemImage: player.currentSong?.podcastEpisodeID == episode.id && player.isPlaying ? "pause.fill" : "play.fill")
                }.buttonStyle(.bordered)
                if store.state.listening[episode.id]?.played == true {
                    Image(systemName: "checkmark.circle.fill").accessibilityLabel("podcasts_played")
                } else if let position = store.state.listening[episode.id]?.position, position > 0, let duration = episode.duration {
                    ProgressView(value: min(position / duration, 1)).frame(maxWidth: 80)
                        .accessibilityLabel("podcasts_progress")
                }
                if store.state.savedEpisodeIDs.contains(episode.id) {
                    Image(systemName: "bookmark.fill").accessibilityLabel("podcasts_saved")
                }
                Spacer()
                if store.state.pendingDownloads.contains(episode.id) {
                    ProgressView(value: store.progress[episode.id] ?? 0).frame(width: 48)
                        .accessibilityLabel("podcasts_downloading")
                } else if store.localURL(episode.id) != nil {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                        .accessibilityLabel("podcasts_downloaded")
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct PodcastEpisodeMenu: View {
    let episode: PodcastEpisode
    @Environment(AudioPlayerManager.self) private var player
    private let store = PodcastStore.shared
    var body: some View {
        Menu {
            Button { store.toggleSaved(episode) } label: {
                Label(LocalizedStringKey(store.state.savedEpisodeIDs.contains(episode.id) ? "podcasts_unsave_episode" : "podcasts_save_episode"), systemImage: "bookmark")
            }
            Button { player.queuePodcastNext(episode) } label: {
                Label("podcasts_play_next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button { store.togglePlayed(episode) } label: {
                Label(LocalizedStringKey(store.state.listening[episode.id]?.played == true ? "podcasts_mark_unplayed" : "podcasts_mark_played"), systemImage: "checkmark.circle")
            }
            if store.localURL(episode.id) != nil {
                Button(role: .destructive) { store.removeDownload(episode) } label: {
                    Label("podcasts_remove_download", systemImage: "trash")
                }
            } else if store.state.pendingDownloads.contains(episode.id) {
                Button(role: .destructive) { store.cancelDownload(episode) } label: {
                    Label("podcasts_cancel_download", systemImage: "xmark.circle")
                }
            } else {
                Button { store.download(episode) } label: {
                    Label("podcasts_download", systemImage: "arrow.down.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("podcasts_episode_options")
    }
}
