import SwiftUI

struct FetchQueueView: View {

    @State private var manager =
        FetchManager.shared

    var body: some View {

        List {

            Section {

                HStack(
                    alignment: .top,
                    spacing: 12
                ) {

                    Image(
                        systemName:
                            "exclamationmark.triangle.fill"
                    )
                    .font(.title3)
                    .foregroundStyle(.orange)

                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {

                        Text(
                            "fetchqueueview_keep_echo_open"
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                        Text(
                            "fetchqueueview_keep_echo_open_description"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if manager.items.isEmpty {

                ContentUnavailableView(
                    "fetchqueueview_no_downloads",
                    systemImage:
                        "arrow.down.circle",
                    description:
                        Text(
                            "fetchqueueview_no_downloads_description"
                        )
                )

            } else {

                ForEach(
                    manager.items
                ) { item in

                    FetchItemRow(
                        item: item
                    )
                }
                .onDelete { offsets in

                    for index in offsets {

                        manager.remove(
                            manager.items[index]
                        )
                    }
                }
            }
        }

        .navigationTitle(
            "fetchqueueview_title"
        )

        .toolbar {

            if !manager.items.isEmpty {

                Button(
                    "fetchqueueview_clear"
                ) {

                    manager
                        .clearCompleted()
                }
            }
        }
    }
}

struct FetchItemRow: View {

    let item: FetchItem

    var body: some View {

        HStack(spacing: 12) {

            artwork

            VStack(
                alignment: .leading,
                spacing: 4
            ) {

                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(item.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                statusView
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var artwork:
        some View {

        if let artworkURL =
            item.artworkURL {

            AsyncImage(
                url: artworkURL
            ) { image in

                image
                    .resizable()
                    .scaledToFill()

            } placeholder: {

                Color.secondary
                    .opacity(0.15)
            }
            .frame(
                width: 52,
                height: 52
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 8
                )
            )

        } else {

            Image(
                systemName:
                    "music.note"
            )
            .frame(
                width: 52,
                height: 52
            )
            .background(
                .secondary
                    .opacity(0.12),
                in:
                    RoundedRectangle(
                        cornerRadius: 8
                    )
            )
        }
    }

    @ViewBuilder
    private var statusView:
        some View {

        switch item.status {

        case .queued:

            Text(
                "fetchqueueview_queued"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

        case .preparing(
            let progress
        ):

            activeProgress(
                title:
                    String(
                        localized:
                            "fetchqueueview_preparing"
                    ),
                progress:
                    progress
            )

        case .downloading(
            let progress
        ):

            activeProgress(
                title:
                    String(
                        localized:
                            "fetchqueueview_downloading"
                    ),
                progress:
                    progress
            )

        case .processing(
            let progress
        ):

            activeProgress(
                title:
                    String(
                        localized:
                            "fetchqueueview_encoding_mp3"
                    ),
                progress:
                    progress
            )

        case .completed:

            Label(
                "fetchqueueview_completed",
                systemImage:
                    "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.green)

        case .failed(
            let message
        ):

            VStack(
                alignment: .leading,
                spacing: 2
            ) {

                Label(
                    "fetchqueueview_download_failed",
                    systemImage:
                        "exclamationmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)

                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func activeProgress(
        title: String,
        progress: Double
    ) -> some View {

        let safeProgress =
            min(
                max(
                    progress,
                    0
                ),
                1
            )

        return VStack(
            alignment: .leading,
            spacing: 3
        ) {

            HStack {

                Text(title)

                Spacer()

                Text(
                    "\(Int(safeProgress * 100))%"
                )
                .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ProgressView(
                value: safeProgress
            )
        }
    }
}
