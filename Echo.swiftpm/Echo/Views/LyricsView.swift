import SwiftUI

struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double
    let text: String
}

/// Full-screen lyrics on the song's living background. Now Playing shows the same
/// `LyricsScroller` inline in place of the cover.
struct LyricsView: View {
    @Environment(AudioPlayerManager.self) private var audioPlayer
    @State private var backdrop: UIImage?

    var body: some View {
        ZStack {
            EchoLivingBackdrop(image: backdrop, dim: 0.4)
                .ignoresSafeArea()
            LyricsScroller()
        }
        .task(id: audioPlayer.currentSong?.id) {
            let song = audioPlayer.currentSong
            let prepared = await PlayerArtworkImages.prepareBackdrop(song: song)
            guard !Task.isCancelled else { return }
            backdrop = prepared
        }
        .navigationTitle(Text(LocalizedStringKey("lyrics_navigation_title")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
