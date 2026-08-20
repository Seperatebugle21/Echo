import SwiftUI

struct FetchView: View {

    @State private var manager = FetchManager.shared
    @State private var settings = FetchSettings.shared
    @State private var spotifyLink = ""

    var body: some View {
        NavigationStack {
            List {

                Section("Spotify") {

    if SpotifyManager.shared.isConnected {

        Label(
            "Connected to Spotify",
            systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(.green)

    } else {

        Button {
            SpotifyManager.shared.connect()
        } label: {
            Label(
                "Connect Spotify",
                systemImage: "person.crop.circle.badge.plus"
            )
        }
    }
}

                Section {
                    HStack {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)

                        TextField(
                            "Spotify link",
                            text: $spotifyLink
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            addLink()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .disabled(
                            spotifyLink
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Add to Fetch")
                }

                Section {
                    NavigationLink {
                        FetchQueueView()
                    } label: {
                        Label(
                            "Downloads",
                            systemImage: "arrow.down.circle"
                        )

                        Spacer()

                        Text("\(manager.items.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Settings") {

                    Picker(
                        "Quality",
                        selection: $settings.quality
                    ) {
                        ForEach(FetchQuality.allCases) { quality in
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

                if !manager.items.isEmpty {
                    Section("Recent") {
                        ForEach(
                            manager.items.prefix(5)
                        ) { item in
                            FetchItemRow(item: item)
                        }
                    }
                }
            }
            .navigationTitle("Fetch")
        }
    }

    private func addLink() {
        let link = spotifyLink
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !link.isEmpty else { return }

        manager.addSpotifyURL(link)
        spotifyLink = ""
    }
}
