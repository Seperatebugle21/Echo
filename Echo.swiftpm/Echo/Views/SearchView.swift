import SwiftUI

struct SearchView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(AudioPlayerManager.self)
    private var audioPlayer

    @State private var searchText = ""
    @State private var showAllSongs = false
    @State private var showSettings = false

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

        recentSearchSongIDs.compactMap { id in

            library.songs.first {
                $0.id == id
            }
        }
    }


    // MARK: - Songs

    private var matchingSongs: [Song] {

        let query =
            searchText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !query.isEmpty else {
            return []
        }

        return library.songs.filter { song in
            FuzzySearch.matches(
                query: query,
                in: [song.title, song.artist, song.album]
            )
        }
    }

    private var displayedSongs: [Song] {

        if showAllSongs {
            return matchingSongs
        }

        return Array(
            matchingSongs.prefix(10)
        )
    }


    // MARK: - Artists

    private var allArtists: [ArtistGroup] {

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
                            "searchview_unknown_artist"
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
                == .orderedAscending
            }
    }

    private var matchingArtists: [ArtistGroup] {

        let query =
            searchText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !query.isEmpty else {
            return []
        }

        return allArtists.filter {

            $0.name
                .localizedCaseInsensitiveContains(
                    query
                )
        }
    }


    // MARK: - Albums

    private var allAlbums: [AlbumGroup] {

        let validSongs =
            library.songs.filter { song in

                guard
                    let album =
                        song.album?
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                else {
                    return false
                }

                return !album.isEmpty
            }

        let grouped =
            Dictionary(
                grouping: validSongs
            ) { song in

                "\(song.artist)|\(song.album ?? "")"
            }

        return grouped
            .compactMap { _, songs in

                guard
                    let first = songs.first,
                    let album = first.album
                else {
                    return nil
                }

                return AlbumGroup(
                    name: album,
                    artist: first.artist,
                    songs: songs
                )
            }
            .sorted {

                $0.name
                    .localizedCaseInsensitiveCompare(
                        $1.name
                    )
                == .orderedAscending
            }
    }

    private var matchingAlbums: [AlbumGroup] {

        let query =
            searchText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !query.isEmpty else {
            return []
        }

        return allAlbums.filter { album in

            album.name
                .localizedCaseInsensitiveContains(
                    query
                )

            ||

            album.artist
                .localizedCaseInsensitiveContains(
                    query
                )
        }
    }


    // MARK: - Playlists

    private var matchingPlaylists: [Playlist] {

        let query =
            searchText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !query.isEmpty else {
            return []
        }

        return library.playlists.filter {

            $0.name
                .localizedCaseInsensitiveContains(
                    query
                )
        }
    }


    // MARK: - Results

    private var hasResults: Bool {

        !matchingSongs.isEmpty
        ||
        !matchingArtists.isEmpty
        ||
        !matchingAlbums.isEmpty
        ||
        !matchingPlaylists.isEmpty
    }


    // MARK: - Body

    var body: some View {

        NavigationStack {

            ScrollView {

                LazyVStack(
                    alignment: .leading,
                    spacing: 30
                ) {

                    header

                    searchBar

                    if searchText
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty
                    {

                        idleContent

                    } else if !hasResults {

                        noResultsView

                    } else {

                        searchResults
                    }
                }
                .padding(.bottom, 120)
            }

            .toolbar(
                .hidden,
                for: .navigationBar
            )

            .sheet(
                isPresented: $showSettings
            ) {

                SettingsView()
            }

            .onChange(of: searchText) {

                showAllSongs = false
            }
        }
    }


    // MARK: - Header

    private var header: some View {

        HStack(alignment: .center) {

            Text("searchview_title")
                .font(.largeTitle.bold())

            Spacer()

            Button {

                showSettings = true

            } label: {

                Image(
                    systemName: "gearshape"
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
    }


    // MARK: - Search Bar

    private var searchBar: some View {

        HStack(spacing: 11) {

            Image(
                systemName: "magnifyingglass"
            )
            .font(
                .system(
                    size: 16,
                    weight: .medium
                )
            )
            .foregroundStyle(.secondary)

            TextField(
                "searchview_placeholder",
                text: $searchText
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit {

                saveCurrentSearch()
            }

            if !searchText.isEmpty {

                Button {

                    withAnimation(
                        .easeInOut(duration: 0.18)
                    ) {

                        searchText = ""
                    }

                } label: {

                    Image(
                        systemName:
                            "xmark.circle.fill"
                    )
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 48)
        .background(
            .thinMaterial,
            in:
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
        )
        .padding(.horizontal)
    }


    // MARK: - Idle Content

    @ViewBuilder
    private var idleContent: some View {

        if !recentQueries.isEmpty {

            recentSearchesSection
        }

        if !recentlySearchedSongs.isEmpty {

            recentlySearchedSection
        }

        if !allArtists.isEmpty {

            idleArtistsSection
        }

        if !allAlbums.isEmpty {

            idleAlbumsSection
        }

        if !library.playlists.isEmpty {

            idlePlaylistsSection
        }

        if library.songs.isEmpty {

            ContentUnavailableView(
                "searchview_empty_library_title",
                systemImage: "music.note",
                description:
                    Text(
                        "searchview_empty_library_description"
                    )
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 45)
        }
    }


    // MARK: - Recent Searches

    private var recentSearchesSection: some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            HStack {

                Text(
                    "searchview_recent_searches"
                )
                .font(.title2.bold())

                Spacer()

                Button {

                    clearRecentSearches()

                } label: {

                    Text(
                        "searchview_clear_recent"
                    )
                    .font(
                        .subheadline
                            .weight(.medium)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            VStack(spacing: 0) {

                ForEach(
                    Array(
                        recentQueries.prefix(4)
                    ),
                    id: \.self
                ) { query in

                    Button {

                        withAnimation(
                            .easeInOut(
                                duration: 0.18
                            )
                        ) {

                            searchText = query
                        }

                    } label: {

                        HStack(spacing: 13) {

                            Image(
                                systemName:
                                    "clock.arrow.circlepath"
                            )
                            .font(.system(size: 16))
                            .foregroundStyle(
                                .secondary
                            )
                            .frame(width: 22)

                            Text(query)
                                .font(.body)
                                .foregroundStyle(
                                    .primary
                                )
                                .lineLimit(1)

                            Spacer()

                            Image(
                                systemName:
                                    "arrow.up.left"
                            )
                            .font(
                                .caption
                                    .weight(.semibold)
                            )
                            .foregroundStyle(
                                .tertiary
                            )
                        }
                        .padding(.horizontal, 15)
                        .frame(height: 47)
                        .contentShape(
                            Rectangle()
                        )
                    }
                    .buttonStyle(.plain)

                    if query
                        !=
                        Array(
                            recentQueries.prefix(4)
                        ).last
                    {

                        Divider()
                            .padding(.leading, 50)
                    }
                }
            }
            .background(
                .thinMaterial,
                in:
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
            )
            .padding(.horizontal)
        }
    }


    // MARK: - Recently searched songs

    private var recentlySearchedSection: some View {

        VStack(
            alignment: .leading,
            spacing: 13
        ) {

            Text(
                "searchview_recently_searched"
            )
            .font(.title2.bold())
            .padding(.horizontal)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {

                LazyHStack(spacing: 15) {

                    ForEach(
                        recentlySearchedSongs.prefix(6)
                    ) { song in

                        Button {

                            rememberRecentSong(song)
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
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }


    // MARK: - Idle Artists

    private var idleArtistsSection: some View {

        VStack(
            alignment: .leading,
            spacing: 13
        ) {

            Text(
                "searchview_your_artists"
            )
            .font(.title2.bold())
            .padding(.horizontal)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {

                LazyHStack(spacing: 18) {

                    ForEach(
                        Array(
                            allArtists.prefix(12)
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
                                .clipShape(Circle())

                                Text(artist.name)
                                    .font(
                                        .subheadline
                                            .weight(.medium)
                                    )
                                    .foregroundStyle(
                                        .primary
                                    )
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


    // MARK: - Idle Albums

    private var idleAlbumsSection: some View {

        VStack(
            alignment: .leading,
            spacing: 13
        ) {

            Text(
                "searchview_browse_albums"
            )
            .font(.title2.bold())
            .padding(.horizontal)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {

                LazyHStack(spacing: 15) {

                    ForEach(
                        Array(
                            allAlbums.prefix(12)
                        )
                    ) { album in

                        NavigationLink {

                            AlbumDetailView(
                                album: album
                            )

                        } label: {

                            VStack(
                                alignment: .leading,
                                spacing: 7
                            ) {

                                albumArtwork(
                                    album,
                                    size: 150
                                )

                                Text(album.name)
                                    .font(.headline)
                                    .foregroundStyle(
                                        .primary
                                    )
                                    .lineLimit(1)

                                Text(album.artist)
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
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }


    // MARK: - Idle Playlists

    private var idlePlaylistsSection: some View {

        VStack(
            alignment: .leading,
            spacing: 13
        ) {

            Text(
                "searchview_browse_playlists"
            )
            .font(.title2.bold())
            .padding(.horizontal)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {

                LazyHStack(spacing: 15) {

                    ForEach(
                        Array(
                            library.playlists.prefix(12)
                        )
                    ) { playlist in

                        NavigationLink {

                            PlaylistDetailView(
                                playlist: playlist
                            )

                        } label: {

                            VStack(
                                alignment: .leading,
                                spacing: 7
                            ) {

                                PlaylistSearchArtwork(
                                    playlist: playlist
                                )
                                .frame(
                                    width: 150,
                                    height: 150
                                )

                                Text(playlist.name)
                                    .font(.headline)
                                    .foregroundStyle(
                                        .primary
                                    )
                                    .lineLimit(1)

                                Text(
                                    String(
                                        format:
                                            String(
                                                localized:
                                                    "searchview_songs_count"
                                            ),
                                        playlist.songIDs.count
                                    )
                                )
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
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }


    // MARK: - No Results

    private var noResultsView: some View {

        VStack(spacing: 13) {

            Image(
                systemName:
                    "magnifyingglass"
            )
            .font(
                .system(
                    size: 38,
                    weight: .medium
                )
            )
            .foregroundStyle(.secondary)

            Text(
                "searchview_no_results"
            )
            .font(.title3.bold())

            Text(
                String(
                    format:
                        String(
                            localized:
                                "searchview_no_results_for_query"
                        ),
                    searchText
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(
                .center
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.top, 55)
    }


    // MARK: - Search Results

    @ViewBuilder
    private var searchResults: some View {

        if !matchingSongs.isEmpty {

            songsResultSection
        }

        if !matchingArtists.isEmpty {

            artistsResultSection
        }

        if !matchingAlbums.isEmpty {

            albumsResultSection
        }

        if !matchingPlaylists.isEmpty {

            playlistsResultSection
        }
    }


    // MARK: Songs Results

    private var songsResultSection: some View {

        VStack(
            alignment: .leading,
            spacing: 10
        ) {

            Text(
                "searchview_searched_songs"
            )
            .font(.title2.bold())
            .padding(.horizontal)

            VStack(spacing: 0) {

                ForEach(
                    displayedSongs
                ) { song in

                    Button {

                        saveCurrentSearch()
                        rememberRecentSong(song)
                        play(song)

                    } label: {

                        LibrarySongRow(
                            song: song
                        )
                        .padding(.vertical, 9)
                        .contentShape(
                            Rectangle()
                        )
                    }
                    .buttonStyle(.plain)

                    if
                        song.id
                        !=
                        displayedSongs.last?.id
                    {

                        Divider()
                            .padding(
                                .leading,
                                62
                            )
                    }
                }

                if
                    matchingSongs.count > 10,
                    !showAllSongs
                {

                    Divider()
                        .padding(
                            .leading,
                            62
                        )

                    Button {

                        withAnimation(
                            .easeInOut(
                                duration: 0.2
                            )
                        ) {

                            showAllSongs = true
                        }

                    } label: {

                        HStack {

                            Text(
                                String(
                                    format:
                                        String(
                                            localized:
                                                "searchview_show_all_results"
                                        ),
                                    matchingSongs.count
                                )
                            )
                            .font(
                                .subheadline
                                    .weight(.medium)
                            )

                            Spacer()

                            Image(
                                systemName:
                                    "chevron.down"
                            )
                            .font(
                                .caption.bold()
                            )
                        }
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .background(
                .thinMaterial,
                in:
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
            )
            .padding(.horizontal)
        }
    }


    // MARK: Artists Results

    private var artistsResultSection: some View {

        VStack(
            alignment: .leading,
            spacing: 13
        ) {

            Text(
                "searchview_searched_artists"
            )
            .font(.title2.bold())
            .padding(.horizontal)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {

                LazyHStack(spacing: 18) {

                    ForEach(
                        matchingArtists
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
                                .clipShape(Circle())

                                Text(artist.name)
                                    .font(
                                        .subheadline
                                            .weight(.medium)
                                    )
                                    .foregroundStyle(
                                        .primary
                                    )
                                    .lineLimit(1)
                                    .frame(width: 112)

                                Text(
                                    String(
                                        format:
                                            String(
                                                localized:
                                                    "searchview_songs_count"
                                            ),
                                        artist.songs.count
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    .secondary
                                )
                                .lineLimit(1)
                                .frame(width: 112)
                            }
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded {

                                    saveCurrentSearch()
                                }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }


    // MARK: Albums Results

    private var albumsResultSection: some View {

        VStack(
            alignment: .leading,
            spacing: 13
        ) {

            Text(
                "searchview_searched_albums"
            )
            .font(.title2.bold())
            .padding(.horizontal)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {

                LazyHStack(spacing: 15) {

                    ForEach(
                        matchingAlbums
                    ) { album in

                        NavigationLink {

                            AlbumDetailView(
                                album: album
                            )

                        } label: {

                            VStack(
                                alignment: .leading,
                                spacing: 7
                            ) {

                                albumArtwork(
                                    album,
                                    size: 150
                                )

                                Text(album.name)
                                    .font(.headline)
                                    .foregroundStyle(
                                        .primary
                                    )
                                    .lineLimit(1)

                                Text(album.artist)
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
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded {

                                    saveCurrentSearch()
                                }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }


    // MARK: Playlists Results

    private var playlistsResultSection: some View {

        VStack(
            alignment: .leading,
            spacing: 13
        ) {

            Text(
                "searchview_searched_playlists"
            )
            .font(.title2.bold())
            .padding(.horizontal)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {

                LazyHStack(spacing: 15) {

                    ForEach(
                        matchingPlaylists
                    ) { playlist in

                        NavigationLink {

                            PlaylistDetailView(
                                playlist: playlist
                            )

                        } label: {

                            VStack(
                                alignment: .leading,
                                spacing: 7
                            ) {

                                PlaylistSearchArtwork(
                                    playlist: playlist
                                )
                                .frame(
                                    width: 150,
                                    height: 150
                                )

                                Text(playlist.name)
                                    .font(.headline)
                                    .foregroundStyle(
                                        .primary
                                    )
                                    .lineLimit(1)

                                Text(
                                    String(
                                        format:
                                            String(
                                                localized:
                                                    "searchview_songs_count"
                                            ),
                                        playlist.songIDs.count
                                    )
                                )
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
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded {

                                    saveCurrentSearch()
                                }
                        )
                    }
                }
                .padding(.horizontal)
            }
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


// MARK: - Playlist Artwork

struct PlaylistSearchArtwork: View {

    let playlist: Playlist

    var body: some View {

        GeometryReader { geometry in

            Group {

                if
                    let data =
                        playlist.imageData,
                    let image =
                        UIImage(data: data)
                {

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()

                } else {

                    ZStack {

                        Rectangle()
                            .fill(
                                .thinMaterial
                            )

                        Image(
                            systemName:
                                "music.note.list"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }
            }
            .frame(
                width:
                    geometry.size.width,
                height:
                    geometry.size.height
            )
            .clipped()
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }
}
