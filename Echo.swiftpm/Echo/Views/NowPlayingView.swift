import SwiftUI
import UIKit

struct NowPlayingView: View {
    var onClose: (() -> Void)? = nil
    var onCloseDrag: ((CGFloat) -> Void)? = nil
    var onCloseDragEnd: ((CGFloat) -> Void)? = nil
    var onCloseDragCancel: (() -> Void)? = nil

    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(\.dismiss) private var dismiss

    @GestureState private var closeDragActive = false

    @State private var closingDragInProgress = false
    @State private var cachedArtwork: UIImage?
    @State private var showQueue = false
    @State private var showPlaylistPicker = false
    @State private var showLyrics = false

    var body: some View {
        ZStack {
            nowPlayingBackground

            VStack(spacing: 25) {
                closeHandle

                Spacer(minLength: 0)

                artwork

                if let song = audioPlayer.currentSong {
                    HStack(alignment: .center) {
                        VStack(
                            alignment: .leading,
                            spacing: 5
                        ) {
                            Text(song.title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text(song.artist)
                                .font(.body)
                                .foregroundStyle(
                                    .white.opacity(0.68)
                                )
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            showPlaylistPicker = true
                        } label: {
                            Image(systemName: "music.note.list")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            LocalizedStringKey(
                                "add_to_playlist_action"
                            )
                        )
                    }
                    .padding(.horizontal, 28)
                }

                VStack(spacing: 5) {
                    Slider(
                        value: Binding(
                            get: {
                                audioPlayer.currentTime
                            },
                            set: { value in
                                audioPlayer.seek(to: value)
                            }
                        ),
                        in: 0...max(audioPlayer.duration, 1),
                        onEditingChanged: { editing in
                            if editing {
                                audioPlayer.pauseForSeeking()
                            } else {
                                audioPlayer.resumeAfterSeeking()
                            }
                        }
                    )
                    .tint(.white)

                    HStack {
                        Text(
                            formatTime(audioPlayer.currentTime)
                        )

                        Spacer()

                        Text(
                            formatTime(audioPlayer.duration)
                        )
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.horizontal, 28)

                HStack(spacing: 35) {
                    Button {
                        audioPlayer.toggleShuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.title2)
                            .foregroundStyle(
                                audioPlayer.shuffleEnabled
                                    ? Color.red
                                    : Color.white
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey("shuffle_action")
                    )

                    Button {
                        audioPlayer.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "previous_track_action"
                        )
                    )

                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        Image(
                            systemName: audioPlayer.isPlaying
                                ? "pause.circle.fill"
                                : "play.circle.fill"
                        )
                        .font(.system(size: 70))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        audioPlayer.isPlaying
                            ? LocalizedStringKey("pause_action")
                            : LocalizedStringKey("play_action")
                    )

                    Button {
                        audioPlayer.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey("next_track_action")
                    )

                    Button {
                        audioPlayer.toggleRepeat()
                    } label: {
                        Image(
                            systemName: audioPlayer.repeatMode == .one
                                ? "repeat.1"
                                : "repeat"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            audioPlayer.repeatMode == .off
                                ? Color.white
                                : Color.red
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey("repeat_action")
                    )
                }

                HStack {
                    AirPlayButton(
                        tintColor: .white,
                        activeTintColor: .white
                    )
                    .frame(width: 30, height: 30)

                    Spacer()

                    Button {
                        showPlaylistPicker = true
                    } label: {
                        Image(systemName: "music.note.list")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "add_to_playlist_action"
                        )
                    )

                    Button {
                        showLyrics = true
                    } label: {
                        Image(systemName: "quote.bubble")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey("lyrics_action")
                    )

                    Button {
                        showQueue = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey("queue_action")
                    )
                }
                .padding(.horizontal, 30)

                Spacer(minLength: 12)
            }
        }
        .onChange(
            of: audioPlayer.currentSong?.coverData
                ?? audioPlayer.currentSong?.imageData,
            initial: true
        ) {
            let data = audioPlayer.currentSong?.coverData
                ?? audioPlayer.currentSong?.imageData

            cachedArtwork = data.flatMap {
                UIImage(data: $0)
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
        .sheet(isPresented: $showPlaylistPicker) {
            if let song = audioPlayer.currentSong {
                PlaylistPickerView(song: song)
            }
        }
        .sheet(isPresented: $showLyrics) {
            NavigationStack {
                LyricsView()
            }
        }
    }

    private var closeHandle: some View {
        Capsule()
            .fill(.white.opacity(0.55))
            .frame(width: 38, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(
                    minimumDistance: 5,
                    coordinateSpace: .global
                )
                .updating($closeDragActive) { _, active, _ in
                    active = true
                }
                .onChanged { value in
                    closingDragInProgress = true
                    onCloseDrag?(value.translation.height)
                }
                .onEnded { value in
                    closingDragInProgress = false

                    if let onCloseDragEnd {
                        onCloseDragEnd(value.velocity.height)
                    } else if
                        value.translation.height > 70
                        || value.velocity.height > 650
                    {
                        close()
                    }
                }
                .exclusively(
                    before: TapGesture().onEnded {
                        close()
                    }
                )
            )
            .task(id: closeDragActive) {
                guard !closeDragActive else { return }

                await Task.yield()

                if closingDragInProgress {
                    closingDragInProgress = false
                    onCloseDragCancel?()
                }
            }
            .accessibilityLabel("Close Now Playing")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                close()
            }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    @ViewBuilder
    private var nowPlayingBackground: some View {
        if let image = cachedArtwork {
            GeometryReader { geometry in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .scaleEffect(1.35)
                    .blur(radius: 65)
                    .saturation(1.25)
                    .overlay {
                        Color.black.opacity(0.42)
                    }
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.08),
                                Color.black.opacity(0.18),
                                Color.black.opacity(0.58)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .clipped()
            }
            .ignoresSafeArea()
        } else {
            ZStack {
                Color.black

                Rectangle()
                    .fill(.ultraThinMaterial)
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = cachedArtwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 280, height: 280)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
                .shadow(
                    color: .black.opacity(0.30),
                    radius: 22,
                    y: 12
                )
        } else {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .fill(.white.opacity(0.12))

                Image(systemName: "music.note")
                    .font(.system(size: 100))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(width: 280, height: 280)
        }
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else {
            return "0:00"
        }

        let minutes = Int(time) / 60
        let seconds = Int(time) % 60

        return String(
            format: "%d:%02d",
            minutes,
            seconds
        )
    }
}