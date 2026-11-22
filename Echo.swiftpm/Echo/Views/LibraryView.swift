import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @State private var showImporter = false
    @State private var showAddActions = false
    @State private var pendingAdd: LibraryAddSheet.Action?
    @State private var showCreate = false
    @State private var showSmart = false
    @State private var isImporting = false
    @State private var importProgress = 0
    @State private var importTotal = 0
    @Namespace private var zoom

    @Environment(MusicLibraryManager.self)
    private var library

    private var artists: [ArtistGroup] {
        library.artistGroups
    }

    private var albumGroups: [AlbumGroup] {
        LibraryAlbums.groups(from: library.songs)
    }

    private var recentlyAddedSongs: [Song] {

        Array(
            library.songs
                .sorted {
                    $0.dateAdded > $1.dateAdded
                }
                .prefix(4)
        )
    }

    private var recentlyPlayedSongs: [Song] {

        Array(
            library.songs
                .filter {
                    $0.lastPlayed != nil
                }
                .sorted {
                    ($0.lastPlayed ?? .distantPast)
                    >
                    ($1.lastPlayed ?? .distantPast)
                }
                .prefix(4)
        )
    }

    private var recentAddedSubtitle: String {

        guard
            let first =
                recentlyAddedSongs.first
        else {
            return String(
                                    localized: "libraryview_no_songs"
                                )
        }

        return first.title
    }

    private var recentPlayedSubtitle: String {

        guard
            let first =
                recentlyPlayedSongs.first
        else {
            return String(
                                    localized: "libraryview_nothing_played"
                                )
        }

        return first.title
    }

    var body: some View {

        NavigationStack {

            ScrollView {

                LazyVStack(
                    alignment: .leading,
                    spacing: 34
                ) {


                    VStack(
                        alignment: .leading,
                        spacing: 14
                    ) {

                        Text(
                            "libraryview_your_library"
                        )
                        .font(.title2.bold())
                        .padding(.horizontal)

                        ScrollView(
                            .horizontal,
                            showsIndicators: false
                        ) {

                            LazyHStack(
                                spacing: 16
                            ) {

                                NavigationLink {

                                    SongsView()
                                        .echoZoomDestination("lib-songs", in: zoom)

                                } label: {

                                    LibraryFeatureCard(
                                        title: "libraryview_songs",
                                        subtitle:
                                            String(
                                                format:
                                                    String(
                                    localized: "libraryview_songs_count"
                                ),
                                                library.songs.count
                                            )
                                    ) {

                                        SongsMosaicArtwork(
                                            songs:
                                                library.songs
                                        )
                                    }
                                    .echoZoomSource("lib-songs", in: zoom)
                                }
                                .buttonStyle(HomePressStyle())
                                .echoRailItem()

                                NavigationLink {

                                    PlaylistsView()
                                        .echoZoomDestination("lib-playlists", in: zoom)

                                } label: {

                                    LibraryFeatureCard(
                                        title: "libraryview_playlists",
                                        subtitle:
                                            String(
                                                format:
                                                    String(
                                    localized: "libraryview_playlists_count"
                                ),
                                                library.playlists.count
                                            )
                                    ) {

                                        PlaylistStackArtwork(
                                            playlists:
                                                library.playlists
                                        )
                                    }
                                    .echoZoomSource("lib-playlists", in: zoom)
                                }
                                .buttonStyle(HomePressStyle())
                                .echoRailItem()

                                NavigationLink {

                                    FavoritesView()
                                        .echoZoomDestination("lib-favorites", in: zoom)

                                } label: {

                                    LibraryFeatureCard(
                                        title: "libraryview_favorites",
                                        subtitle:
                                            String(
                                                format:
                                                    String(
                                    localized: "libraryview_songs_count"
                                ),
                                                library.favoriteSongs.count
                                            )
                                    ) {

                                        FavoritesFeatureArtwork(
                                            songs:
                                                library.favoriteSongs
                                        )
                                    }
                                    .echoZoomSource("lib-favorites", in: zoom)
                                }
                                .buttonStyle(HomePressStyle())
                                .echoRailItem()

                                NavigationLink { FavoriteAlbumsView().echoZoomDestination("lib-favorite-albums", in: zoom) } label: {
                                    LibraryFeatureCard(title: "library_favorite_albums",
                                        subtitle: String(format: String(localized: "favorite_albums_count"), FavoriteAlbumsStore.shared.albums.count)) {
                                        FavoriteAlbumsFeatureArtwork(albums: FavoriteAlbumsStore.shared.albums)
                                    }
                                    .echoZoomSource("lib-favorite-albums", in: zoom)
                                }.buttonStyle(HomePressStyle())
                                .echoRailItem()
                            }
                            .scrollTargetLayout()
                            .padding(.vertical, 6)
                        }
                        .contentMargins(.horizontal, 16, for: .scrollContent)
                        .scrollClipDisabled()
                        .scrollTargetBehavior(.viewAligned)
                    }
                    .echoReveal(0)

                    VStack(
                        alignment: .leading,
                        spacing: 14
                    ) {

                        Text(
                            "libraryview_collections"
                        )
                        .font(.title2.bold())
                        .padding(.horizontal)

                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .flexible(),
                                    spacing: 12
                                ),
                                GridItem(
                                    .flexible(),
                                    spacing: 12
                                )
                            ],
                            spacing: 12
                        ) {

                            NavigationLink {

                                ArtistsView()
                                    .echoZoomDestination("lib-artists", in: zoom)

                            } label: {

                                CollectionCard(
                                    title: "libraryview_artists",
                                    subtitle:
                                        String(
                                            format:
                                                String(
                                    localized: "libraryview_artists_count"
                                ),
                                            artists.count
                                        ),
                                    symbol:
                                        "person.2.fill"
                                ) {

                                    ArtistCollectionArtwork(
                                        artists: artists
                                    )
                                }
                                .echoZoomSource("lib-artists", in: zoom)
                            }
                            .buttonStyle(HomePressStyle())

                            NavigationLink {

                                AlbumsView()
                                    .echoZoomDestination("lib-albums", in: zoom)

                            } label: {

                                CollectionCard(
                                    title: "libraryview_albums",
                                    subtitle:
                                        String(
                                            format:
                                                String(
                                    localized: "libraryview_albums_count"
                                ),
                                            albumGroups.count
                                        ),
                                    symbol:
                                        "square.stack.fill"
                                ) {

                                    AlbumCollectionArtwork(
                                        albums:
                                            albumGroups
                                    )
                                }
                                .echoZoomSource("lib-albums", in: zoom)
                            }
                            .buttonStyle(HomePressStyle())

                            NavigationLink {

                                RecentAddedView()
                                    .echoZoomDestination("lib-added", in: zoom)

                            } label: {

                                CollectionCard(
                                    title: "libraryview_recent_added",
                                    subtitle:
                                        recentAddedSubtitle,
                                    symbol: "plus"
                                ) {

                                    CoverStackArtwork(
                                        songs:
                                            recentlyAddedSongs
                                    )
                                }
                                .echoZoomSource("lib-added", in: zoom)
                            }
                            .buttonStyle(HomePressStyle())

                            NavigationLink {

                                RecentPlayedView()
                                    .echoZoomDestination("lib-played", in: zoom)

                            } label: {

                                CollectionCard(
                                    title: "libraryview_recent_played",
                                    subtitle:
                                        recentPlayedSubtitle,
                                    symbol:
                                        "clock.arrow.circlepath"
                                ) {

                                    CoverStackArtwork(
                                        songs:
                                            recentlyPlayedSongs
                                    )
                                }
                                .echoZoomSource("lib-played", in: zoom)
                            }
                            .buttonStyle(HomePressStyle())
                        }
                        .padding(.horizontal)
                    }
                    .echoReveal(1)
                    .echoScrollSection()
                    PodcastLibraryFolders()
                        .padding(.horizontal)
                        .echoReveal(2)
                        .echoScrollSection()
                }
                .padding(.top, 8)
                .background(alignment: .top) {
                    EchoAmbientGlow(height: 460).offset(y: -260)
                }
                .padding(.bottom, 120)
            }

            .echoBackground()

            .navigationTitle(
                "libraryview_title"
            )
            .navigationBarTitleDisplayMode(
                .large
            )
            .toolbar {
                ToolbarItem(placement: .largeTitle) {
                    Group {
                    HStack(alignment: .center) {
                        Text("libraryview_title")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 16)
                        Button {
                            showAddActions = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .disabled(isImporting)
                        .accessibilityLabel("library_add_title")
                    }
                    .frame(maxWidth: .infinity)
                    }.tint(.primary)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $showAddActions, onDismiss: finishAddAction) {
                LibraryAddSheet { action in pendingAdd = action; showAddActions = false }
            }
            .sheet(isPresented: $showCreate) { CreatePlaylistView() }
            .sheet(isPresented: $showSmart) { SmartPlaylistEditor() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let files):
                    guard !files.isEmpty else { return }
                    isImporting = true
                    importProgress = 0
                    importTotal = files.count
                    Task { @MainActor in
                        defer { isImporting = false }
                        for file in files {
                            await importFile(file)
                            importProgress += 1
                        }
                    }
                case .failure(let error):
                    print("Import error:", error.localizedDescription)
                }
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView(value: Double(importProgress), total: Double(importTotal))
                                .progressViewStyle(.circular)
                                .scaleEffect(1.5)
                            Text("songsview_importing").font(.headline)
                            Text("\(importProgress) / \(importTotal)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: .rect(cornerRadius: 16))
                        .shadow(radius: 10)
                    }
                }
            }
            .alert("alert_duplicate_title", isPresented: Binding(
                // Do not compete with SongsView's alert when navigating there.
                get: { isImporting && library.showDuplicateAlert },
                set: { if isImporting { library.showDuplicateAlert = $0 } }
            )) {
                Button("action_skip") { library.resolveDuplicate(choice: .skip, applyToAll: false) }
                Button("action_replace", role: .destructive) { library.resolveDuplicate(choice: .replace, applyToAll: false) }
                Button("action_skip_all") { library.resolveDuplicate(choice: .skip, applyToAll: true) }
                Button("action_replace_all", role: .destructive) { library.resolveDuplicate(choice: .replace, applyToAll: true) }
                Button("action_cancel", role: .cancel) {}
            } message: {
                Text("alert_duplicate_message \(library.duplicateSongName)")
            }
        }
    }

    private func finishAddAction() {
        guard let action = pendingAdd else { return }
        pendingAdd = nil
        switch action {
        case .playlist: showCreate = true
        case .smart: showSmart = true
        case .files: showImporter = true
        case .fetch: AppRouter.shared.open(.fetch)
        }
    }

    @MainActor private func importFile(_ file: URL) async {
        let hasAccess = file.startAccessingSecurityScopedResource()
        defer { if hasAccess { file.stopAccessingSecurityScopedResource() } }
        library.importSong(from: file)
        // Keep this file accessible until the duplicate decision is finished,
        // and do not overwrite the pending duplicate with the next selected file.
        while library.showDuplicateAlert {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

struct LibraryFeatureCard<
    Artwork: View
>: View {

    let title: LocalizedStringKey
    let subtitle: String

    @ViewBuilder
    let artwork: Artwork

    init(
        title: LocalizedStringKey,
        subtitle: String,
        @ViewBuilder artwork:
            () -> Artwork
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork()
    }

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            artwork
                .frame(
                    width: 168,
                    height: 168
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 22,
                        style: .continuous
                    )
                )
                .homeCoverShadow()

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(
            width: 168,
            alignment: .leading
        )
    }
}

