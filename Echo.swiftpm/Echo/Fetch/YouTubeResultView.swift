import SwiftUI

struct YouTubeResultView: View {

    let track: SpotifyTrack
    let result: YouTubeSearchResult

    @State private var hasPermission = false

    @State private var showAddedConfirmation = false

    var body: some View {

        Form {

            Section {

                AsyncImage(
                    url: result.thumbnailURL
                ) { image in

                    image
                        .resizable()
                        .scaledToFit()

                } placeholder: {

                    ProgressView()
                }

                Text(result.title)
                    .font(.headline)

                Text(result.channelTitle)
                    .foregroundStyle(.secondary)
            }

            Section("Permission") {

                Toggle(
                    "I have permission to download this audio",
                    isOn: $hasPermission
                )
            }

            Section {

                Button {
                       FetchManager.shared.addAuthorizedMatch(
        track: track,
        youtubeResult: result
    )

    showAddedConfirmation = true
                } label: {

                    Label(
                        "Fetch to Echo",
                        systemImage: "arrow.down.circle.fill"
                    )
                }
                .disabled(!hasPermission)
            }
        }
        .navigationTitle("Fetch")
        .sheet(
    isPresented: $showAddedConfirmation
) {

    AddedToQueueView(
        track: track
    )
    .presentationDetents([
        .height(260)
    ])
    .presentationDragIndicator(.visible)
}
    }
}
