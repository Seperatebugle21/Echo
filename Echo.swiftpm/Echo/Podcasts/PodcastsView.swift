import SwiftUI

struct PodcastsView: View {
    var resetSearchID = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var isSearchPresented = false
    @State private var searchGeneration = 0
    @FocusState private var isSearchFocused: Bool
    @State private var results: [PodcastShow] = []
    @State private var episodeResults: [PodcastEpisode] = []
    @State private var loading = false
    @State private var failed = false
    @State private var retry = 0
    @State private var recommendations = PodcastRecommendationsModel()
    @State private var isOverviewVisible = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isSearchPresented { searchBar }
                ScrollView {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        PodcastsOverview(
                            recommendations: recommendations.shows,
                            recommendationsLoading: recommendations.loading,
                            recommendationsFailed: recommendations.failed,
                            retryRecommendations: { recommendations.retry += 1 }
                        )
                        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: recommendations.shows.map(\.id))
                        .opacity(isOverviewVisible ? 1 : 0)
                        .offset(y: isOverviewVisible ? 0 : 18)
                    } else {
                        PodcastSearchResults(
                            query: query,
                            results: results,
                            episodes: episodeResults,
                            loading: loading,
                            failed: failed,
                            retry: { retry += 1 }
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .scrollIndicators(.hidden)
            }
            .echoBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !isSearchPresented {
                        Button {
                            isSearchPresented = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("podcasts_search")
                    }
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.42), value: query.isEmpty)
            .task(id: "\(searchGeneration):\(query):\(retry)") { await search() }
            .task(id: recommendations.taskID) { await recommendations.load() }
            .task {
                await Task.yield()
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.55)) {
                    isOverviewVisible = true
                }
            }
        }
        .onChange(of: resetSearchID) {
            resetSearch()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("podcasts_search", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)
                    .onSubmit { isSearchFocused = false }
                    .accessibilityLabel("podcasts_search")
                    .task {
                        // Focus after the actual text field has entered the hierarchy.
                        await Task.yield()
                        guard !Task.isCancelled, isSearchPresented else { return }
                        isSearchFocused = true
                    }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .glassEffect(.regular, in: .capsule)

            Button(action: resetSearch) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("action_cancel")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func resetSearch() {
        // Invalidate in-flight work even when the next search uses the same text.
        searchGeneration += 1
        isSearchFocused = false
        isSearchPresented = false
        query = ""
        results = []
        episodeResults = []
        loading = false
        failed = false
        retry = 0
    }

    private func search() async {
        let generation = searchGeneration
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearchPresented, !term.isEmpty else {
            results = []; episodeResults = []; loading = false; failed = false
            return
        }
        loading = true
        failed = false
        results = []
        episodeResults = []
        do {
            try await Task.sleep(for: .milliseconds(500))
            let country = Locale.current.region?.identifier ?? "US"
            async let shows = try? PodcastCatalog.shared.search(term, country: country)
            async let episodes = try? PodcastCatalog.shared.searchEpisodes(term, country: country)
            let (foundShows, foundEpisodes) = await (shows, episodes)
            try Task.checkCancellation()
            guard generation == searchGeneration, isSearchPresented,
                  term == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            results = foundShows ?? []
            episodeResults = foundEpisodes ?? []
            failed = foundShows == nil || foundEpisodes == nil
            loading = false
        } catch {
            guard !Task.isCancelled, generation == searchGeneration else { return }
            failed = true
            loading = false
        }
    }
}

private struct PodcastsOverview: View {
    let recommendations: [PodcastShow]
    let recommendationsLoading: Bool
    let recommendationsFailed: Bool
    let retryRecommendations: () -> Void
    private let store = PodcastStore.shared

