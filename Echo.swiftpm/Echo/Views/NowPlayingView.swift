import SwiftUI
import UIKit
import ImageIO
import CoreImage

struct NowPlayingView: View {
    // Defaults preserve existing callers that present this view in a sheet.
    var onClose: (() -> Void)? = nil
    var onCloseDrag: ((CGFloat) -> Void)? = nil
    var onCloseDragEnd: ((CGFloat) -> Void)? = nil
    var onCloseDragCancel: (() -> Void)? = nil
    var renderedArtwork: PlayerArtworkImages? = nil
    var drawsBackground = true

    @State private var sliderFrame: CGRect = .zero
    @State private var dragMayClose: Bool?
    @State private var localArtwork = PlayerArtworkImages.empty
    @GestureState private var closeDragActive = false
    @State private var closingDragInProgress = false


    @Environment(AudioPlayerManager.self)
    private var audioPlayer

    @Environment(\.dismiss)
    private var dismiss

    @State private var showQueue = false
    @State private var showPlaylistPicker = false
    @State private var showLyrics = false

    var body: some View {

        ZStack {

            // MARK: - Background

            if drawsBackground {
                NowPlayingBackdrop(image: (renderedArtwork ?? localArtwork).background)
                    .ignoresSafeArea()
            }


            // MARK: - Content

            VStack(spacing: 25) {

                // MARK: Close Button

                closeHandle

                Spacer(minLength: 0)


                // MARK: - Artwork

                artwork


                // MARK: - Song Info

                if let song = audioPlayer.currentSong {

                    HStack(alignment: .center) {

                        VStack(
                            alignment: .leading,
                            spacing: 5
                        ) {

                            Text(song.title)
                                .font(
                                    .title2
                                        .weight(.bold)
                                )
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

                            Image(
                                systemName:
                                    "music.note.list"
                            )
                            .font(
                                .title3
                                    .weight(.medium)
                            )
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


                // MARK: - Progress

                VStack(spacing: 5) {

                    Slider(
                        value: Binding(
                            get: {
                                audioPlayer.currentTime
                            },
                            set: { value in
                                audioPlayer.seek(
                                    to: value
                                )
                            }
                        ),
                        in: 0...max(
                            audioPlayer.duration,
                            1
                        ),
                        onEditingChanged: { editing in

                            if editing {

                                audioPlayer
                                    .pauseForSeeking()

                            } else {

                                audioPlayer
                                    .resumeAfterSeeking()
                            }
                        }
                    )
                    .tint(.white)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        if !closingDragInProgress { sliderFrame = frame }
                    }

                    HStack {

                        Text(
                            formatTime(
                                audioPlayer.currentTime
                            )
                        )

                        Spacer()

                        Text(
                            formatTime(
                                audioPlayer.duration
                            )
                        )
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(
                        .white.opacity(0.65)
                    )
                }
                .padding(.horizontal, 28)


                // MARK: - Playback Controls

                HStack(spacing: 35) {

                    // Shuffle

                    Button {
                        audioPlayer.toggleShuffle()
                    } label: {

                        Image(
                            systemName: "shuffle"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            audioPlayer.shuffleEnabled
                            ? Color.red
                            : Color.white
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "shuffle_action"
                        )
                    )


                    // Previous

                    Button {
                        audioPlayer.previous()
                    } label: {

                        Image(
                            systemName:
                                "backward.fill"
                        )
                        .font(.title2)
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "previous_track_action"
                        )
                    )


                    // Play / Pause

                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {

                        Image(
                            systemName:
                                audioPlayer.isPlaying
                                ? "pause.circle.fill"
                                : "play.circle.fill"
                        )
                        .font(
                            .system(size: 70)
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        audioPlayer.isPlaying
                        ? LocalizedStringKey(
                            "pause_action"
                        )
                        : LocalizedStringKey(
                            "play_action"
                        )
                    )


                    // Next

                    Button {
                        audioPlayer.next()
                    } label: {

                        Image(
                            systemName:
                                "forward.fill"
                        )
                        .font(.title2)
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "next_track_action"
                        )
                    )


                    // Repeat

                    Button {
                        audioPlayer.toggleRepeat()
                    } label: {

                        Image(
                            systemName:
                                audioPlayer.repeatMode
                                == .one
                                ? "repeat.1"
                                : "repeat"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            audioPlayer.repeatMode
                            == .off
                            ? Color.white
                            : Color.red
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "repeat_action"
                        )
                    )
                }


                // MARK: - Bottom Actions

                HStack {

                    // AirPlay

                    AirPlayButton(
                        tintColor: .white,
                        activeTintColor: .white
                    )
                    .frame(
                        width: 30,
                        height: 30
                    )


                    Spacer()


                    // Add to Playlist

                    Button {
                        showPlaylistPicker = true
                    } label: {

                        Image(
                            systemName:
                                "music.note.list"
                        )
                        .font(.title3)
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "add_to_playlist_action"
                        )
                    )


                    // Lyrics

                    Button {
                        showLyrics = true
                    } label: {

                        Image(
                            systemName:
                                "quote.bubble"
                        )
                        .font(.title3)
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "lyrics_action"
                        )
                    )


                    // Queue

                    Button {
                        showQueue = true
                    } label: {

                        Image(
                            systemName:
                                "list.bullet"
                        )
                        .font(.title3)
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "queue_action"
                        )
                    )
                }
                .padding(.horizontal, 30)


                Spacer(minLength: 12)
            }
            // A recognized vertical drag cannot also release a playback button.
            .disabled(closingDragInProgress)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(closeDrag)
        .task(id: closeDragActive) {
            guard !closeDragActive else { return }
            await Task.yield()
            if closingDragInProgress {
                closingDragInProgress = false
                onCloseDragCancel?()
            }
            dragMayClose = nil
        }

        .task(id: audioPlayer.currentSong?.coverData ?? audioPlayer.currentSong?.imageData) {
            guard renderedArtwork == nil else { return }
            let data = audioPlayer.currentSong?.coverData ?? audioPlayer.currentSong?.imageData
            let images = await PlayerArtworkImages.prepare(data)
            guard !Task.isCancelled else { return }
            localArtwork = images
        }

        // MARK: - Queue Sheet

        .sheet(
            isPresented: $showQueue
        ) {
            QueueView()
        }


        // MARK: - Playlist Sheet

        .sheet(
            isPresented:
                $showPlaylistPicker
        ) {

            if let song =
                audioPlayer.currentSong
            {

                PlaylistPickerView(
                    song: song
                )
            }
        }


        // MARK: - Lyrics Sheet

        .sheet(
            isPresented: $showLyrics
        ) {

            NavigationStack {
                LyricsView()
            }
        }
    }


