import SwiftUI

struct SearchView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(AudioPlayerManager.self)
    private var audioPlayer

    @ScaledMetric(relativeTo: .body) private var historyRowHeight: CGFloat = 52
    @State private var searchText = ""
    @State private var showAllSongs = false
    @State private var showSettings = false
    @FocusState private var searchFocused: Bool
    @Namespace private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Built in the background whenever the library changes.
    @State private var searchIndex = LibrarySearchIndex.empty

    /// Results of the last finished search (computed in the background).
    @State private var results = LibrarySearchResults.empty

    // MARK: - Search history

    @AppStorage("echo_search_recent_queries_v1")
    private var recentQueriesData: Data = Data()

    @AppStorage("echo_search_recent_song_ids_v1")
    private var recentSongIDsData: Data = Data()


    // MARK: - Recent searches

    private var recentQueries: [String] {

        guard !recentQueriesData.isEmpty else {
            return []
        }

        return (
            try? JSONDecoder().decode(
                [String].self,
                from: recentQueriesData
            )
        ) ?? []
    }


    // MARK: - Recently opened from Search

    private var recentSearchSongIDs: [UUID] {

        guard !recentSongIDsData.isEmpty else {
            return []
        }

        return (
            try? JSONDecoder().decode(
                [UUID].self,
                from: recentSongIDsData
            )
        ) ?? []
    }

    private var recentlySearchedSongs: [Song] {

        recentSearchSongIDs.compactMap {
            library.song(withID: $0)
        }
    }


    // MARK: - Query

    private var trimmedQuery: String {
        searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }


    // MARK: - Results (cached, see refreshResults)

    private var matchingSongs: [Song] {
        results.songs
    }

    private var displayedSongs: [Song] {

        if showAllSongs {
            return results.songs
        }

        return Array(
            results.songs.prefix(10)
        )
    }

    private var matchingArtists: [ArtistGroup] {
        results.artists
    }

    private var matchingAlbums: [AlbumGroup] {
        results.albums
    }

    private var matchingPlaylists: [Playlist] {
        results.playlists
    }


    // MARK: - Idle sources

    private var allArtists: [ArtistGroup] {
        library.artistGroups
    }

    private var allAlbums: [AlbumGroup] {
        searchIndex.albums
    }


    // MARK: - Background search

    /// Rebuilds the search index off the main thread.
    private func rebuildIndex() async {

        let songs = library.songs
        let revision = library.songRevision

        let index =
            await Task.detached(
                priority: .userInitiated
            ) {
                LibrarySearchIndex(
                    songs: songs,
                    revision: revision
                )
            }
            .value

        guard !Task.isCancelled else {
            return
        }

        searchIndex = index

        await refreshResults(debounce: false)
    }


    /// Searches off the main thread so typing never waits for filtering.
    /// Called through `.task(id: searchText)`, which cancels the previous
    /// search as soon as another character is typed.
    private func refreshResults(
        debounce: Bool
    ) async {

        let query = trimmedQuery

        guard !query.isEmpty else {
            results = .empty
            return
        }

        if debounce {

            try? await Task.sleep(
                for: .milliseconds(120)
            )

            guard !Task.isCancelled else {
                return
            }
        }

        let index = searchIndex
        let artists = library.artistGroups
        let playlists = library.playlists.map {
            (playlist: $0, name: $0.displayName())
        }

        let task =
            Task.detached(
                priority: .userInitiated
            ) {
                LibrarySearch.search(
                    query,
                    in: index,
                    artists: artists,
                    playlists: playlists
                )
            }

        let found =
            await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }

        guard
            !Task.isCancelled,
            query == trimmedQuery
        else {
            return
        }

        results = found
    }


    // MARK: - Body

    var body: some View {

        NavigationStack {

            ScrollView {

                LazyVStack(alignment: .leading, spacing: 28) {

                    if !searchFocused {
                        header
                            .transition(AnyTransition.opacity.combined(with: AnyTransition.offset(y: -16)))
                    }

                    searchBar

                    Group {
                        if trimmedQuery.isEmpty {
                            idleContent
                        } else if results.query == trimmedQuery, results.isEmpty {
                            noResultsView
                        } else {
                            searchResults
                        }
                    }
                    .transition(AnyTransition.opacity.combined(with: AnyTransition.offset(y: 14)))
                }
                .padding(.top, 6)
                .padding(.bottom, 120)
                .background(alignment: .top) {
                    EchoAmbientGlow(height: 420).offset(y: -240)
                }
                .animation(motion, value: trimmedQuery.isEmpty)
                .animation(motion, value: searchFocused)
                .animation(motion, value: results.query)
            }
            .scrollDismissesKeyboard(.interactively)
            .echoBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onChange(of: searchText) { showAllSongs = false }
            .task(id: library.songRevision) { await rebuildIndex() }
            .task(id: searchText) { await refreshResults(debounce: true) }
        }
    }

    private var motion: Animation { EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion) }


    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("searchview_title")
                .font(.largeTitle.weight(.heavy))
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(HomePressStyle())
            .accessibilityLabel("tab_settings")
        }
        .padding(.horizontal, 20)
    }


    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(searchFocused ? Color.accentColor : .secondary)
                    .symbolEffect(.bounce, value: searchFocused)

                TextField("searchview_placeholder", text: $searchText)
                    .font(.body.weight(.medium))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { saveCurrentSearch() }

                if !searchText.isEmpty {
                    Button {
                        withAnimation(motion) { searchText = "" }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(.circle)
                    }
                    .buttonStyle(EchoPlayerControlStyle(halo: false))
                    .transition(AnyTransition.scale(scale: 0.4).combined(with: AnyTransition.opacity))
                    .accessibilityLabel("searchview_clear_recent")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(height: 52)
            .glassEffect(.regular.interactive(), in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(Color.accentColor.opacity(searchFocused ? 0.55 : 0), lineWidth: 1.5)
            }

            if searchFocused {
                Button("action_cancel") {
                    searchText = ""
                    searchFocused = false
                }
                .font(.body.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
                .transition(AnyTransition.move(edge: .trailing).combined(with: AnyTransition.opacity))
            }
        }
        .padding(.horizontal, 20)
        .animation(motion, value: searchText.isEmpty)
    }


    // MARK: - Idle Content

    @ViewBuilder
    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 30) {
            let queries = recentQueries
            if !queries.isEmpty {
                recentSearchesSection(queries).echoReveal(0)
            }
            let recentSongs = recentlySearchedSongs
            if !recentSongs.isEmpty {
                recentlySearchedSection(recentSongs).echoReveal(1).echoScrollSection()
            }
            if !allArtists.isEmpty {
                artistRail(title: "searchview_your_artists", artists: Array(allArtists.prefix(12)), zoomPrefix: "idle")
                    .echoReveal(2).echoScrollSection()
            }
            if !allAlbums.isEmpty {
                albumRail(title: "searchview_browse_albums", albums: Array(allAlbums.prefix(12)), zoomPrefix: "idle")
                    .echoReveal(3).echoScrollSection()
            }
            if !library.playlists.isEmpty {
                playlistRail(title: "searchview_browse_playlists", playlists: Array(library.playlists.prefix(12)))
                    .echoReveal(4).echoScrollSection()
            }
            if library.songs.isEmpty {
                ContentUnavailableView(
                    "searchview_empty_library_title",
                    systemImage: "music.note",
                    description: Text("searchview_empty_library_description")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 45)
            }
        }
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.title2.bold()).padding(.horizontal, 20).accessibilityAddTraits(.isHeader)
    }


    // MARK: - Recent Searches (chips)

    private func recentSearchesSection(_ queries: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("searchview_recent_searches").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("searchview_clear_recent", action: clearRecentSearches)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            EchoFlowLayout(spacing: 8) {
                ForEach(queries, id: \.self) { query in
                    HStack(spacing: 6) {
                        Button {
                            searchText = query
                            searchFocused = false
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(verbatim: query)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .padding(.leading, 14)
                            .frame(height: 40)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)

                        Button { removeRecentQuery(query) } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 40)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("searchview_delete_history")
                    }
                    .padding(.trailing, 4)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .transition(AnyTransition.scale(scale: 0.6).combined(with: AnyTransition.opacity))
                    .accessibilityElement(children: .contain)
                }
            }
            .padding(.horizontal, 20)
            .animation(motion, value: queries)
        }
    }

    private func removeRecentQuery(_ query: String) {
        guard let data = try? JSONEncoder().encode(recentQueries.filter { $0 != query }) else { return }
        withAnimation(motion) { recentQueriesData = data }
    }


    // MARK: - Recently searched songs

    private func recentlySearchedSection(_ songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("searchview_recently_searched")
            rail {
                ForEach(songs.prefix(6)) { song in
                    Button {
                        rememberRecentSong(song)
                        play(song)
                    } label: {
                        coverTile(title: song.title, subtitle: song.artist) {
                            SongArtworkView(song: song, cornerRadius: 16)
                        }
                    }
                    .buttonStyle(HomePressStyle())
                    .echoRailItem()
                }
            }
        }
    }


    // MARK: - Rails

    private func rail<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) { content() }
                .scrollTargetLayout()
                .padding(.vertical, 6)
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollClipDisabled()
        .scrollTargetBehavior(.viewAligned)
    }

    private func coverTile<Artwork: View>(title: String, subtitle: String, size: CGFloat = 146,
                                          zoomID: String? = nil,
                                          @ViewBuilder artwork: () -> Artwork) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            artwork()
                .frame(width: size, height: size)
                .echoZoomSource(zoomID ?? "", in: zoomID == nil ? nil : zoom)
                .homeCoverShadow()
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: size, alignment: .leading)
        .contentShape(.rect)
    }

    private func artistRail(title: LocalizedStringKey, artists: [ArtistGroup], zoomPrefix: String,
                            showsCount: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title)
            rail {
                ForEach(artists) { artist in
                    let zoomID = "search-\(zoomPrefix)-artist-\(artist.id)"
                    NavigationLink {
                        ArtistDetailView(artist: artist).echoZoomDestination(zoomID, in: zoom)
                    } label: {
                        VStack(spacing: 7) {
                            ArtistArtworkView(songs: artist.songs)
                                .frame(width: 104, height: 104)
                                .clipShape(Circle())
                                .echoZoomSource(zoomID, in: zoom)
                                .homeCoverShadow()
                            Text(artist.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if showsCount {
                                Text(String(format: String(localized: "searchview_songs_count"), artist.songs.count))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(width: 104)
                    }
                    .buttonStyle(HomePressStyle())
                    .simultaneousGesture(TapGesture().onEnded { saveCurrentSearch() })
                    .echoRailItem()
                }
            }
        }
    }

    private func albumRail(title: LocalizedStringKey, albums: [AlbumGroup], zoomPrefix: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title)
            rail {
                ForEach(albums) { album in
                    let zoomID = "search-\(zoomPrefix)-album-\(album.id)"
                    NavigationLink {
                        AlbumDetailView(album: album).echoZoomDestination(zoomID, in: zoom)
                    } label: {
                        coverTile(title: album.name, subtitle: album.artist, zoomID: zoomID) {
                            albumArtwork(album, size: 146)
                        }
                    }
                    .buttonStyle(HomePressStyle())
                    .albumFavoriteActions(FavoriteAlbum(album: album))
                    .simultaneousGesture(TapGesture().onEnded { saveCurrentSearch() })
                    .echoRailItem()
                }
            }
        }
    }

    private func playlistRail(title: LocalizedStringKey, playlists: [Playlist]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title)
            rail {
                ForEach(playlists) { playlist in
                    let zoomID = "search-playlist-\(playlist.id)"
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist).echoZoomDestination(zoomID, in: zoom)
                    } label: {
                        coverTile(title: playlist.displayName(),
                                  subtitle: String(format: String(localized: "searchview_songs_count"),
                                                   library.songCount(in: playlist)),
                                  zoomID: zoomID) {
                            PlaylistSearchArtwork(playlist: playlist)
                        }
                    }
                    .buttonStyle(HomePressStyle())
                    .simultaneousGesture(TapGesture().onEnded { saveCurrentSearch() })
                    .echoRailItem()
                }
            }
        }
    }


    // MARK: - No Results

    private var noResultsView: some View {
        VStack(spacing: 13) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolEffect(.wiggle, options: .nonRepeating, value: results.query)
            Text("searchview_no_results").font(.title3.bold())
            Text(String(format: String(localized: "searchview_no_results_for_query"), searchText))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.top, 55)
    }


    // MARK: - Search Results

    @ViewBuilder
    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 30) {
            if let top = matchingSongs.first {
                topResult(top).echoReveal(0)
            }
            if matchingSongs.count > 1 {
                songsResultSection.echoReveal(1)
            }
            if !matchingArtists.isEmpty {
                artistRail(title: "searchview_searched_artists", artists: matchingArtists,
                           zoomPrefix: "result", showsCount: true)
                    .echoReveal(2).echoScrollSection()
            }
            if !matchingAlbums.isEmpty {
                albumRail(title: "searchview_searched_albums", albums: matchingAlbums, zoomPrefix: "result")
                    .echoReveal(3).echoScrollSection()
            }
            if !matchingPlaylists.isEmpty {
                playlistRail(title: "searchview_searched_playlists", playlists: matchingPlaylists)
                    .echoReveal(4).echoScrollSection()
            }
        }
    }

    // MARK: Top result

    private func topResult(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("searchview_top_result")
            Button {
                saveCurrentSearch()
                rememberRecentSong(song)
                play(song)
            } label: {
                HStack(spacing: 16) {
                    SongArtworkView(song: song, cornerRadius: 14)
                        .frame(width: 92, height: 92)
                        .echoArtworkGlow(radius: 16, opacity: 0.6)
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.title).font(.title3.bold()).foregroundStyle(.primary).lineLimit(2)
                        Text(song.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: audioPlayer.currentSong?.id == song.id && audioPlayer.isPlaying ? "waveform" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: audioPlayer.currentSong?.id == song.id && audioPlayer.isPlaying)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 46, height: 46)
                        .background(Color.accentColor, in: .circle)
                }
                .padding(14)
                .background {
                    ZStack {
                        Rectangle().fill(.thinMaterial)
                        SongArtworkView(song: song, cornerRadius: 0)
                            .blur(radius: 40)
                            .opacity(0.35)
                    }
                }
                .clipShape(.rect(cornerRadius: 22, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.primary.opacity(0.06)) }
                .contentShape(.rect(cornerRadius: 22))
            }
            .buttonStyle(HomePressStyle())
            .padding(.horizontal, 20)
            .id(song.id)
            .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.96)))
        }
        .animation(motion, value: song.id)
    }

    // MARK: Songs Results

    private var songsResultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("searchview_searched_songs")

            let songs = Array(displayedSongs.dropFirst())
            let lastSongID = songs.last?.id

            VStack(spacing: 0) {
                ForEach(songs) { song in
                    Button {
                        saveCurrentSearch()
                        rememberRecentSong(song)
                        play(song)
                    } label: {
                        LibrarySongRow(song: song)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HomePressStyle())
                    .transition(AnyTransition.opacity.combined(with: AnyTransition.offset(y: 8)))

                    if song.id != lastSongID {
                        Divider().padding(.leading, 62)
                    }
                }

                if matchingSongs.count > 10, !showAllSongs {
                    Divider().padding(.leading, 62)
                    Button {
                        withAnimation(motion) { showAllSongs = true }
                    } label: {
                        HStack {
                            Text(String(format: String(localized: "searchview_show_all_results"), matchingSongs.count))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.down").font(.caption.bold())
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.vertical, 13)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(0.06)) }
            .padding(.horizontal, 20)
            .animation(motion, value: songs.map(\.id))
        }
    }


    // MARK: - Album Artwork

    @ViewBuilder
    private func albumArtwork(
        _ album: AlbumGroup,
        size: CGFloat
    ) -> some View {

        if let song = album.songs.first {

            SongArtworkView(
                song: song,
                cornerRadius: 16
            )
            .frame(
                width: size,
                height: size
            )

        } else {

            ZStack {

                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .fill(.thinMaterial)

                Image(
                    systemName:
                        "square.stack"
                )
                .font(.title)
                .foregroundStyle(
                    .secondary
                )
            }
            .frame(
                width: size,
                height: size
            )
        }
    }


    // MARK: - Search History

    private func saveCurrentSearch() {

        let cleaned =
            searchText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !cleaned.isEmpty else {
            return
        }

        var searches = recentQueries

        searches.removeAll {

            $0.localizedCaseInsensitiveCompare(
                cleaned
            )
            == .orderedSame
        }

        searches.insert(
            cleaned,
            at: 0
        )

        searches =
            Array(
                searches.prefix(4)
            )

        if let data =
            try? JSONEncoder().encode(
                searches
            )
        {

            recentQueriesData = data
        }
    }

    private func clearRecentSearches() {

        withAnimation(
            .easeInOut(duration: 0.2)
        ) {

            recentQueriesData = Data()
        }
    }


    // MARK: - Recently Searched Songs

    private func rememberRecentSong(
        _ song: Song
    ) {

        var ids = recentSearchSongIDs

        ids.removeAll {
            $0 == song.id
        }

        ids.insert(
            song.id,
            at: 0
        )

        ids =
            Array(
                ids.prefix(6)
            )

        if let data =
            try? JSONEncoder().encode(
                ids
            )
        {

            recentSongIDsData = data
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
        PlaylistCoverArtwork(data: playlist.imageData, builtin: playlist.builtinCoverID, pixels: 256)
            .clipShape(.rect(cornerRadius: 16))
    }
}


/// Wraps chips onto as many rows as they need.
struct EchoFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: proposal.width ?? width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > 0 && x + size.width > bounds.width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
