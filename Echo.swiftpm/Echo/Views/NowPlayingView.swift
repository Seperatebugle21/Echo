import SwiftUI

struct NowPlayingView: View {

    @Environment(AudioPlayerManager.self)
    private var audioPlayer

    @Environment(\.dismiss)
    private var dismiss

    @State private var showQueue = false
    @State private var showPlaylistPicker = false
    @State private var showLyrics = false

    var body: some View {

        GeometryReader { geometry in

            let artworkSize =
                min(
                    geometry.size.width - 48,
                    320
                )

            ScrollView(
                .vertical,
                showsIndicators: false
            ) {

                VStack(spacing: 0) {

                    // MARK: - Top

                    HStack {

                        Spacer()

                        Button {
                            dismiss()
                        } label: {

                            Image(
                                systemName:
                                    "chevron.down"
                            )
                            .font(
                                .system(
                                    size: 19,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(.primary)
                            .frame(
                                width: 42,
                                height: 42
                            )
                            .background(
                                .thinMaterial,
                                in: Circle()
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            LocalizedStringKey(
                                "dismiss_action"
                            )
                        )

                        Spacer()
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 24)


                    // MARK: - Artwork

                    Group {

                        if
                            let song =
                                audioPlayer.currentSong,
                            let data =
                                song.coverData,
                            let image =
                                UIImage(data: data)
                        {

                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: artworkSize,
                                    height: artworkSize
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 26,
                                        style: .continuous
                                    )
                                )

                        } else {

                            ZStack {

                                RoundedRectangle(
                                    cornerRadius: 26,
                                    style: .continuous
                                )
                                .fill(.thinMaterial)

                                Image(
                                    systemName:
                                        "music.note"
                                )
                                .font(
                                    .system(
                                        size: 82,
                                        weight: .medium
                                    )
                                )
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                            .frame(
                                width: artworkSize,
                                height: artworkSize
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)


                    // MARK: - Song Info

                    if
                        let song =
                            audioPlayer.currentSong
                    {

                        VStack(
                            alignment: .leading,
                            spacing: 6
                        ) {

                            Text(song.title)
                                .font(
                                    .title2
                                        .weight(.bold)
                                )
                                .foregroundStyle(
                                    .primary
                                )
                                .lineLimit(1)

                            Text(song.artist)
                                .font(
                                    .body
                                        .weight(.medium)
                                )
                                .foregroundStyle(
                                    .secondary
                                )
                                .lineLimit(1)
                        }
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                    }


                    // MARK: - Progress

                    VStack(spacing: 7) {

                        Slider(
                            value: Binding(
                                get: {
                                    audioPlayer
                                        .currentTime
                                },
                                set: { value in
                                    audioPlayer
                                        .seek(
                                            to: value
                                        )
                                }
                            ),
                            in:
                                0...
                                max(
                                    audioPlayer
                                        .duration,
                                    1
                                ),
                            onEditingChanged: {
                                editing in

                                if editing {

                                    audioPlayer
                                        .pauseForSeeking()

                                } else {

                                    audioPlayer
                                        .resumeAfterSeeking()
                                }
                            }
                        )

                        HStack {

                            Text(
                                formatTime(
                                    audioPlayer
                                        .currentTime
                                )
                            )

                            Spacer()

                            Text(
                                formatTime(
                                    audioPlayer
                                        .duration
                                )
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                        .monospacedDigit()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)


                    // MARK: - Playback Controls

                    HStack(
                        alignment: .center,
                        spacing: 0
                    ) {

                        Button {

                            audioPlayer
                                .toggleShuffle()

                        } label: {

                            Image(
                                systemName:
                                    "shuffle"
                            )
                            .font(
                                .system(
                                    size: 19,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                audioPlayer
                                    .shuffleEnabled
                                ? Color.red
                                : Color.primary
                            )
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            LocalizedStringKey(
                                "shuffle_action"
                            )
                        )


                        Button {

                            audioPlayer
                                .previous()

                        } label: {

                            Image(
                                systemName:
                                    "backward.fill"
                            )
                            .font(
                                .system(
                                    size: 27,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                .primary
                            )
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            LocalizedStringKey(
                                "previous_track_action"
                            )
                        )


                        Button {

                            audioPlayer
                                .togglePlayPause()

                        } label: {

                            Image(
                                systemName:
                                    audioPlayer
                                        .isPlaying
                                    ? "pause.fill"
                                    : "play.fill"
                            )
                            .font(
                                .system(
                                    size: 27,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                Color(
                                    .systemBackground
                                )
                            )
                            .frame(
                                width: 72,
                                height: 72
                            )
                            .background(
                                Color.primary,
                                in: Circle()
                            )
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


                        Button {

                            audioPlayer
                                .next()

                        } label: {

                            Image(
                                systemName:
                                    "forward.fill"
                            )
                            .font(
                                .system(
                                    size: 27,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                .primary
                            )
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            LocalizedStringKey(
                                "next_track_action"
                            )
                        )


                        Button {

                            audioPlayer
                                .toggleRepeat()

                        } label: {

                            Image(
                                systemName:
                                    audioPlayer
                                        .repeatMode
                                    == .one
                                    ? "repeat.1"
                                    : "repeat"
                            )
                            .font(
                                .system(
                                    size: 19,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                audioPlayer
                                    .repeatMode
                                == .off
                                ? Color.primary
                                : Color.red
                            )
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            LocalizedStringKey(
                                "repeat_action"
                            )
                        )
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 28)


                    // MARK: - Bottom Actions

                    HStack {

    AirPlayButton()
        .frame(width: 30, height: 30)

    Spacer()

    Button {
        showPlaylistPicker = true
    } label: {
        Image(systemName: "music.note.list")
            .font(.title3)
    }
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
    }
    .accessibilityLabel(
        LocalizedStringKey(
            "lyrics_action"
        )
    )

    Button {
        showQueue = true
    } label: {
        Image(systemName: "list.bullet")
            .font(.title3)
    }
    .accessibilityLabel(
        LocalizedStringKey(
            "queue_action"
        )
    )
}
.padding(.horizontal)
.padding(.horizontal)
                    .padding(.vertical, 15)
                    .padding(.horizontal, 8)
                    .background(
                        .thinMaterial,
                        in:
                            RoundedRectangle(
                                cornerRadius: 22,
                                style: .continuous
                            )
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 30)
                }
            }
        }

        .sheet(
            isPresented: $showQueue
        ) {

            QueueView()
        }

        .sheet(
            isPresented:
                $showPlaylistPicker
        ) {

            if
                let song =
                    audioPlayer.currentSong
            {

                PlaylistPickerView(
                    song: song
                )
            }
        }

        .sheet(
            isPresented: $showLyrics
        ) {

            NavigationStack {

                LyricsView()
            }
        }
    }


    // MARK: - Time Formatting

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
