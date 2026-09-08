import SwiftUI
import UIKit

struct FetchURLInlineSection:
    View
{

    let onResolved:
        (FetchURLResolvedContent) -> Void

    @State private var urlText =
        ""

    @State private var isResolving =
        false

    @State private var errorMessage:
        String?

    var body: some View {

        Section {

            HStack(
                spacing: 8
            ) {

                TextField(
                    String(
                        localized:
                            "fetchurlviews_spotify_or_youtube_music_url"
                    ),
                    text:
                        $urlText
                )
                .textInputAutocapitalization(
                    .never
                )
                .autocorrectionDisabled()
                .keyboardType(.URL)

                if !urlText.isEmpty {

                    Button {

                        urlText = ""

                    } label: {

                        Image(
                            systemName:
                                "xmark.circle.fill"
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {

                    paste()

                } label: {

                    Image(
                        systemName:
                            "doc.on.clipboard"
                    )
                }
                .buttonStyle(.plain)
            }

            Button {

                resolve()

            } label: {

                HStack {

                    Spacer()

                    if isResolving {

                        ProgressView()
                            .controlSize(.small)

                        Text(
                            "fetchurlviews_loading"
                        )

                    } else {

                        Label(
                            "fetchurlviews_fetch_url",
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
                "fetchurlviews_url"
            )

        } footer: {

            Text(
                "fetchurlviews_inline_footer"
            )
        }

        .alert(
            "fetchurlviews_could_not_open_url",
            isPresented:
                Binding(
                    get: {
                        errorMessage != nil
                    },
                    set: { newValue in

                        if !newValue {
                            errorMessage = nil
                        }
                    }
                )
        ) {

            Button(
                "fetchurlviews_ok",
                role: .cancel
            ) {}

        } message: {

            Text(
                errorMessage
                ??
                String(
                    localized:
                        "fetchurlviews_unknown_error"
                )
            )
        }
    }

    private func resolve() {

        guard !isResolving else {
            return
        }

        isResolving = true
        errorMessage = nil

        let input =
            urlText

        Task {

            do {

                let result =
                    try await
                    FetchURLResolver.shared
                        .resolve(input)

                isResolving = false

                await Task.yield()

                onResolved(result)

            } catch {

                isResolving = false

                errorMessage =
                    error.localizedDescription
            }
        }
    }

    private func paste() {

        guard let string =
            UIPasteboard.general
                .string
        else {
            return
        }

        urlText = string
    }
}

struct FetchURLInputSheet:
    View
{

    @Environment(\.dismiss)
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
                        spacing: 8
                    ) {

                        TextField(
                            String(
                                localized:
                                    "fetchurlviews_paste_url"
                            ),
                            text:
                                $urlText
                        )
                        .textInputAutocapitalization(
                            .never
                        )
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                        if !urlText.isEmpty {

                            Button {

                                urlText = ""

                            } label: {

                                Image(
                                    systemName:
                                        "xmark.circle.fill"
                                )
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {

                            paste()

                        } label: {

                            Image(
                                systemName:
                                    "doc.on.clipboard"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {

                        resolve()

                    } label: {

                        HStack {

                            Spacer()

                            if isResolving {

                                ProgressView()
                                    .controlSize(.small)

                                Text(
                                    "fetchurlviews_loading"
                                )

                            } else {

                                Label(
                                    "fetchurlviews_fetch_url",
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
                        "fetchurlviews_url"
                    )

                } footer: {

                    Text(
                        "fetchurlviews_sheet_footer"
                    )
                }
            }

            .navigationTitle(
                "fetchurlviews_fetch_url"
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
                        "fetchurlviews_done"
                    ) {

                        dismiss()
                    }
                }
            }

            .navigationDestination(
                isPresented:
                    Binding(
                        get: {
                            resolved != nil
                        },
                        set: { isPresented in

                            if !isPresented {
                                resolved = nil
                            }
                        }
                    )
            ) {

                if let resolved {

                    FetchURLPreviewView(
                        content: resolved
                    )
                }
            }
        }

        .alert(
            "fetchurlviews_could_not_open_url",
            isPresented:
                Binding(
                    get: {
                        errorMessage != nil
                    },
                    set: { newValue in

                        if !newValue {
                            errorMessage = nil
                        }
                    }
                )
        ) {

            Button(
                "fetchurlviews_ok",
                role: .cancel
            ) {}

        } message: {

            Text(
                errorMessage
                ??
                String(
                    localized:
                        "fetchurlviews_unknown_error"
                )
            )
        }
    }

    private func resolve() {

        guard !isResolving else {
            return
        }

        isResolving = true
        errorMessage = nil

        let input =
            urlText

        Task {

            do {

                let result =
                    try await
                    FetchURLResolver.shared
                        .resolve(input)

                isResolving = false

                await Task.yield()

                resolved = result

            } catch {

                isResolving = false

                errorMessage =
                    error.localizedDescription
            }
        }
    }

    private func paste() {

        guard let string =
            UIPasteboard.general
                .string
        else {
            return
        }

        urlText = string
    }
}

struct FetchURLPreviewView:
    View
{

    let content:
        FetchURLResolvedContent

    @Environment(\.dismiss)
    private var dismiss

    @State private var manager =
        FetchManager.shared

    @State private var isStarting =
        false

    @State private var isTransferring =
        false

    @State private var showDownloadConfirmation =
        false

    @State private var showTransferConfirmation =
        false

    @State private var transferResultMessage:
        String?

    @State private var showTransferResult =
        false

    @State private var showStarted =
        false

    @State private var errorMessage:
        String?

    var body: some View {

        ScrollView {

            VStack(
                spacing: 20
            ) {

                artwork

                VStack(
                    spacing: 5
                ) {

                    Text(
                        content.title
                    )
                    .font(
                        .title2.bold()
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
                        spacing: 5
                    ) {

                        Image(
                            systemName:
                                sourceIcon
                        )

                        Text(
                            content.sourceTitle
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }

                if content.isPlaylist {

                    playlistTracks
                }

                VStack(
                    spacing: 12
                ) {

                    Button {

                        if content.isPlaylist {

                            showDownloadConfirmation =
                                true

                        } else {

                            startDownload()
                        }

                    } label: {

                        HStack {

                            Spacer()

                            if isStarting {

                                ProgressView()
                                    .tint(.white)

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
                    .controlSize(.large)
                    .disabled(isBusy)

                    if canTransferPlaylist {

                        Button {

                            showTransferConfirmation =
                                true

                        } label: {

                            HStack {

                                Spacer()

                                if isTransferring {

                                    ProgressView()

                                } else {

                                    Label(
                                        "fetchurlviews_transfer_to_echo",
                                        systemImage:
                                            "rectangle.stack.badge.plus"
                                    )
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(isBusy)
                    }
                }
            }
            .padding(20)
        }

        .navigationTitle(
            content.isPlaylist
            ?
            "fetchurlviews_playlist"
            :
            "fetchurlviews_song"
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
                    "fetchurlviews_done"
                ) {

                    dismiss()
                }
            }
        }

        .confirmationDialog(
            "fetchurlviews_download_playlist_confirmation",
            isPresented:
                $showDownloadConfirmation,
            titleVisibility:
                .visible
        ) {

            Button(
                downloadButtonTitle
            ) {

                startDownload()
            }

            Button(
                "fetchurlviews_cancel",
                role: .cancel
            ) {}

        } message: {

            Text(
                "fetchurlviews_download_playlist_message"
            )
        }

        .confirmationDialog(
            "fetchurlviews_transfer_confirmation",
            isPresented:
                $showTransferConfirmation,
            titleVisibility:
                .visible
        ) {

            Button(
                "fetchurlviews_transfer_to_echo"
            ) {

                startTransfer()
            }

            Button(
                "fetchurlviews_cancel",
                role: .cancel
            ) {}

        } message: {

            Text(
                "fetchurlviews_transfer_message"
            )
        }

        .alert(
            "fetchurlviews_added_to_fetch",
            isPresented:
                $showStarted
        ) {

            Button(
                "fetchurlviews_done"
            ) {

                dismiss()
            }

            Button(
                "fetchurlviews_view_downloads"
            ) {

                dismiss()

                DispatchQueue.main
                    .async {

                        NotificationCenter
                            .default
                            .post(
                                name:
                                    .echoOpenFetchDownloads,
                                object: nil
                            )
                    }
            }

        } message: {

            if content.isPlaylist {

                Text(
                    String(
                        format:
                            String(
                                localized:
                                    "fetchurlviews_playlist_added_message"
                            ),
                        content.trackCount
                    )
                )

            } else {

                Text(
                    "fetchurlviews_song_added_message"
                )
            }
        }

        .alert(
            "fetchurlviews_download_failed",
            isPresented:
                Binding(
                    get: {
                        errorMessage != nil
                    },
                    set: { value in

                        if !value {
                            errorMessage = nil
                        }
                    }
                )
        ) {

            Button(
                "fetchurlviews_ok",
                role: .cancel
            ) {}

        } message: {

            Text(
                errorMessage
                ??
                String(
                    localized:
                        "fetchurlviews_unknown_error"
                )
            )
        }

        .alert(
            "fetchurlviews_transfer_result",
            isPresented:
                $showTransferResult
        ) {

            Button(
                "fetchurlviews_ok",
                role: .cancel
            ) {}

        } message: {

            Text(
                transferResultMessage
                ??
                ""
            )
        }
    }

    private var artwork:
        some View {

        AsyncImage(
            url:
                content.artworkURL
        ) { image in

            image
                .resizable()
                .scaledToFill()

        } placeholder: {

            RoundedRectangle(
                cornerRadius: 22
            )
            .fill(
                .secondary
                    .opacity(0.12)
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
                    .system(size: 52)
                )
                .foregroundStyle(
                    .secondary
                )
            }
        }
        .frame(
            width: 230,
            height: 230
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22
            )
        )
    }

    @ViewBuilder
    private var playlistTracks:
        some View {

        LazyVStack(
            alignment: .leading,
            spacing: 0
        ) {

            HStack {

                Text(
                    "fetchurlviews_songs"
                )
                .font(.headline)

                Spacer()

                Text(
                    "\(content.trackCount)"
                )
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            ForEach(
                playlistRows
            ) { row in

                HStack(
                    spacing: 10
                ) {

                    AsyncImage(
                        url:
                            row.artworkURL
                    ) { image in

                        image
                            .resizable()
                            .scaledToFill()

                    } placeholder: {

                        RoundedRectangle(
                            cornerRadius: 6
                        )
                        .fill(
                            .secondary
                                .opacity(0.12)
                        )
                    }
                    .frame(
                        width: 42,
                        height: 42
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 6
                        )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {

                        Text(
                            row.title
                        )
                        .lineLimit(1)

                        Text(
                            row.artist
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.vertical, 6)

                Divider()
            }
        }
        .padding(14)
        .background(
            .secondary
                .opacity(0.07),
            in:
                RoundedRectangle(
                    cornerRadius: 16
                )
        )
    }

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
                String(
                    format:
                        String(
                            localized:
                                "fetchurlviews_songs_count"
                        ),
                    tracks.count
                )

        case .youtubeTrack(
            let track
        ):

            return
                track.artist

        case .youtubePlaylist(
            let playlist
        ):

            return
                String(
                    format:
                        String(
                            localized:
                                "fetchurlviews_songs_count"
                        ),
                    playlist.tracks.count
                )
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
                String(
                    format:
                        String(
                            localized:
                                "fetchurlviews_download_songs"
                        ),
                    content.trackCount
                )

        } else {

            return
                String(
                    localized:
                        "fetchurlviews_download"
                )
        }
    }

    private var isBusy:
        Bool {

        isStarting ||
        isTransferring
    }

    private var canTransferPlaylist:
        Bool {

        if case .spotifyPlaylist = content {
            return true
        }

        return false
    }

    private struct PreviewRow:
        Identifiable
    {

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
        [PreviewRow]
    {

        switch content {

        case .spotifyPlaylist(
            _,
            let tracks
        ):

            return tracks.enumerated().map {
                index,
                track in

                PreviewRow(
                    id:
                        "\(index)-\(track.id)",
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

            return playlist.tracks
                .enumerated()
                .map {
                    index,
                    track in

                PreviewRow(
                    id:
                        "\(index)-\(track.id)",
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

    private func startDownload() {

        guard !isStarting else {
            return
        }

        isStarting = true

        Task {

            do {

                switch content {

                case .spotifyTrack(
                    let track
                ):

                    try await
                        addSpotifyTrack(
                            track
                        )

                case .spotifyPlaylist(
                    _,
                    let tracks
                ):

                    await manager
                        .preparePlaylistTracks(
                            tracks
                        )

                case .youtubeTrack(
                    let track
                ):

                    addYouTubeTrack(
                        track
                    )

                case .youtubePlaylist(
                    let playlist
                ):

                    for track
                        in playlist.tracks
                    {

                        addYouTubeTrack(
                            track
                        )
                    }
                }

                showStarted = true

            } catch {

                errorMessage =
                    error.localizedDescription
            }

            isStarting = false
        }
    }

    private func startTransfer() {

        guard !isBusy else {
            return
        }

        guard case .spotifyPlaylist(
            let playlist,
            let tracks
        ) = content,
              !tracks.isEmpty
        else {
            return
        }

        isTransferring = true

        Task {

            let result =
                await SpotifyPlaylistTransferService
                    .transfer(
                        playlist: playlist,
                        tracks: tracks
                    )

            transferResultMessage =
                String(
                    format:
                        String(
                            localized:
                                "fetchurlviews_transfer_started_message"
                        ),
                    result.existingSongCount,
                    result.queuedDownloadCount
                )

            isTransferring = false
            showTransferResult = true

            if result.queuedDownloadCount > 0 {

                NotificationCenter.default
                    .post(
                        name:
                            .echoOpenFetchDownloads,
                        object: nil
                    )
            }
        }
    }

    private func addSpotifyTrack(
        _ track: SpotifyTrack
    ) async throws {

        switch
            ApifySettings.shared
                .downloadMethod
        {

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
                        of: part,
                        with: "",
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