    var body: some View {
        let continuing = store.continueListening
        let savedEpisodes = store.savedEpisodes

        LazyVStack(alignment: .leading, spacing: 32) {
            PodcastsHeader()

            if let episode = continuing.first {
                PodcastResumeHero(episode: episode)
            }

            if continuing.count > 1 {
                PodcastEpisodeStrip(
                    title: "podcasts_continue",
                    episodes: Array(continuing.dropFirst().prefix(8))
                )
            }

            PodcastRecommendationsSection(
                shows: recommendations,
                loading: recommendationsLoading,
                failed: recommendationsFailed,
                retry: retryRecommendations
            )

            PodcastLibraryLinks()

            if !savedEpisodes.isEmpty {
                PodcastSavedEpisodesSection(episodes: Array(savedEpisodes.prefix(4)))
            }
        }
        .padding(.bottom, 32)
    }
}

private struct PodcastsHeader: View {
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("podcasts_title")
                    .font(.largeTitle.bold())
                Text("podcasts_overview_subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            NavigationLink {
                PodcastLibraryView(kind: .downloads)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("podcasts_downloads")
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }
}

private struct PodcastResumeHero: View {
    let episode: PodcastEpisode
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let store = PodcastStore.shared

    private var isCurrentEpisode: Bool {
        player.currentSong?.podcastEpisodeID == episode.id
    }

    private var progress: Double? {
        guard let duration = episode.duration, duration > 0,
              let position = store.state.listening[episode.id]?.position else { return nil }
        return min(max(position / duration, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("podcasts_continue")
                .font(.title2.bold())

            NavigationLink {
                PodcastDetailView(show: episode.show)
            } label: {
                HStack(spacing: 16) {
                    PodcastArtwork(url: episode.artworkURL, size: 92)
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(episode.show.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(episode.title)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if let published = episode.published {
                            Text(published, format: .dateTime.day().month(.abbreviated))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if let progress {
                ProgressView(value: progress)
                    .tint(.accentColor)
                    .accessibilityLabel("podcasts_progress")
                    .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
            }

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        if isCurrentEpisode {
                            player.togglePlayPause()
                        } else {
                            player.playPodcast(episode)
                        }
                    } label: {
                        Label(
                            LocalizedStringKey(isCurrentEpisode && player.isPlaying ? "podcasts_pause" : "podcasts_resume"),
                            systemImage: isCurrentEpisode && player.isPlaying ? "pause.fill" : "play.fill"
                        )
                        .font(.headline)
                    }
                    .buttonStyle(.glassProminent)

                    PodcastEpisodeMenu(episode: episode)
                        .frame(width: 46, height: 46)
                        .glassEffect(.regular.interactive(), in: .circle)

                    Spacer()
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.20), Color.accentColor.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(.horizontal)
        .transaction { transaction in
            if reduceMotion { transaction.disablesAnimations = true }
        }
    }
}

struct PodcastLibraryLinks: View {
    var title: LocalizedStringKey = "podcasts_library"
    var horizontalPadding: CGFloat = 16
    private let store = PodcastStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.bold())
            // Three persistent cards: no lazy glass region that can lose its drawing.
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    PodcastLibraryShortcut(title: "podcasts_saved_shows", symbol: "dot.radiowaves.left.and.right",
                        color: .purple, count: store.savedShows.count, kind: .shows)
                    PodcastLibraryShortcut(title: "podcasts_saved_episodes", symbol: "bookmark.fill",
                        color: .orange, count: store.savedEpisodes.count, kind: .episodes)
                }
                GridRow {
                    PodcastLibraryShortcut(title: "podcasts_downloads", symbol: "arrow.down.circle.fill",
                        color: .blue, count: store.downloadedEpisodes.count, kind: .downloads)
                        .gridCellColumns(2)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
    }
}

private struct PodcastLibraryShortcut: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color
    let count: Int
    let kind: PodcastLibraryView.Kind

    var body: some View {
        NavigationLink {
            PodcastLibraryView(kind: kind)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.14), in: .circle)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(count, format: .number).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24).strokeBorder(color.opacity(0.22), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }
}

