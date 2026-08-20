import SwiftUI

struct YouTubeResultView: View {

    let track: SpotifyTrack
    let result: YouTubeSearchResult

    @State private var hasPermission = false

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
                    /*
                     Hier koppelen we straks de
                     daadwerkelijke toegestane bron/import.
                    */
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
    }
}
