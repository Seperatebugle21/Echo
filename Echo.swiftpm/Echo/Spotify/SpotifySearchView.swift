import SwiftUI

struct SpotifySearchView: View {

    @State private var query =
        ""

    @State private var results:
        [SpotifyTrack] = []

    @State private var isLoading =
        false

    @State private var errorMessage:
        String?

    @State private var selectedTrack:
        SpotifyTrack?

    var body: some View {

        List {

            if isLoading {

                HStack {

                    Spacer()

                    ProgressView()

                    Spacer()
                }
            }

            if let errorMessage {

                Text(
                    errorMessage
                )
                .foregroundStyle(
                    .red
                )
                .font(
                    .caption
                )
            }

            ForEach(
                results
            ) { track in

                Button {

                    selectedTrack =
                        track

                } label: {

                    SpotifyTrackRow(
                        track:
                            track
                    )
                    .frame(
                        maxWidth:
                            .infinity,
                        alignment:
                            .leading
                    )
                    .contentShape(
                        Rectangle()
                    )
                }
                .buttonStyle(
                    .plain
                )
            }
        }

        .navigationTitle(
            "spotifysearchview_title"
        )

        .searchable(
            text:
                $query,
            prompt:
                "spotifysearchview_search_songs"
        )

        .onSubmit(
            of:
                .search
        ) {

            Task {

                await search()
            }
        }

        .sheet(
            item:
                $selectedTrack
        ) { track in

            SpotifyTrackDetailView(

                track:
                    track,

                onClose: {

                    selectedTrack =
                        nil
                },

                onViewDownloads: {

                    selectedTrack =
                        nil

                    DispatchQueue.main.async {

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
            )
        }
    }

    private func search()
        async
    {

        let text =
            query
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard !text.isEmpty else {
            return
        }

        isLoading =
            true

        errorMessage =
            nil

        do {

            results =
                try await
                SpotifyAPI.shared
                    .searchTracks(
                        query:
                            text
                    )

        } catch {

            errorMessage =
                error
                    .localizedDescription
        }

        isLoading =
            false
    }
}
