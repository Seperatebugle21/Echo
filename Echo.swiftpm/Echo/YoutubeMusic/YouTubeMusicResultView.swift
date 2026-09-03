import SwiftUI

struct YouTubeMusicResultView:
    View
{
    let result:
        YouTubeMusicTrack

    let onClose:
        () -> Void

    let onViewDownloads:
        () -> Void

    @State private var fetch =
        FetchManager.shared

    @State private var showStarted =
        false

    var body: some View {

        NavigationStack {

            VStack(
                spacing: 22
            ) {

                AsyncImage(
                    url:
                        result.thumbnailURL
                ) { image in

                    image
                        .resizable()
                        .scaledToFill()

                } placeholder: {

                    RoundedRectangle(
                        cornerRadius: 20
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
                                size: 48
                            )
                        )
                    }
                }
                .frame(
                    width: 230,
                    height: 230
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20
                    )
                )

                VStack(
                    spacing: 6
                ) {

                    Text(
                        result.title
                    )
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                    Text(
                        result.artist
                    )
                    .foregroundStyle(.secondary)

                    if let album =
                        result.album,
                       !album.isEmpty
                    {
                        Text(album)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }

                    if let duration =
                        result.duration
                    {
                        Text(duration)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Button {

                    download()

                } label: {

                    Label(
                        "youtubemusicresultview_download",
                        systemImage:
                            "arrow.down.circle.fill"
                    )
                    .font(.headline)
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .controlSize(.large)
            }
            .padding(24)

            .navigationTitle(
                "youtubemusicresultview_song"
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
                        "youtubemusicresultview_done"
                    ) {

                        onClose()
                    }
                }
            }
        }

        .alert(
            "youtubemusicresultview_download_started",
            isPresented:
                $showStarted
        ) {

            Button(
                "youtubemusicresultview_ok"
            ) {

                onClose()
            }

            Button(
                "youtubemusicresultview_view_downloads"
            ) {

                onViewDownloads()
            }

        } message: {

            Text(
                "youtubemusicresultview_added_to_queue"
            )
        }
    }

    private func download() {

        let item =
            FetchItem(
                spotifyURL:
                    result.videoURL,

                title:
                    result.title,

                artist:
                    result.artist,

                album:
                    result.album,

                artworkURL:
                    result.thumbnailURL,

                youtubeURL:
                    result.videoURL,

                permissionConfirmed:
                    true
            )

        fetch.addPreparedItem(
            item
        )

        showStarted =
            true
    }
}