    private var closeHandle: some View {
        Button {
            guard !closingDragInProgress else { return }
            close()
        } label: {
            Capsule()
                .fill(.white.opacity(0.55))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close Now Playing")
    }

    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($closeDragActive) { _, active, _ in active = true }
            .onChanged { value in
                if dragMayClose == nil {
                    // Preserve seeking, even if a slider drag is slightly diagonal.
                    let startedOnSlider = sliderFrame
                        .insetBy(dx: -12, dy: -12)
                        .contains(value.startLocation)
                    dragMayClose = !startedOnSlider
                        && value.translation.height > 0
                        && abs(value.translation.height) > abs(value.translation.width)
                }
                guard dragMayClose == true else { return }
                closingDragInProgress = true
                onCloseDrag?(value.translation.height)
            }
            .onEnded { value in
                let shouldFinish = closingDragInProgress
                closingDragInProgress = false
                dragMayClose = nil
                guard shouldFinish else { return }
                if let onCloseDragEnd {
                    onCloseDragEnd(value.velocity.height)
                } else if value.translation.height > 70 || value.velocity.height > 650 {
                    close()
                }
            }
    }

    private func close() {
        if let onClose { onClose() }
        else { dismiss() }
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artwork: some View {

        if let image = (renderedArtwork ?? localArtwork).cover {

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(
                    width: 280,
                    height: 280
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
                .shadow(
                    color:
                        .black.opacity(0.30),
                    radius: 22,
                    y: 12
                )

        } else {

            ZStack {

                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .fill(
                    .white.opacity(0.12)
                )

                Image(
                    systemName:
                        "music.note"
                )
                .font(
                    .system(size: 100)
                )
                .foregroundStyle(
                    .white.opacity(0.8)
                )
            }
            .frame(
                width: 280,
                height: 280
            )
        }
    }


    // MARK: - Time

    private func formatTime(
        _ time: Double
    ) -> String {

        guard
            time.isFinite,
            time >= 0
        else {
            return "0:00"
        }

        let minutes =
            Int(time) / 60

        let seconds =
            Int(time) % 60

        return String(
            format: "%d:%02d",
            minutes,
            seconds
        )
    }
}

// Shared images are prepared once per artwork change, outside the gesture path.
// UIImage instances are immutable here and are only rendered after preparation.
struct PlayerArtworkImages: @unchecked Sendable {
    let cover: UIImage?
    let background: UIImage?
    static let empty = PlayerArtworkImages(cover: nil, background: nil)

    static func prepare(_ data: Data?) async -> PlayerArtworkImages {
        guard let data else { return .empty }
        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return PlayerArtworkImages.empty
            }

            func thumbnail(_ maximumSize: Int) -> CGImage? {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumSize,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                return CGImageSourceCreateThumbnailAtIndex(
                    source, 0, options as CFDictionary
                )
            }

            guard let cover = thumbnail(900) else {
                return PlayerArtworkImages.empty
            }

            var background: UIImage?
            if let small = thumbnail(180) {
                let input = CIImage(cgImage: small)
                let blurred = input.clampedToExtent()
                    .applyingGaussianBlur(sigma: 20)
                    .cropped(to: input.extent)
                let context = CIContext(options: [.cacheIntermediates: false])
                if let output = context.createCGImage(blurred, from: input.extent) {
                    background = UIImage(cgImage: output)
                }
            }
            return PlayerArtworkImages(
                cover: UIImage(cgImage: cover),
                background: background ?? UIImage(cgImage: cover)
            )
        }.value
    }
}

// Used by both standalone Now Playing and the interactive transition.
// No live blur shader or repeated image decoding during a drag.
struct NowPlayingBackdrop: View {
    let image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .saturation(1.25)
                } else {
                    LinearGradient(
                        colors: [Color(white: 0.22), Color(white: 0.10)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }

                Color.black.opacity(0.42)
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.58)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}
