import SwiftUI

struct SpotifyTrackDetailView: View {

    let track: SpotifyTrack

    let onClose: () -> Void
    let onViewDownloads: () -> Void

    @State private var fetch =
        FetchManager.shared

    @State private var method =
        ApifySettings.shared

    @State private var showDownloadStatus =
        false

    @State private var downloadItemID:
        UUID?

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(
                    spacing: 24
                ) {

                    artwork

                    VStack(
                        spacing: 6
                    ) {

                        Text(track.name)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text(track.artist)
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text(track.album)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Divider()

                    VStack(
                        spacing: 14
                    ) {

                        informationRow(
                            title:
                                String(
                                    localized:
                                        "spotifytrackdetailview_artist"
                                ),
                            value:
                                track.artist
                        )

                        informationRow(
                            title:
                                String(
                                    localized:
                                        "spotifytrackdetailview_album"
                                ),
                            value:
                                track.album
                        )

                        informationRow(
                            title:
                                String(
                                    localized:
                                        "spotifytrackdetailview_duration"
                                ),
                            value:
                                durationText
                        )

                        informationRow(
                            title:
                                String(
                                    localized:
                                        "spotifytrackdetailview_method"
                                ),
                            value:
                                method
                                    .downloadMethod
                                    .title
                        )
                    }

                    Spacer(
                        minLength: 10
                    )

                    downloadButton
                }
                .padding(24)
            }

            .navigationTitle(
                "spotifytrackdetailview_song"
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
                        "spotifytrackdetailview_done"
                    ) {

                        onClose()
                    }
                }
            }
        }

        .sheet(
            isPresented:
                $showDownloadStatus
        ) {

            DownloadStartedSheet(

                track:
                    track,

                item:
                    currentDownloadItem,

                onOK: {

                    showDownloadStatus =
                        false

                    onClose()
                },

                onViewDownloads: {

                    showDownloadStatus =
                        false

                    onViewDownloads()
                }
            )
            .presentationDetents(
                [
                    .height(330)
                ]
            )
            .presentationDragIndicator(
                .visible
            )
        }
    }

    private var artwork:
        some View {

        AsyncImage(
            url:
                track.artworkURL
        ) { image in

            image
                .resizable()
                .scaledToFill()

        } placeholder: {

            RoundedRectangle(
                cornerRadius: 22
            )
            .fill(
                .secondary.opacity(
                    0.12
                )
            )
            .overlay {

                Image(
                    systemName:
                        "music.note"
                )
                .font(
                    .system(
                        size: 50
                    )
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
        .shadow(
            radius: 10,
            y: 5
        )
    }

    @ViewBuilder
    private var downloadButton:
        some View {

        switch method.downloadMethod {

        case .spotify:

            Button {

                startYTDLPDownload()

            } label: {

                Label(
                    "spotifytrackdetailview_download",
                    systemImage:
                        "arrow.down.circle.fill"
                )
                .font(.headline)
                .frame(
                    maxWidth: .infinity
                )
                .padding(.vertical, 5)
            }
            .buttonStyle(
                .borderedProminent
            )
            .controlSize(.large)

        case .youtube:

            NavigationLink {

                YouTubeSearchView(
                    track: track
                )

            } label: {

                Label(
                    "spotifytrackdetailview_download",
                    systemImage:
                        "arrow.down.circle.fill"
                )
                .font(.headline)
                .frame(
                    maxWidth: .infinity
                )
                .padding(.vertical, 5)
            }
            .buttonStyle(
                .borderedProminent
            )
            .controlSize(.large)
        }
    }

    private func startYTDLPDownload() {

        let existingIDs =
            Set(
                fetch.items.map {
                    $0.id
                }
            )

        fetch
            .addAuthorizedSpotifyTrack(
                track
            )

        if let newItem =
            fetch.items.last(
                where: {

                    !existingIDs
                        .contains(
                            $0.id
                        )
                }
            )
        {

            downloadItemID =
                newItem.id
        }

        showDownloadStatus =
            true
    }

    private var currentDownloadItem:
        FetchItem?
    {

        guard let downloadItemID else {
            return nil
        }

        return fetch.items.first {

            $0.id ==
                downloadItemID
        }
    }

    private func informationRow(
        title: String,
        value: String
    ) -> some View {

        HStack {

            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.subheadline)
    }

    private var durationText:
        String {

        let seconds =
            track.durationMS
            /
            1000

        let minutes =
            seconds
            /
            60

        let remaining =
            seconds
            %
            60

        return String(
            format:
                "%d:%02d",
            minutes,
            remaining
        )
    }
}

private struct DownloadStartedSheet: View {

    let track:
        SpotifyTrack

    let item:
        FetchItem?

    let onOK:
        () -> Void

    let onViewDownloads:
        () -> Void

    var body: some View {

        VStack(
            spacing: 20
        ) {

            Image(
                systemName:
                    statusIcon
            )
            .font(
                .system(
                    size: 42
                )
            )
            .foregroundStyle(
                statusColor
            )

            VStack(
                spacing: 5
            ) {

                Text(
                    statusTitle
                )
                .font(.title2.bold())

                Text(
                    track.name
                )
                .font(.headline)
                .lineLimit(1)

                Text(
                    track.artist
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Label(
                "spotifytrackdetailview_keep_open",
                systemImage:
                    "iphone"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if let progress =
                item?
                    .status
                    .progress
            {

                VStack(
                    spacing: 6
                ) {

                    HStack {

                        Text(
                            item?.status.title
                            ??
                            String(
                                localized:
                                    "spotifytrackdetailview_downloading"
                            )
                        )

                        Spacer()

                        Text(
                            "\(Int(progress * 100))%"
                        )
                        .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ProgressView(
                        value:
                            progress
                    )
                }

            } else {

                switch item?.status {

                case .completed:

                    Text(
                        "spotifytrackdetailview_added_to_echo"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                case .failed(let message):

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)

                default:

                    HStack(
                        spacing: 8
                    ) {

                        ProgressView()

                        Text(
                            "spotifytrackdetailview_starting_download"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(
                spacing: 12
            ) {

                Button {

                    onOK()

                } label: {

                    Text(
                        "spotifytrackdetailview_ok"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(.bordered)

                Button {

                    onViewDownloads()

                } label: {

                    Text(
                        "spotifytrackdetailview_view_downloads"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
            }
        }
        .padding(24)
    }

    private var statusTitle:
        String {

        switch item?.status {

        case .completed:

            return String(
                localized:
                    "spotifytrackdetailview_downloaded"
            )

        case .failed:

            return String(
                localized:
                    "spotifytrackdetailview_download_failed"
            )

        default:

            return String(
                localized:
                    "spotifytrackdetailview_downloading"
            )
        }
    }

    private var statusIcon:
        String {

        switch item?.status {

        case .completed:
            return "checkmark.circle.fill"

        case .failed:
            return "exclamationmark.circle.fill"

        default:
            return "arrow.down.circle.fill"
        }
    }

    private var statusColor:
        Color {

        switch item?.status {

        case .completed:
            return .green

        case .failed:
            return .red

        default:
            return .accentColor
        }
    }
}
