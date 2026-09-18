import SwiftUI

struct PodcastPlaybackControls: View {
    @Environment(AudioPlayerManager.self) private var player
    var body: some View {
        HStack(spacing: 20) {
            Menu {
                ForEach([Float(0.75), 1, 1.25, 1.5, 1.75, 2], id: \.self) { speed in
                    Button { player.setPodcastSpeed(speed) } label: {
                        Text("podcasts_speed_value \(speed.formatted())")
                    }
                }
            } label: {
                Text("podcasts_speed_value \(player.podcastSpeed.formatted())").font(.subheadline.bold())
                    .frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("podcasts_speed")
            Button { player.seek(to: player.currentTime - 15) } label: {
                Image(systemName: "gobackward.15").font(.title2).frame(width: 44, height: 44)
            }.accessibilityLabel("podcasts_skip_back")
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 70))
            }.accessibilityLabel(player.isPlaying ? Text("pause_action") : Text("play_action"))
            Button { player.seek(to: player.currentTime + 30) } label: {
                Image(systemName: "goforward.30").font(.title2).frame(width: 44, height: 44)
            }.accessibilityLabel("podcasts_skip_forward")
            Button { player.next() } label: {
                Image(systemName: "forward.end.fill").frame(width: 44, height: 44)
            }.accessibilityLabel("podcasts_next_episode")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}
