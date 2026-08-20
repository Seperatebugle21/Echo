import SwiftUI

struct SpotifyFetchButton: View {

    let track: SpotifyTrack

    @State private var showPermission = false
    @State private var showAdded = false

    var body: some View {

        Group {

            switch ApifySettings.shared.downloadMethod {

            // MARK: - YouTube

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


            // MARK: - Spotify

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
            }
        }

        // MARK: Permission

        .confirmationDialog(
            "Fetch from Spotify?",
            isPresented:
                $showPermission,
            titleVisibility:
                .visible
        ) {

            Button(
                "I have permission — Add to Queue"
            ) {

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
                "Only continue if you own this content or have permission to download it."
            )
        }


        // MARK: Added

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
                "\(track.name) by \(track.artist) was added to Downloads."
            )
        }
    }
}
