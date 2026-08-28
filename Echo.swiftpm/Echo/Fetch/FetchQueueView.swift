import SwiftUI


struct FetchQueueView: View {

    @State private var manager =
        FetchManager.shared


    var body: some View {

        List {

            if manager.items.isEmpty {

                ContentUnavailableView(
                    "No Downloads",
                    systemImage:
                        "arrow.down.circle",
                    description:
                        Text(
                            "Add a Spotify track, album or playlist."
                        )
                )

            } else {

                ForEach(
                    manager.items
                ) {
                    item in

                    FetchItemRow(
                        item:
                            item
                    )
                }
                .onDelete {
                    offsets in

                    for index in offsets {

                        manager.remove(
                            manager.items[
                                index
                            ]
                        )
                    }
                }
            }
        }
        .navigationTitle(
            "Downloads"
        )
        .toolbar {

            if !manager.items.isEmpty {

                Button(
                    "Clear"
                ) {

                    manager
                        .clearCompleted()
                }
            }
        }
    }
}


struct FetchItemRow: View {

    let item:
        FetchItem


    var body: some View {

        HStack(
            spacing:
                12
        ) {

            artwork


            VStack(
                alignment:
                    .leading,
                spacing:
                    4
            ) {

                Text(
                    item.title
                )
                .font(
                    .headline
                )
                .lineLimit(
                    1
                )


                Text(
                    item.artist
                )
                .font(
                    .subheadline
                )
                .foregroundStyle(
                    .secondary
                )
                .lineLimit(
                    1
                )


                statusView
            }


            Spacer()
        }
        .padding(
            .vertical,
            4
        )
    }


    // MARK: - Artwork

    @ViewBuilder
    private var artwork:
        some View {

        if let artworkURL =
            item.artworkURL {

            AsyncImage(
                url:
                    artworkURL
            ) {
                image in

                image
                    .resizable()
                    .scaledToFill()

            } placeholder: {

                Color.secondary
                    .opacity(
                        0.15
                    )
            }
            .frame(
                width:
                    52,
                height:
                    52
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius:
                        8
                )
            )

        } else {

            Image(
                systemName:
                    "music.note"
            )
            .frame(
                width:
                    52,
                height:
                    52
            )
            .background(
                .secondary
                    .opacity(
                        0.12
                    ),
                in:
                    RoundedRectangle(
                        cornerRadius:
                            8
                    )
            )
        }
    }


    // MARK: - Status

    @ViewBuilder
    private var statusView:
        some View {

        switch item.status {

        case .queued:

            Text(
                "Queued"
            )
            .font(
                .caption
            )
            .foregroundStyle(
                .secondary
            )


        case .preparing(let progress):

            activeProgress(
                title:
                    "Preparing",
                progress:
                    progress
            )


        case .downloading(let progress):

            activeProgress(
                title:
                    "Downloading",
                progress:
                    progress
            )


        case .processing(let progress):

            activeProgress(
                title:
                    "Encoding MP3",
                progress:
                    progress
            )


        case .completed:

            Label(
                "Completed",
                systemImage:
                    "checkmark.circle.fill"
            )
            .font(
                .caption
            )
            .foregroundStyle(
                .green
            )


        case .failed(let message):

            Text(
                message
            )
            .font(
                .caption
            )
            .foregroundStyle(
                .red
            )
            .lineLimit(
                2
            )
        }
    }


    private func activeProgress(
        title: String,
        progress: Double
    ) -> some View {

        VStack(
            alignment:
                .leading,
            spacing:
                3
        ) {

            HStack {

                Text(
                    title
                )


                Spacer()


                Text(
                    "\(Int(progress * 100))%"
                )
                .monospacedDigit()
            }
            .font(
                .caption
            )
            .foregroundStyle(
                .secondary
            )


            ProgressView(
                value:
                    progress
            )
        }
    }
}
