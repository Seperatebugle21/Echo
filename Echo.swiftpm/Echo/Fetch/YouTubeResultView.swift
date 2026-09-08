import SwiftUI

struct YouTubeResultView: View {

    let track: SpotifyTrack
    let result: YouTubeSearchResult

    @State private var hasPermission =
        false

    @State private var showAddedConfirmation =
        false

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

            Section(
                "youtuberesultview_permission"
            ) {

                Toggle(
                    "youtuberesultview_permission_toggle",
                    isOn: $hasPermission
                )
            }

            Section {

                Button {

                    FetchManager.shared
                        .addAuthorizedMatch(
                            track: track,
                            youtubeResult:
                                result
                        )

                    showAddedConfirmation =
                        true

                } label: {

                    Label(
                        "youtuberesultview_fetch_to_echo",
                        systemImage:
                            "arrow.down.circle.fill"
                    )
                }
                .disabled(!hasPermission)
            }
        }

        .navigationTitle(
            "youtuberesultview_title"
        )

        .sheet(
            isPresented:
                $showAddedConfirmation
        ) {

            NavigationStack {

                AddedToQueueView(
                    track: track
                )
            }
            .presentationDetents([
                .height(260)
            ])
        }
    }
}
