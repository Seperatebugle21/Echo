import SwiftUI

struct YouTubeSearchView: View {

    let track: SpotifyTrack

    @State private var results: [YouTubeSearchResult] = []
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {

        List {

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.headline)

                    Text(track.artist)
                        .foregroundStyle(.secondary)
                }
            }

            Section("YouTube Results") {

                if loading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                ForEach(results) { result in

                    NavigationLink {
                        YouTubeResultView(
                            track: track,
                            result: result
                        )
                    } label: {

                        HStack(spacing: 12) {

                            AsyncImage(
                                url: result.thumbnailURL
                            ) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Color.secondary.opacity(0.15)
                            }
                            .frame(
                                width: 90,
                                height: 52
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 7
                                )
                            )

                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {

                                Text(result.title)
                                    .lineLimit(2)

                                Text(result.channelTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Find Audio")
        .task {
            await search()
        }
    }

    private func search() async {

        loading = true
        errorMessage = nil

        do {

            results = try await YouTubeAPI.shared.search(
                title: track.name,
                artist: track.artist
            )

        } catch {

            errorMessage =
                error.localizedDescription
        }

        loading = false
    }
}
