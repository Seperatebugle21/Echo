import SwiftUI

struct MusicBrainzSearchView:
    View
{

    @State private var query =
        ""

    @State private var results:
        [MusicBrainzTrack] = []

    @State private var isLoading =
        false

    @State private var errorMessage:
        String?

    @State private var selectedTrack:
        MusicBrainzTrack?

    var body: some View {

        List {

            Section {

                HStack(
                    spacing: 10
                ) {

                    Image(
                        systemName:
                            "magnifyingglass"
                    )
                    .foregroundStyle(
                        .secondary
                    )

                    TextField(
                        String(
                            localized:
                                "musicbrainzsearchview_placeholder"
                        ),
                        text:
                            $query
                    )
                    .textInputAutocapitalization(
                        .never
                    )
                    .autocorrectionDisabled()
                    .submitLabel(
                        .search
                    )
                    .onSubmit {

                        Task {

                            await search()
                        }
                    }

                    if !query.isEmpty {

                        Button {

                            query = ""
                            results = []
                            errorMessage = nil

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
                }
            }

            if
                results.isEmpty,
                !isLoading,
                errorMessage == nil
            {

                Section {

                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {

                        Label(
                            "musicbrainzsearchview_search_without_spotify",
                            systemImage:
                                "magnifyingglass"
                        )
                        .font(.headline)

                        Text(
                            "musicbrainzsearchview_intro_description"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                }
            }

            if isLoading {

                Section {

                    HStack(
                        spacing: 10
                    ) {

                        Spacer()

                        ProgressView()

                        Text(
                            "musicbrainzsearchview_searching"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        Spacer()
                    }
                }
            }

            if let errorMessage {

                Section {

                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {

                        Label(
                            "musicbrainzsearchview_search_failed",
                            systemImage:
                                "exclamationmark.triangle"
                        )
                        .font(.headline)

                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(
                            "musicbrainzsearchview_try_again"
                        ) {

                            Task {

                                await search()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !results.isEmpty {

                Section(
                    "musicbrainzsearchview_songs"
                ) {

                    ForEach(
                        results
                    ) { track in

                        Button {

                            selectedTrack =
                                track

                        } label: {

                            MusicBrainzTrackRow(
                                track: track
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        .navigationTitle(
            "musicbrainzsearchview_title"
        )

        .navigationBarTitleDisplayMode(
            .inline
        )

        .sheet(
            item:
                $selectedTrack
        ) { track in

            SpotifyTrackDetailView(

                track:
                    track.echoTrack,

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

            results = []
            return
        }

        isLoading = true
        errorMessage = nil

        do {

            results =
                try await
                MusicBrainzAPI.shared
                    .searchTracks(
                        query:
                            text,
                        limit:
                            30
                    )

            if results.isEmpty {

                errorMessage =
                    String(
                        format:
                            String(
                                localized:
                                    "musicbrainzsearchview_no_results_for_query"
                            ),
                        text
                    )
            }

        } catch {

            results = []

            errorMessage =
                error.localizedDescription
        }

        isLoading = false
    }
}

private struct MusicBrainzTrackRow:
    View
{

    let track:
        MusicBrainzTrack

    var body: some View {

        HStack(
            spacing: 12
        ) {

            artwork

            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text(
                    track.title
                )
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

                Text(
                    track.artist
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                HStack(
                    spacing: 6
                ) {

                    if track.album !=
                        "Unknown Album"
                    {

                        Text(
                            track.album
                        )
                        .lineLimit(1)
                    }

                    if track.durationMS > 0 {

                        if track.album !=
                            "Unknown Album"
                        {

                            Text("•")
                        }

                        Text(
                            durationText
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .contentShape(
            Rectangle()
        )
        .padding(.vertical, 3)
    }

    private var artwork:
        some View
    {

        AsyncImage(
            url:
                track.artworkURL
        ) { image in

            image
                .resizable()
                .scaledToFill()

        } placeholder: {

            RoundedRectangle(
                cornerRadius: 8
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
                .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: 54,
            height: 54
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 8
            )
        )
    }

    private var durationText:
        String
    {

        let totalSeconds =
            track.durationMS
            /
            1000

        let minutes =
            totalSeconds
            /
            60

        let seconds =
            totalSeconds
            %
            60

        return String(
            format:
                "%d:%02d",
            minutes,
            seconds
        )
    }
}
