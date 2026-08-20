import SwiftUI

struct FetchView: View {

    @State private var manager = FetchManager.shared
    @State private var settings = FetchSettings.shared
    @State private var spotify = SpotifyManager.shared

    @State private var spotifyLink = ""

    var body: some View {

        NavigationStack {

            List {

                // MARK: - Spotify

                Section("Spotify") {

                    if spotify.isConnected {

                        Label(
                            "Connected to Spotify",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)

                    } else {

                        Button {
                            spotify.connect()
                        } label: {
                            Label(
                                "Connect Spotify",
                                systemImage: "person.crop.circle.badge.plus"
                            )
                        }
                    }
                }


                // MARK: - Add Link

                Section {
                    HStack(spacing: 12) {

                        Image(systemName: "link")
                            .foregroundStyle(.secondary)

                        TextField(
                            "Spotify link",
                            text: $spotifyLink
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        if !spotifyLink.isEmpty {

                            Button {
                                spotifyLink = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            addLink()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .disabled(
                            spotifyLink
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                        )
                    }
                    .padding(.vertical, 4)

                } header: {
                    Text("Add to Fetch")

                } footer: {
                    Text(
                        "Paste a Spotify track, album or playlist link."
                    )
                }


                // MARK: - Downloads

                Section {

                    NavigationLink {
                        FetchQueueView()
                    } label: {

                        HStack {

                            Label(
                                "Downloads",
                                systemImage: "arrow.down.circle"
                            )

                            Spacer()

                            Text("\(manager.items.count)")
                                .foregroundStyle(.secondary)
                        }
                    }

                }


                // MARK: - Settings

                Section("Settings") {

                    Picker(
                        "Quality",
                        selection: $settings.quality
                    ) {

                        ForEach(
                            FetchQuality.allCases
                        ) { quality in

                            Text(quality.title)
                                .tag(quality)
                        }
                    }


                    Toggle(
                        "Artwork",
                        isOn: $settings.embedArtwork
                    )


                    Toggle(
                        "Metadata",
                        isOn: $settings.embedMetadata
                    )
                }


                // MARK: - Recent

                if !manager.items.isEmpty {

                    Section("Recent") {

                        ForEach(
                            Array(
                                manager.items
                                    .reversed()
                                    .prefix(5)
                            )
                        ) { item in

                            FetchItemRow(
                                item: item
                            )
                        }
                    }
                }
            }
            .navigationTitle("Fetch")
        }
    }


    // MARK: - Add Spotify Link

    private func addLink() {

        let link = spotifyLink
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !link.isEmpty else {
            return
        }

        manager.addSpotifyURL(link)

        spotifyLink = ""
    }
}