struct PodcastRecommendationsSection: View {
    let shows: [PodcastShow]
    let loading: Bool
    let failed: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PodcastSectionHeader(title: "podcasts_recommended")

            if loading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("podcasts_loading")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(.horizontal)
            } else if failed {
                ContentUnavailableView {
                    Label("podcasts_recommendations_error", systemImage: "wifi.exclamationmark")
                } actions: {
                    Button("podcasts_retry", action: retry)
                        .buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
            } else if shows.isEmpty {
                ContentUnavailableView(
                    "podcasts_discover",
                    systemImage: "sparkles",
                    description: Text("podcasts_search_hint")
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
            } else {
                PodcastShowCards(shows: shows)
            }
        }
    }
}

private struct PodcastShowStrip: View {
    let title: LocalizedStringKey
    let shows: [PodcastShow]
    let showAllKind: PodcastLibraryView.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PodcastSectionHeader(title: title, showAllKind: showAllKind)
            PodcastShowCards(shows: shows)
        }
    }
}

private struct PodcastShowCards: View {
    let shows: [PodcastShow]

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 15) {
                ForEach(shows) { show in
                    PodcastShowCard(show: show)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }
}

private struct PodcastShowCard: View {
    let show: PodcastShow
    @Namespace private var transition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationLink {
            PodcastDetailView(show: show)
                .navigationTransition(.zoom(sourceID: show.id, in: transition))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                PodcastArtwork(url: show.artworkURL, size: 150)
                    .matchedTransitionSource(id: show.id, in: transition)
                    .shadow(color: .black.opacity(0.18), radius: 7, y: 4)

                Text(show.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(show.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .transaction { transaction in
            if reduceMotion { transaction.disablesAnimations = true }
        }
    }
}

private struct PodcastSectionHeader: View {
    let title: LocalizedStringKey
    var showAllKind: PodcastLibraryView.Kind?

    var body: some View {
        HStack {
            Text(title)
                .font(.title2.bold())

            Spacer()

            if let showAllKind {
                NavigationLink {
                    PodcastLibraryView(kind: showAllKind)
                } label: {
                    Text("podcasts_show_all")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(.horizontal)
    }
}

private struct PodcastEpisodeStrip: View {
    let title: LocalizedStringKey
    let episodes: [PodcastEpisode]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PodcastSectionHeader(title: title)

            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 14) {
                    LazyHStack(spacing: 14) {
                        ForEach(episodes) { episode in
                            PodcastEpisodeCompactCard(episode: episode)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct PodcastEpisodeCompactCard: View {
    let episode: PodcastEpisode
    @Environment(AudioPlayerManager.self) private var player
    private let store = PodcastStore.shared

    private var isPlaying: Bool {
        player.currentSong?.podcastEpisodeID == episode.id && player.isPlaying
    }

    private var progress: Double? {
        guard let duration = episode.duration, duration > 0,
              let position = store.state.listening[episode.id]?.position else { return nil }
        return min(max(position / duration, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PodcastArtwork(url: episode.artworkURL, size: 66)

                VStack(alignment: .leading, spacing: 5) {
                    Text(episode.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(episode.show.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let progress {
                ProgressView(value: progress)
                    .tint(.accentColor)
                    .accessibilityLabel("podcasts_progress")
            }

            Button {
                if player.currentSong?.podcastEpisodeID == episode.id {
                    player.togglePlayPause()
                } else {
                    player.playPodcast(episode)
                }
            } label: {
                Label(
                    LocalizedStringKey(isPlaying ? "podcasts_pause" : "podcasts_resume"),
                    systemImage: isPlaying ? "pause.fill" : "play.fill"
                )
            }
            .buttonStyle(.glass)
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .frame(minHeight: 174, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

private struct PodcastSavedEpisodesSection: View {
    let episodes: [PodcastEpisode]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PodcastSectionHeader(title: "podcasts_saved_episodes", showAllKind: .episodes)

            GlassEffectContainer(spacing: 14) {
                LazyVStack(spacing: 14) {
                    ForEach(episodes) { episode in
                        PodcastEpisodeRow(episode: episode)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct PodcastSearchResults: View {
    private enum Scope { case all, shows, episodes }
    @State private var scope = Scope.all
    let query: String
    let results: [PodcastShow]
    let episodes: [PodcastEpisode]
    let loading: Bool
    let failed: Bool
    let retry: () -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            Picker("podcasts_search_results", selection: $scope) {
                Text("podcasts_search_all").tag(Scope.all)
                Text("podcasts_title").tag(Scope.shows)
                Text("podcasts_episodes_title").tag(Scope.episodes)
            }
            .pickerStyle(.segmented)
            if loading {
                ProgressView("podcasts_loading").frame(maxWidth: .infinity).padding(.top, 40)
            } else {
                if failed {
                    Label("podcasts_search_partial_error", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                    Button("podcasts_retry", action: retry).buttonStyle(.bordered)
                }
                if !failed && ((scope == .all && results.isEmpty && episodes.isEmpty)
                    || (scope == .shows && results.isEmpty) || (scope == .episodes && episodes.isEmpty)) {
                    ContentUnavailableView.search(text: query)
                }
                if scope != .episodes && !results.isEmpty {
                    HStack {
                        Text("podcasts_title").font(.title2.bold())
                        Spacer()
                        if scope == .all && results.count > 5 {
                            Button("podcasts_show_all") { scope = .shows }.font(.subheadline)
                        }
                    }
                    ForEach(scope == .all ? Array(results.prefix(5)) : results) { show in
                        PodcastShowLink(show: show).padding(14)
                            .background(.regularMaterial, in: .rect(cornerRadius: 22))
                    }
                }
                if scope != .shows && !episodes.isEmpty {
                    Text("podcasts_episodes_title").font(.title2.bold())
                    ForEach(episodes) { episode in
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink { PodcastDetailView(show: episode.show) } label: {
                                Label(episode.show.title, systemImage: "dot.radiowaves.left.and.right")
                                    .font(.subheadline)
                            }
                            PodcastEpisodeRow(episode: episode)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

struct PodcastLibraryView: View {
    enum Kind { case shows, episodes, downloads }
    let kind: Kind
    @State private var query = ""
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
            GlassEffectContainer(spacing: 20) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if kind == .shows {
                        let shows = store.savedShows.filter { $0.matches(query) }
                        if shows.isEmpty { empty }
                        ForEach(shows) { PodcastShowLink(show: $0) }
                    } else {
                        let episodes = (kind == .episodes ? store.savedEpisodes : store.downloadedEpisodes).filter { $0.matches(query) }
                        if kind == .downloads {
                            Text("podcasts_storage \(ByteCountFormatter.string(fromByteCount: store.downloadBytes, countStyle: .file))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if episodes.isEmpty { empty }
                        ForEach(episodes) { PodcastEpisodeRow(episode: $0) }
                    }
                }
                .padding()
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "podcasts_search")
        .echoBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private var empty: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView("podcasts_empty", systemImage: "dot.radiowaves.left.and.right", description: Text("podcasts_empty_hint"))
        } else {
            ContentUnavailableView.search(text: query)
        }
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
    @State private var query = ""
    @State private var episodes: [PodcastEpisode] = []
    @State private var loading = true
    @State private var failed = false
    private let store = PodcastStore.shared

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 24) {
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
                    let filtered = episodes.filter { $0.matches(query) }
                    if !query.isEmpty && filtered.isEmpty && !loading && !episodes.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(filtered) { PodcastEpisodeRow(episode: $0) }
                }.padding()
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "podcasts_search_episodes")
        .echoBackground()
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
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
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
