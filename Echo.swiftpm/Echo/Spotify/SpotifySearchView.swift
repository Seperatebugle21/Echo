import SwiftUI

struct SpotifySearchView: View {

    @State private var query = ""
    @State private var results: [SpotifyTrack] = []

    @State private var isLoading = false
    @State private var errorMessage: String?

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

                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            ForEach(results) { track in

                NavigationLink {
                   SpotifyFetchButton(
                    track: track
                    )
                } label: {

                    HStack(spacing: 12) {

                        AsyncImage(
                            url: track.artworkURL
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


                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {

                            Text(track.name)
                                .font(.headline)
                                .lineLimit(1)

                            Text(track.artist)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text(track.album)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle("Search Spotify")
        .searchable(
            text: $query,
            prompt: "Search songs"
        )
        .onSubmit(of: .search) {
            Task {
                await search()
            }
        }
    }


    private func search() async {

        let text =
            query.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !text.isEmpty else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {

            results =
                try await SpotifyAPI.shared
                    .searchTracks(
                        query: text
                    )

        } catch {

            errorMessage =
                error.localizedDescription
        }

        isLoading = false
    }
}
