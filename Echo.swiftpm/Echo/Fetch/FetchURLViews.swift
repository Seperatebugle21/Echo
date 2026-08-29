import SwiftUI
import UIKit


// MARK: - Inline URL Section

struct FetchURLInlineSection:
    View {

    @State private var urlText =
        ""

    @State private var isResolving =
        false

    @State private var resolved:
        FetchURLResolvedContent?

    @State private var errorMessage:
        String?


    var body: some View {

        Section {

            HStack(
                spacing:
                    8
            ) {

                TextField(
                    "Spotify or YouTube Music URL",
                    text:
                        $urlText
                )
                .textInputAutocapitalization(
                    .never
                )
                .autocorrectionDisabled()
                .keyboardType(
                    .URL
                )


                if !urlText.isEmpty {

                    Button {

                        urlText =
                            ""

                    } label: {

                        Image(
                            systemName:
                                "xmark.circle.fill"
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                    .buttonStyle(
                        .plain
                    )
                }


                Button {

                    paste()

                } label: {

                    Image(
                        systemName:
                            "doc.on.clipboard"
                    )
                }
                .buttonStyle(
                    .plain
                )
            }


            Button {

                resolve()

            } label: {

                HStack {

                    Spacer()


                    if isResolving {

                        ProgressView()
                            .controlSize(
                                .small
                            )


                        Text(
                            "Loading..."
                        )

                    } else {

                        Label(
                            "Fetch URL",
                            systemImage:
                                "arrow.down.circle"
                        )
                    }


                    Spacer()
                }
            }
            .disabled(
                urlText
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .isEmpty
                ||
                isResolving
            )

        } header: {

            Text(
                "URL"
            )

        } footer: {

            Text(
                "Paste a Spotify or YouTube Music song or playlist link."
            )
        }

        .sheet(
            item:
                $resolved
        ) {
            content in

            FetchURLPreviewView(
                content:
                    content
            )
        }

        .alert(
            "Could Not Open URL",
            isPresented:
                Binding(
                    get: {

                        errorMessage !=
                            nil
                    },
                    set: {
                        newValue in

                        if !newValue {

                            errorMessage =
                                nil
                        }
                    }
                )
        ) {

            Button(
                "OK",
                role:
                    .cancel
            ) {}

        } message: {

            Text(
                errorMessage
                ??
                "Unknown error."
            )
        }
    }


    // MARK: - Resolve

    private func resolve() {

        guard !isResolving else {

            return
        }


        isResolving =
            true

        errorMessage =
            nil


        let input =
            urlText


        Task {

            do {

                let result =
                    try await
                    FetchURLResolver.shared
                        .resolve(
                            input
                        )


                resolved =
                    result


            } catch {

                errorMessage =
                    error.localizedDescription
            }


            isResolving =
                false
        }
    }


    // MARK: - Paste

    private func paste() {

        guard let string =
            UIPasteboard.general
                .string
        else {

            return
        }


        urlText =
            string
    }
}


// MARK: - Navigation Bar URL Input

struct FetchURLInputSheet:
    View {

    @Environment(
        \.dismiss
    )
    private var dismiss


    @State private var urlText =
        ""

    @State private var isResolving =
        false

    @State private var resolved:
        FetchURLResolvedContent?

    @State private var errorMessage:
        String?


    var body: some View {

        NavigationStack {

            Form {

                Section {

                    HStack(
                        spacing:
                            8
                    ) {

                        TextField(
                            "Paste URL",
                            text:
                                $urlText
                        )
                        .textInputAutocapitalization(
                            .never
                        )
                        .autocorrectionDisabled()
                        .keyboardType(
                            .URL
                        )


                        Button {

                            paste()

                        } label: {

                            Image(
                                systemName:
                                    "doc.on.clipboard"
                            )
                        }
                    }


                    Button {

                        resolve()

                    } label: {

                        HStack {

                            Spacer()


                            if isResolving {

                                ProgressView()
                                    .controlSize(
                                        .small
                                    )


                                Text(
                                    "Loading..."
                                )

                            } else {

                                Label(
                                    "Fetch URL",
                                    systemImage:
                                        "arrow.down.circle"
                                )
                            }


                            Spacer()
                        }
                    }
                    .disabled(
                        urlText
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty
                        ||
                        isResolving
                    )

                } header: {

                    Text(
                        "URL"
                    )

                } footer: {

                    Text(
                        "Spotify and YouTube Music songs and playlists are supported."
                    )
                }
            }

            .navigationTitle(
                "Fetch URL"
            )

            .navigationBarTitleDisplayMode(
                .inline
            )

            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    Button(
                        "Done"
                    ) {

                        dismiss()
                    }
                }
            }
        }

        .sheet(
            item:
                $resolved
        ) {
            content in

            FetchURLPreviewView(
                content:
                    content
            )
        }

        .alert(
            "Could Not Open URL",
            isPresented:
                Binding(
                    get: {

                        errorMessage !=
                            nil
                    },
                    set: {
                        newValue in

                        if !newValue {

                            errorMessage =
                                nil
                        }
                    }
                )
        ) {

            Button(
                "OK",
                role:
                    .cancel
            ) {}

        } message: {

            Text(
                errorMessage
                ??
                "Unknown error."
            )
        }
    }


    // MARK: - Resolve

    private func resolve() {

        guard !isResolving else {

            return
        }


        isResolving =
            true

        errorMessage =
            nil


        let input =
            urlText


        Task {

            do {

                resolved =
                    try await
                    FetchURLResolver.shared
                        .resolve(
                            input
                        )


            } catch {

                errorMessage =
                    error.localizedDescription
            }


            isResolving =
                false
        }
    }


    // MARK: - Paste

    private func paste() {

        guard let string =
            UIPasteboard.general
                .string
        else {

            return
        }


        urlText =
            string
    }
}


