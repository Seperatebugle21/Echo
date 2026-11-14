import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

/// Now playing on the Lock Screen, in StandBy and in the Dynamic Island.
struct EchoLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EchoLiveActivityAttributes.self) { context in
            EchoLiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "echo://open"))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    EchoLiveActivityArtwork(state: state)
                        .frame(width: 52, height: 52)
                        .clipShape(.rect(cornerRadius: 10))
                }
                DynamicIslandExpandedRegion(.center) {
                    EchoLiveActivityTitle(state: state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EchoLiveActivityStatusIcon(state: state)
                        .font(.title3)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        EchoLiveActivityProgress(state: state)
                        EchoLiveActivityControls(state: state)
                    }
                }
            } compactLeading: {
                EchoLiveActivityArtwork(state: state)
                    .frame(width: 24, height: 24)
                    .clipShape(.rect(cornerRadius: 6))
            } compactTrailing: {
                EchoLiveActivityStatusIcon(state: state)
            } minimal: {
                EchoLiveActivityArtwork(state: state)
                    .frame(width: 24, height: 24)
                    .clipShape(.circle)
            }
            .widgetURL(URL(string: "echo://open"))
            .keylineTint(.white)
        }
    }
}

private struct EchoLiveActivityLockScreenView: View {
    let state: EchoLiveActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                EchoLiveActivityArtwork(state: state)
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 10))
                EchoLiveActivityTitle(state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                EchoLiveActivityStatusIcon(state: state)
                    .font(.title3)
            }
            EchoLiveActivityProgress(state: state)
            EchoLiveActivityControls(state: state)
        }
        .padding(14)
        .foregroundStyle(.white)
    }
}

private struct EchoLiveActivityTitle: View {
    let state: EchoLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: state.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(verbatim: state.artist).font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EchoLiveActivityStatusIcon: View {
    let state: EchoLiveActivityAttributes.ContentState

    var body: some View {
        Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
            .symbolEffect(.variableColor.iterative, isActive: state.isPlaying)
            .foregroundStyle(.white.opacity(0.85))
            .accessibilityHidden(true)
    }
}

private struct EchoLiveActivityProgress: View {
    let state: EchoLiveActivityAttributes.ContentState

    var body: some View {
        Group {
            if let interval = state.progressInterval {
                // Animated by the system; no per-second updates from the app.
                ProgressView(timerInterval: interval, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: state.progress)
            }
        }
        .progressViewStyle(.linear)
        .tint(.white)
        .accessibilityHidden(true)
    }
}

private struct EchoLiveActivityControls: View {
    let state: EchoLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 0) {
            control(.previous, symbol: "backward.end.fill", label: "Vorig nummer")
            control(.toggle, symbol: state.isPlaying ? "pause.fill" : "play.fill",
                    label: state.isPlaying ? "Pauzeer" : "Speel af")
            control(.next, symbol: "forward.end.fill", label: "Volgend nummer")
        }
    }

    private func control(_ action: EchoWidgetAction, symbol: String, label: String) -> some View {
        Button(intent: EchoWidgetPlaybackIntent(action, songID: state.songID)) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(Text(verbatim: label))
    }
}

/// Artwork comes from the widget snapshot in the App Group, matched on song ID
/// so a stale cover is never shown for a new song.
private struct EchoLiveActivityArtwork: View {
    let state: EchoLiveActivityAttributes.ContentState

    var body: some View {
        let snapshot = EchoWidgetSnapshotStore.load()
        let item = snapshot.currentSong?.id == state.songID ? snapshot.currentSong : nil
        GeometryReader { proxy in
            Group {
                if let data = item?.artworkData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [Color(red: 0.5, green: 0.18, blue: 0.42),
                                                Color(red: 0.13, green: 0.18, blue: 0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: state.isPodcast ? "mic.fill" : "music.note")
                            .font(.system(size: max(10, proxy.size.width * 0.4)))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}
