import SwiftUI

struct AddedToQueueView: View {

    let track: SpotifyTrack

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {

        VStack(spacing: 18) {

            Image(
                systemName:
                    "checkmark.circle.fill"
            )
            .font(.system(size: 46))
            .foregroundStyle(.green)

            VStack(spacing: 5) {

                Text(
                    "addedtoqueueview_added_to_queue"
                )
                .font(.title2.bold())

                Text(track.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {

                Button {
                    dismiss()
                } label: {

                    Text(
                        "addedtoqueueview_close"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(.bordered)

                NavigationLink {

                    FetchQueueView()

                } label: {

                    Text(
                        "addedtoqueueview_view_downloads"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
            }
        }
        .padding()
    }
}