// MARK: - Preview

struct FetchURLPreviewView:
    View {

    let content:
        FetchURLResolvedContent


    @Environment(
        \.dismiss
    )
    private var dismiss


    @State private var manager =
        FetchManager.shared


    @State private var isStarting =
        false


    @State private var showStarted =
        false


    @State private var errorMessage:
        String?


    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(
                    spacing:
                        20
                ) {

                    artwork


                    VStack(
                        spacing:
                            5
                    ) {

                        Text(
                            content.title
                        )
                        .font(
                            .title2
                                .bold()
                        )
                        .multilineTextAlignment(
                            .center
                        )


                        Text(
                            subtitle
                        )
                        .foregroundStyle(
                            .secondary
                        )
                        .multilineTextAlignment(
                            .center
                        )


                        HStack(
                            spacing:
                                5
                        ) {

                            Image(
                                systemName:
                                    sourceIcon
                            )


                            Text(
                                content
                                    .sourceTitle
                            )
                        }
                        .font(
                            .caption
                        )
                        .foregroundStyle(
                            .secondary
                        )
                        .padding(
                            .top,
                            2
                        )
                    }


                    if content.isPlaylist {

                        playlistTracks
                    }


                    Button {

                        startDownload()

                    } label: {

                        HStack {

                            Spacer()


                            if isStarting {

                                ProgressView()
                                    .tint(
                                        .white
                                    )


                            } else {

                                Label(
                                    downloadButtonTitle,
                                    systemImage:
                                        "arrow.down.circle.fill"
                                )
                            }


                            Spacer()
                        }
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .controlSize(
                        .large
                    )
                    .disabled(
                        isStarting
                    )
                }
                .padding(
                    20
                )
            }

            .navigationTitle(
                content.isPlaylist
                ?
                "Playlist"
                :
                "Song"
            )

            .navigationBarTitleDisplayMode(
                .inline
            )

            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    Button(
                        "Done"
                    ) {

                        dismiss()
                    }
                }
            }
        }

        .alert(
            "Added to Fetch",
            isPresented:
                $showStarted
        ) {

            Button(
                "Done"
            ) {

                dismiss()
            }


            Button(
                "View Downloads"
            ) {

                dismiss()


                DispatchQueue.main
                    .async {

                        NotificationCenter
                            .default
                            .post(
                                name:
                                    .echoOpenFetchDownloads,
                                object:
                                    nil
                            )
                    }
            }

        } message: {

            if content.isPlaylist {

                Text(
                    "\(content.trackCount) songs were added to the download queue."
                )

            } else {

                Text(
                    "The song was added to the download queue."
                )
            }
        }

        .alert(
            "Download Failed",
            isPresented:
                Binding(
                    get: {

                        errorMessage !=
                            nil
                    },
                    set: {
                        value in

                        if !value {

                            errorMessage =
                                nil
                        }
                    }
                )
        ) {

            Button(
                "OK",
                role:
                    .cancel
            ) {}

        } message: {

            Text(
                errorMessage
                ??
                "Unknown error."
            )
        }
    }


    // MARK: - Artwork

    private var artwork:
        some View {

        AsyncImage(
            url:
                content.artworkURL
        ) {
            image in

            image
                .resizable()
                .scaledToFill()

        } placeholder: {

            RoundedRectangle(
                cornerRadius:
                    22
            )
            .fill(
                .secondary
                    .opacity(
                        0.12
                    )
            )
            .overlay {

                Image(
                    systemName:
                        content.isPlaylist
                        ?
                        "music.note.list"
                        :
                        "music.note"
                )
                .font(
                    .system(
                        size:
                            52
                    )
                )
                .foregroundStyle(
                    .secondary
                )
            }
        }
        .frame(
            width:
                230,
            height:
                230
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius:
                    22
            )
        )
    }


    // MARK: - Playlist Tracks

    @ViewBuilder
    private var playlistTracks:
        some View {

        VStack(
            alignment:
                .leading,
            spacing:
                0
        ) {

            HStack {

                Text(
                    "Songs"
                )
                .font(
                    .headline
                )


                Spacer()


                Text(
                    "\(content.trackCount)"
                )
                .foregroundStyle(
                    .secondary
                )
            }
            .padding(
                .bottom,
                10
            )


            ForEach(
                Array(
                    playlistRows
                        .prefix(
                            12
                        )
                )
            ) {
                row in

                HStack(
                    spacing:
                        10
                ) {

                    AsyncImage(
                        url:
                            row.artworkURL
                    ) {
                        image in

                        image
                            .resizable()
                            .scaledToFill()

                    } placeholder: {

                        RoundedRectangle(
                            cornerRadius:
                                6
                        )
                        .fill(
                            .secondary
                                .opacity(
                                    0.12
                                )
                        )
                    }
                    .frame(
                        width:
                            42,
                        height:
                            42
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius:
                                6
                        )
                    )


                    VStack(
                        alignment:
                            .leading,
                        spacing:
                            2
                    ) {

                        Text(
                            row.title
                        )
                        .lineLimit(
                            1
                        )


                        Text(
                            row.artist
                        )
                        .font(
                            .caption
                        )
                        .foregroundStyle(
                            .secondary
                        )
                        .lineLimit(
                            1
                        )
                    }


                    Spacer()
                }
                .padding(
                    .vertical,
                    6
                )


                Divider()
            }


            if playlistRows.count >
                12 {

                Text(
                    "+ \(playlistRows.count - 12) more songs"
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .secondary
                )
                .padding(
                    .top,
                    10
                )
            }
        }
        .padding(
            14
        )
        .background(
            .secondary
                .opacity(
                    0.07
                ),
            in:
                RoundedRectangle(
                    cornerRadius:
                        16
                )
        )
    }


    // MARK: - Presentation

    private var subtitle:
        String {

        switch content {

        case .spotifyTrack(
            let track
        ):

            return
                "\(track.artist) • \(track.album)"


        case .spotifyPlaylist(
            _,
            let tracks
        ):

            return
                "\(tracks.count) songs"


        case .youtubeTrack(
            let track
        ):

            return
                track.artist


        case .youtubePlaylist(
            let playlist
        ):

            return
                "\(playlist.tracks.count) songs"
        }
    }


    private var sourceIcon:
        String {

        switch content {

        case .spotifyTrack,
             .spotifyPlaylist:

            return
                "music.note"


        case .youtubeTrack,
             .youtubePlaylist:

            return
                "play.rectangle.fill"
        }
    }


    private var downloadButtonTitle:
        String {

        if content.isPlaylist {

            return
                "Download \(content.trackCount) Songs"

        } else {

            return
                "Download"
        }
    }


    // MARK: - Rows

    private struct PreviewRow:
        Identifiable {

        let id:
            String

        let title:
            String

        let artist:
            String

        let artworkURL:
            URL?
    }


    private var playlistRows:
        [PreviewRow] {

        switch content {

        case .spotifyPlaylist(
            _,
            let tracks
        ):

            return tracks.map {
                track in

                PreviewRow(
                    id:
                        track.id,

                    title:
                        track.name,

                    artist:
                        track.artist,

                    artworkURL:
                        track.artworkURL
                )
            }


        case .youtubePlaylist(
            let playlist
        ):

            return playlist.tracks.map {
                track in

                PreviewRow(
                    id:
                        track.id,

                    title:
                        track.title,

                    artist:
                        track.artist,

                    artworkURL:
                        track.artworkURL
                )
            }


        default:

            return []
        }
    }


    // MARK: - Download

    private func startDownload() {

        guard !isStarting else {

            return
        }


        isStarting =
            true


        Task {

            do {

                switch content {

                // MARK: Spotify Track

                case .spotifyTrack(
                    let track
                ):

                    try await
                        addSpotifyTrack(
                            track
                        )


                // MARK: Spotify Playlist

                case .spotifyPlaylist(
                    _,
                    let tracks
                ):

                    await manager
                        .preparePlaylistTracks(
                            tracks
                        )


                // MARK: YouTube Track

                case .youtubeTrack(
                    let track
                ):

                    addYouTubeTrack(
                        track
                    )


                // MARK: YouTube Playlist

                case .youtubePlaylist(
                    let playlist
                ):

                    for track
                        in playlist.tracks {

                        addYouTubeTrack(
                            track
                        )
                    }
                }


                showStarted =
                    true


            } catch {

                errorMessage =
                    error.localizedDescription
            }


            isStarting =
                false
        }
    }


    // MARK: - Spotify Track Download

    private func addSpotifyTrack(
        _ track: SpotifyTrack
    ) async throws {

        switch
            ApifySettings.shared
                .downloadMethod {

        case .spotify:

            manager
                .addAuthorizedSpotifyTrack(
                    track
                )


        case .youtube:

            let results =
                try await
                YouTubeAPI.shared
                    .search(
                        title:
                            track.name,

                        artist:
                            track.artist,

                        maxResults:
                            1
                    )


            guard let result =
                results.first
            else {

                throw
                    YTDLPAudioSourceError
                        .noYouTubeMatch
            }


            manager
                .addAuthorizedMatch(
                    track:
                        track,

                    youtubeResult:
                        result
                )
        }
    }


    // MARK: - YouTube Track Download

    private func addYouTubeTrack(
        _ track:
            FetchURLTrackPreview
    ) {

        let item =
            FetchItem(
                spotifyURL:
                    track.sourceURL,

                title:
                    cleanedYouTubeTitle(
                        track.title
                    ),

                artist:
                    track.artist,

                album:
                    nil,

                artworkURL:
                    track.artworkURL,

                youtubeURL:
                    track.sourceURL,

                permissionConfirmed:
                    true
            )


        manager
            .addPreparedItem(
                item
            )
    }


    // MARK: - Clean YouTube Title

    private func cleanedYouTubeTitle(
        _ value: String
    ) -> String {

        var title =
            value


        let removable = [

            "(Official Video)",
            "(Official Music Video)",
            "(Official Audio)",

            "[Official Video]",
            "[Official Audio]",

            "Official Video",
            "Official Audio"
        ]


        for part in removable {

            title =
                title
                    .replacingOccurrences(
                        of:
                            part,

                        with:
                            "",

                        options:
                            .caseInsensitive
                    )
        }


        return title
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
    }
}
