import SwiftUI

struct AlbumPlaybackControls: View {
    let songs: [Song]
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            Button { play(shuffled: false) } label: {
                Label("play_all_action", systemImage: "play.fill")
            }.buttonStyle(.borderedProminent)
            Button { play(shuffled: true) } label: {
                Label("shuffle_action", systemImage: "shuffle")
            }.buttonStyle(.bordered)
        }
        .disabled(songs.isEmpty)
    }

    private func play(shuffled: Bool) {
        let queue = AlbumSongSelection.queue(songs, shuffled: shuffled)
        guard let first = queue.first, let url = library.getURL(for: first) else { return }
        player.lastPlaybackDirection = .fade
        player.play(song: first, url: url, queue: queue)
        player.allSongs = library.songs
        player.fillAutoNext(from: library.songs)
    }
}
