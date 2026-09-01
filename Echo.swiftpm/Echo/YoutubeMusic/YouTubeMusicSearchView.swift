import SwiftUI

struct YouTubeMusicSearchView:
    View
{

    @State private var query =
        ""

    @State private var results:
        [YouTubeSearchResult] = []

    @State private var loading =
        false

    @State private var errorMessage:
        String?

    @State private var selectedResult:
        YouTubeSearchResult?

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
                    .foregroundStyle(.secondary)

                    TextField(
                        String(
                            localized:
                                "youtubemusicsearchview_placeholder"
                        ),
                        text:
                            $query
                    )
                    .textInputAutocapitalization(
                        .never
                    )
                    .autocorrectionDisabled()
                    .submitLabel(.search)
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
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if
                results.isEmpty,
                !loading,
                errorMessage == nil
            {

                Section {

                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {

                        Label(
                            "youtubemusicsearchview_youtube_music",
                            systemImage:
                                "music.note"
                        )
                        .font(.headline)

                        Text(
                            "youtubemusicsearchview_intro_description"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if loading {

                Section {

                    HStack {

                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }

            if let errorMessage {

                Section {

                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            if !results.isEmpty {

                Section(
                    "youtubemusicsearchview_songs"
                ) {

                    ForEach(
                        results
                    ) { result in

                        Button {

                            selectedResult =
                                result

                        } label: {

                            HStack(
                                spacing: 12
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
                                        cornerRadius: 8
                                    )
                                    .fill(
                                        .secondary
                                            .opacity(0.12)
                                    )
                                }
                                .frame(
                                    width: 64,
                                    height: 64
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 8
                                    )
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 4
                                ) {

                                    Text(
                                        result.title
                                    )
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                    Text(
                                        result.channelTitle
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }

                                Spacer()

                                Image(
                                    systemName:
                                        "chevron.right"
                                )
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        .navigationTitle(
            "youtubemusicsearchview_title"
        )

        .navigationBarTitleDisplayMode(
            .inline
        )

        .sheet(
            item:
                $selectedResult
        ) { result in

            YouTubeMusicResultView(
                result:
                    result,

                onClose: {

                    selectedResult =
                        nil
                },

                onViewDownloads: {

                    selectedResult =
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

        loading = true
        errorMessage = nil

        do {

            results =
                try await
                YouTubeAPI.shared
                    .searchMusic(
                        query:
                            text,
                        maxResults:
                            25
                    )

            if results.isEmpty {

                errorMessage =
                    String(
                        localized:
                            "youtubemusicsearchview_no_music_found"
                    )
            }

        } catch {

            results = []

            errorMessage =
                error.localizedDescription
        }

        loading = false
    }
}