struct SongsMosaicArtwork: View {

    let songs: [Song]

    private var displayedSongs: [Song] {
        Array(
            songs.prefix(4)
        )
    }

    var body: some View {

        GeometryReader { geometry in

            let gap: CGFloat = 2
            let side =
                (
                    geometry.size.width
                    - gap
                )
                / 2

            ZStack {

                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .fill(.thinMaterial)

                if displayedSongs.isEmpty {

                    Image(
                        systemName: "music.note"
                    )
                    .font(
                        .system(
                            size: 48,
                            weight: .medium
                        )
                    )

                } else {

                    LazyVGrid(
                        columns: [
                            GridItem(
                                .fixed(side),
                                spacing: gap
                            ),
                            GridItem(
                                .fixed(side),
                                spacing: gap
                            )
                        ],
                        spacing: gap
                    ) {

                        ForEach(
                            0..<4,
                            id: \.self
                        ) { index in

                            if
                                displayedSongs
                                    .indices
                                    .contains(index)
                            {

                                RawSongArtwork(
                                    song:
                                        displayedSongs[index]
                                )
                                .frame(
                                    width: side,
                                    height: side
                                )

                            } else {

                                Rectangle()
                                    .fill(.thinMaterial)
                                    .frame(
                                        width: side,
                                        height: side
                                    )
                            }
                        }
                    }
                }
            }
            .clipped()
        }
    }
}

