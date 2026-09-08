import SwiftUI

struct SpotifyFetchButton: View {

    let track: SpotifyTrack

    @State private var showPermission = false
    @State private var showAdded = false

    var body: some View {

        switch ApifySettings.shared.downloadMethod {

        case .youtube:

            NavigationLink {

                YouTubeSearchView(
                    track: track
                )

            } label: {

                Label(
                    "Fetch to Echo",
                    systemImage:
                        "arrow.down.circle"
                )
            }


        case .spotify:

            Button {

                showPermission = true

            } label: {

                Label(
                    "Fetch to Echo",
                    systemImage:
                        "arrow.down.circle"
                )
            }

            .confirmationDialog(
                "Fetch from Spotify",
                isPresented:
                    $showPermission,
                titleVisibility:
                    .visible
            ) {

                Button(
                    "Add to Queue"
                ) {

                    print(
                        "Spotify Fetch pressed:",
                        track.name
                    )

                    FetchManager.shared
                        .addAuthorizedSpotifyTrack(
                            track
                        )

                    showAdded = true
                }

                Button(
                    "Cancel",
                    role: .cancel
                ) {}

            } message: {

                Text(
                    "Continue only for content you own or have permission to download."
                )
            }

            .alert(
                "Added to Queue",
                isPresented:
                    $showAdded
            ) {

                Button(
                    "Close",
                    role: .cancel
                ) {}

            } message: {

                Text(
                    "\(track.name) has been added to Downloads."
                )
            }
        }
    }
}
