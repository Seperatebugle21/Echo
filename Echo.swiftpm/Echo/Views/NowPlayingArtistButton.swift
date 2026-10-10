import SwiftUI

/// Own artist presentation here so playback progress does not rebuild its navigation state.
struct NowPlayingArtistButton: View {
    let song: Song
    @Environment(MusicLibraryManager.self) private var library
    @State private var selectedArtist: ArtistGroup?
    @State private var candidates: [ArtistGroup] = []
    @State private var chooseArtist = false

    var body: some View {
        Group {
            if song.podcastEpisodeID == nil && !ArtistCredits.names(for: song).isEmpty {
                Button {
                    candidates = ArtistCredits.navigationGroups(for: song, indexedGroups: library.artistGroupsByID)
                    if candidates.count == 1 { selectedArtist = candidates.first }
                    else if !candidates.isEmpty { chooseArtist = true }
                } label: {
                    Text(song.artist).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("nowplaying_open_artist \(song.artist)"))
            } else {
                Text(song.artist)
            }
        }
        .font(.body)
        .foregroundStyle(.white.opacity(0.68))
        .lineLimit(1)
        .confirmationDialog("nowplaying_choose_artist", isPresented: $chooseArtist, titleVisibility: .visible) {
            ForEach(candidates) { artist in
                Button(artist.name) { selectedArtist = artist }
            }
        }
        .sheet(item: $selectedArtist) { artist in
            NowPlayingArtistSheet(artist: artist)
        }
    }
}

private struct NowPlayingArtistSheet: View {
    let artist: ArtistGroup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ArtistDetailView(artist: artist)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("catalog_done") { dismiss() }
                    }
                }
        }
    }
}