struct PlaylistStackArtwork: View {

    let playlists: [Playlist]

    var body: some View {

        GeometryReader { geometry in

            ZStack {

                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .fill(.thinMaterial)

                if playlists.isEmpty {

                    Image(
                        systemName:
                            "music.note.list"
                    )
                    .font(
                        .system(
                            size: 46,
                            weight: .medium
                        )
                    )

                } else {

                    ZStack {

                        playlistCard(
                            index: 2,
                            size:
                                geometry.size.width
                                * 0.59
                        )
                        .rotationEffect(.degrees(9))
                        .offset(x: 19, y: -4)

                        playlistCard(
                            index: 1,
                            size:
                                geometry.size.width
                                * 0.65
                        )
                        .rotationEffect(.degrees(-7))
                        .offset(x: -17, y: 7)

                        playlistCard(
                            index: 0,
                            size:
                                geometry.size.width
                                * 0.72
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func playlistCard(
        index: Int,
        size: CGFloat
    ) -> some View {

        if playlists.indices.contains(index) {

            let playlist =
                playlists[index]

            PlaylistCoverArtwork(data: playlist.imageData, builtin: playlist.builtinCoverID, pixels: 256)
            .frame(
                width: size,
                height: size
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .shadow(
                radius: 8,
                y: 4
            )

        } else {

            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .fill(.regularMaterial)
            .frame(
                width: size,
                height: size
            )
        }
    }
}

struct FavoritesFeatureArtwork: View {

    let songs: [Song]

    private var covers: [Song] {
        Array(
            songs.prefix(4)
        )
    }

    var body: some View {

        GeometryReader { geometry in

            ZStack {

                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .fill(.thinMaterial)

                if !covers.isEmpty {

                    HStack(
                        spacing: -22
                    ) {

                        ForEach(
                            Array(
                                covers.prefix(3)
                            )
                        ) { song in

                            RawSongArtwork(
                                song: song
                            )
                            .frame(
                                width:
                                    geometry.size.width
                                    * 0.44,
                                height:
                                    geometry.size.width
                                    * 0.44
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 13,
                                    style: .continuous
                                )
                            )
                            .shadow(
                                radius: 5,
                                y: 3
                            )
                        }
                    }
                    .opacity(0.72)
                    .offset(y: 14)
                }

                Circle()
                    .fill(.regularMaterial)
                    .frame(
                        width: 72,
                        height: 72
                    )
                    .shadow(
                        radius: 10,
                        y: 4
                    )

                Image(
                    systemName: "heart.fill"
                )
                .font(
                    .system(
                        size: 34,
                        weight: .semibold
                    )
                )
                .foregroundStyle(Color.accentColor)
            }
        }
    }
}

struct CollectionCard<
    Artwork: View
>: View {

    let title: LocalizedStringKey
    let subtitle: String
    let symbol: String

    @ViewBuilder
    let artwork: Artwork

    init(
        title: LocalizedStringKey,
        subtitle: String,
        symbol: String,
        @ViewBuilder artwork:
            () -> Artwork
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.artwork = artwork()
    }

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 10
        ) {

            ZStack(
                alignment: .bottomLeading
            ) {

                artwork
                    .frame(maxWidth: .infinity)
                    .frame(height: 105)

                Image(
                    systemName: symbol
                )
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .frame(
                    width: 32,
                    height: 32
                )
                .background(
                    .regularMaterial,
                    in: Circle()
                )
                .padding(10)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(10)
        .background(
            .thinMaterial,
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
    }
}

struct ArtistCollectionArtwork: View {

    let artists: [ArtistGroup]

    var body: some View {

        GeometryReader { _ in

            ZStack {

                Rectangle()
                    .fill(.thinMaterial)

                HStack(spacing: -16) {

                    ForEach(
                        Array(
                            artists.prefix(3)
                        )
                    ) { artist in

                        ArtistArtworkView(
                            songs:
                                artist.songs
                        )
                        .frame(
                            width: 66,
                            height: 66
                        )
                        .clipShape(Circle())
                        .overlay {

                            Circle()
                                .stroke(
                                    .background,
                                    lineWidth: 2
                                )
                        }
                    }
                }
            }
        }
    }
}

struct AlbumCollectionArtwork: View {

    let albums: [AlbumGroup]

    var body: some View {

        ZStack {

            Rectangle()
                .fill(.thinMaterial)

            if
                albums.count > 1,
                let second =
                    albums[1].songs.first
            {

                SongArtworkView(
                    song: second,
                    cornerRadius: 13
                )
                .frame(width: 70, height: 70)
                .rotationEffect(.degrees(8))
                .offset(x: 20, y: -4)
            }

            if
                let firstAlbum =
                    albums.first,
                let song =
                    firstAlbum.songs.first
            {

                SongArtworkView(
                    song: song,
                    cornerRadius: 13
                )
                .frame(width: 75, height: 75)
                .rotationEffect(.degrees(-5))
                .offset(x: -15, y: 7)
            }
        }
    }
}

struct CoverStackArtwork: View {

    let songs: [Song]

    var body: some View {

        ZStack {

            Rectangle()
                .fill(.thinMaterial)

            ForEach(
                Array(
                    songs.prefix(3)
                        .enumerated()
                ),
                id: \.offset
            ) { index, song in

                SongArtworkView(
                    song: song,
                    cornerRadius: 12
                )
                .frame(width: 68, height: 68)
                .rotationEffect(
                    .degrees(
                        Double(index - 1)
                        * 6
                    )
                )
                .offset(
                    x:
                        CGFloat(index - 1)
                        * 15,
                    y:
                        CGFloat(index)
                        * 2
                )
            }
        }
    }
}

struct ArtistsView: View {

    @Environment(\.locale)
    private var locale
    @Environment(MusicLibraryManager.self)
    private var library

    @State private var searchText = ""

    private var allArtists: [ArtistGroup] {
        library.artistGroups
    }

    private var artists: [ArtistGroup] {

        guard !searchText.isEmpty
        else {
            return allArtists
        }

        return allArtists.filter { artist in
            FuzzySearch.matches(
                query: searchText,
                in: [artist.name]
            )
        }
    }

    var body: some View {

        List(artists) { artist in

            NavigationLink {

                ArtistDetailView(
                    artist: artist
                )

            } label: {

                HStack(spacing: 12) {

                    ArtistArtworkView(
                        songs: artist.songs
                    )
                    .frame(width: 55, height: 55)
                    .clipShape(Circle())

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {

                        Text(artist.name)
                            .font(.headline)

                        Text(
                            String(
                                format: String(
                                    localized: "libraryview_songs_count",
                                    locale: locale
                                ),
                                artist.songs.count
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }

        .echoBackground()

        .navigationTitle(
            "libraryview_artists"
        )
        .overlay {
            if library.isLoadingArtists && allArtists.isEmpty {
                ProgressView("libraryview_loading_artists")
            }
        }
        .safeAreaInset(edge: .top) {
            if library.isLoadingArtists && !allArtists.isEmpty {
                ProgressView("libraryview_loading_artists")
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }
        }

        .searchable(
            text: $searchText,
            prompt: "libraryview_search_artists"
        )
    }
}

struct ArtistDetailView: View {

    @Environment(\.locale)
    private var locale
    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(AudioPlayerManager.self)
    private var audioPlayer

    let artist: ArtistGroup

    private var heroData: Data? { songs.first(where: { $0.coverData != nil })?.coverData }

    private var songs: [Song] {
        library.artistGroupsByID[artist.id]?.songs ?? artist.songs.compactMap { library.song(withID: $0.id) }
    }

    private var sortedSongs: [Song] {
        songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        EchoCollectionPage(artworkData: heroData) { colors in
            VStack(alignment: .leading, spacing: 12) {
                EchoCollectionPill(text: Text("collection_kind_artist"), tint: colors.tint)

                Text(artist.name)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(colors.tint)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: String(format: String(localized: "libraryview_songs_count", locale: locale), songs.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    NavigationLink {
                        ArtistCompletionView(name: artist.name)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(colors.tint)
                            .frame(width: 50, height: 50)
                            .background(colors.tint.opacity(0.1), in: .circle)
                            .overlay { Circle().strokeBorder(colors.tint.opacity(0.4), lineWidth: 1) }
                            .contentShape(.circle)
                    }
                    .buttonStyle(HomePressStyle())
                    .accessibilityLabel("artist_find_online")
                    Spacer(minLength: 0)
                    EchoCollectionPlayButtons(tint: colors.tint,
                                              shuffle: { playAll(shuffled: true) },
                                              play: { playAll(shuffled: false) })
                }
                .padding(.top, 4)

                EchoCollectionDivider(tint: colors.tint)
                    .padding(.top, 6)
            }
        } rows: { colors in
            LazyVStack(spacing: 0) {
                ForEach(sortedSongs) { song in
                    artistSongRow(song, tint: colors.tint)
                }
            }
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            if library.isLoadingArtists {
                ProgressView("libraryview_loading_artists")
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }
        }
    }

    private func artistSongRow(_ song: Song, tint: Color) -> some View {
        let isCurrent = audioPlayer.currentSong?.id == song.id
        return Button {
            play(song, queue: sortedSongs)
        } label: {
            HStack(spacing: 14) {
                CachedSongArtwork(data: song.coverData ?? song.imageData)
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                    Text(song.album ?? song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .symbolEffect(.variableColor.iterative, isActive: audioPlayer.isPlaying)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.opacity(isCurrent ? 0.14 : 0))
                    .padding(.horizontal, 8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(HomePressStyle())
        .animation(.easeInOut(duration: 0.25), value: isCurrent)
    }

    private func playAll(shuffled: Bool) {
        let queue = shuffled ? sortedSongs.shuffled() : sortedSongs
        guard let first = queue.first else { return }
        play(first, queue: queue)
    }

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
            from: library.songs
        )
    }
}

struct AlbumsView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @State private var searchText = ""

    @State private var allAlbums: [AlbumGroup] = []

    private var albums: [AlbumGroup] {

        guard !searchText.isEmpty
        else {
            return allAlbums
        }

        return allAlbums.filter { album in
            FuzzySearch.matches(
                query: searchText,
                in: [album.name, album.artist]
            )
        }
    }

    var body: some View {

        List(albums) { album in

            NavigationLink {

                AlbumDetailView(
                    album: album
                )

            } label: {

                HStack(spacing: 12) {

                    if
                        let first =
                            album.songs.first
                    {

                        SongArtworkView(
                            song: first,
                            cornerRadius: 12
                        )
                        .frame(width: 58, height: 58)
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {

                        Text(album.name)
                            .font(.headline)

                        Text(album.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .albumFavoriteActions(FavoriteAlbum(album: album), swipe: true)
        }

        .echoBackground()

        .navigationTitle(
            "libraryview_albums"
        )
        .task(id: library.songRevision) {
            let all = library.songs
            let grouped = await Task.detached(priority: .userInitiated) { LibraryAlbums.groups(from: all) }.value
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { allAlbums = grouped }
        }

        .searchable(
            text: $searchText,
            prompt: "libraryview_search_albums"
        )
    }
}

struct AlbumDetailView: View {
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var audioPlayer
    let album: AlbumGroup
    @State private var searchText = ""
    @State private var sortOption: FavoritesSortOption = .custom
    @State private var selectedSong: Song?
    @State private var findMissing = false
    /// Regrouping the whole library on every body pass made opening an album stutter.
    @State private var liveSongs: [Song]?
    private let favorites = FavoriteAlbumsStore.shared

    private var songs: [Song] { liveSongs ?? album.songs }
    private var processedSongs: [Song] {
        let filtered = AlbumSongSelection.filtered(songs, query: searchText)
        switch sortOption {
        case .custom: return filtered
        case .title: return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist: return filtered.sorted { $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
        case .dateAdded: return filtered.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .lastPlayed: return filtered.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        }
    }
    private var coverData: Data? { songs.first.flatMap { $0.coverData ?? $0.imageData } }

    private var meta: String {
        let year = songs.compactMap(\.releaseYear).min().map(String.init)
        let count = String(format: String(localized: "libraryview_songs_count"), songs.count)
        return [year, count].compactMap { $0 }.joined(separator: " · ")
    }

    private var artistGroup: ArtistGroup? {
        library.artistGroups.first { $0.name.localizedCaseInsensitiveCompare(album.artist) == .orderedSame }
    }

    var body: some View {
        EchoCollectionPage(artworkData: coverData) { colors in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    EchoCollectionPill(text: Text("collection_kind_album"), tint: colors.tint)
                    if let genre = songs.compactMap(\.genre).first(where: { !$0.isEmpty }) {
                        EchoCollectionPill(text: Text(verbatim: genre), tint: colors.tint)
                    }
                }
                Text(album.name)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(colors.tint)
                    .fixedSize(horizontal: false, vertical: true)

                artistLine

                Text(verbatim: meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    let favorite = FavoriteAlbum(album: album)
                    let isFavorite = favorites.contains(favorite)
                    EchoCollectionIconButton(symbol: isFavorite ? "star.fill" : "star",
                                             tint: colors.tint,
                                             label: LocalizedStringKey(isFavorite ? "album_remove_favorite" : "album_add_favorite")) {
                        favorites.toggle(favorite)
                    }
                    EchoCollectionIconButton(symbol: "plus", tint: colors.tint, label: "album_find_missing") {
                        findMissing = true
                    }
                    Spacer(minLength: 0)
                    EchoCollectionPlayButtons(tint: colors.tint,
                                              shuffle: { playAll(shuffled: true) },
                                              play: { playAll(shuffled: false) })
                }
                .padding(.top, 4)

                EchoCollectionDivider(tint: colors.tint)
                    .padding(.top, 6)
            }
        } rows: { colors in
            // All tracks share the album cover, so the rows show the track number instead.
            LazyVStack(spacing: 0) {
                let tracks = processedSongs
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, song in
                    albumTrackRow(song, number: index + 1, tint: colors.tint)
                }
                if tracks.isEmpty {
                    Text("catalog_no_search_results")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }
            }
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "album_search")
        .task(id: library.songRevision) {
            let all = library.songs
            let id = album.id
            let grouped = await Task.detached(priority: .userInitiated) {
                LibraryAlbums.groups(from: all).first { $0.id == id }?.songs ?? []
            }.value
            guard !Task.isCancelled else { return }
            liveSongs = grouped
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("MUSIC_APP_SORT_MENU_SELECTION_HEADER_TITLE", selection: $sortOption) {
                        ForEach(FavoritesSortOption.allCases) { option in Text(option.localizedLabel).tag(option) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                .accessibilityLabel("MUSIC_APP_SORT_MENU_SELECTION_HEADER_TITLE")
                .tint(.primary)
            }
        }
        .sheet(item: $selectedSong) { SongOptionsView(song: $0) }
        .sheet(isPresented: $findMissing) {
            NavigationStack {
                AlbumCompletionView(title: album.name, artist: album.artist)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Group { Button("catalog_done") { findMissing = false }
                            }.tint(.primary)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var artistLine: some View {
        if let artistGroup {
            NavigationLink { ArtistDetailView(artist: artistGroup) } label: { artistLabel }
                .buttonStyle(HomePressStyle())
        } else {
            artistLabel
        }
    }

    private var artistLabel: some View {
        HStack(spacing: 10) {
            CachedSongArtwork(data: coverData)
                .frame(width: 26, height: 26)
                .clipShape(.circle)
            Text(album.artist)
                .font(.headline)
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
        }
        .contentShape(.rect)
    }

    private func playAll(shuffled: Bool) {
        let queue = AlbumSongSelection.queue(processedSongs, shuffled: shuffled)
        guard let first = queue.first, let url = library.getURL(for: first) else { return }
        audioPlayer.lastPlaybackDirection = .fade
        audioPlayer.play(song: first, url: url, queue: queue)
        audioPlayer.allSongs = library.songs
        audioPlayer.fillAutoNext(from: library.songs)
    }

    private func albumTrackRow(_ song: Song, number: Int, tint: Color) -> some View {
        let isCurrent = audioPlayer.currentSong?.id == song.id
        return HStack(spacing: 0) {
            Button { play(song) } label: {
                HStack(spacing: 16) {
                    ZStack {
                        if isCurrent {
                            Image(systemName: "waveform")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(tint)
                                .symbolEffect(.variableColor.iterative, isActive: audioPlayer.isPlaying)
                        } else {
                            Text(verbatim: "\(number)")
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 20)
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(HomePressStyle())
            Button { selectedSong = song } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .accessibilityLabel("album_song_options")
        }
        // The playing track sits on a soft tinted card, like Joi Tunes.
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(isCurrent ? 0.14 : 0))
                .padding(.horizontal, 8)
        }
        .animation(.easeInOut(duration: 0.25), value: isCurrent)
        .contextMenu {
            Button("album_song_options", systemImage: "ellipsis") { selectedSong = song }
        }
    }

    private func play(_ song: Song) {
        guard let url = library.getURL(for: song) else { return }
        audioPlayer.lastPlaybackDirection = .fade
        audioPlayer.play(song: song, url: url, queue: processedSongs)
        audioPlayer.allSongs = library.songs
        audioPlayer.fillAutoNext(from: library.songs)
    }
}

struct RecentAddedView: View {
    @Environment(MusicLibraryManager.self)
    private var library

    var body: some View {

        SongCollectionView(
            title: "libraryview_recent_added",
            songs:
                library.songs.sorted {
                    $0.dateAdded
                    >
                    $1.dateAdded
                }
        )
    }
}

struct RecentPlayedView: View {
    @Environment(MusicLibraryManager.self)
    private var library

    var body: some View {

        SongCollectionView(
            title: "libraryview_recent_played",
            songs:
                library.songs
                    .filter {
                        $0.lastPlayed != nil
                    }
                    .sorted {
                        ($0.lastPlayed ?? .distantPast)
                        >
                        ($1.lastPlayed ?? .distantPast)
                    }
        )
    }
}

struct SongCollectionView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(AudioPlayerManager.self)
    private var audioPlayer

    let title: LocalizedStringKey
    let songs: [Song]

    var body: some View {

        List(songs) { song in

            Button {

                play(song)

            } label: {

                LibrarySongRow(
                    song: song
                )
            }
            .buttonStyle(.plain)
        }
        .echoBackground()
        .navigationTitle(title)
    }

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
            queue: [song]
        )

        audioPlayer.allSongs =
            library.songs

        audioPlayer.autoNextQueue.removeAll()
        audioPlayer.autoNextIndex = 0

        audioPlayer.fillAutoNext(
            from: library.songs
        )
    }
}

struct LibrarySongRow: View {

    let song: Song

    var body: some View {

        HStack(spacing: 12) {

            SongArtworkView(
                song: song,
                cornerRadius: 10
            )
            .frame(width: 50, height: 50)

            VStack(
                alignment: .leading,
                spacing: 2
            ) {

                Text(song.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }
}

struct SongArtworkView: View {

    let song: Song
    let cornerRadius: CGFloat

    var body: some View {

        GeometryReader { geometry in

            RawSongArtwork(
                song: song
            )
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .clipped()
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius:
                    cornerRadius,
                style: .continuous
            )
        )
    }
}

struct RawSongArtwork: View {

    let song: Song

    var body: some View {

        CachedSongArtwork(data: song.coverData ?? song.imageData)
    }
}

struct ArtistArtworkView: View {

    let songs: [Song]

    var body: some View {

        GeometryReader { geometry in

            Group {

                // Decoded once off the main thread and cached, not in every body pass.
                if let data = songs.first(where: { $0.coverData != nil })?.coverData {

                    CachedSongArtwork(data: data)

                } else {

                    ZStack {

                        Rectangle()
                            .fill(.thinMaterial)

                        Image(
                            systemName:
                                "person.crop.circle.fill"
                        )
                        .font(
                            .system(size: 50)
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .clipped()
        }
    }
}
