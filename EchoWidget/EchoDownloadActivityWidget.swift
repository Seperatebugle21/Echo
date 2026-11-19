import ActivityKit
import SwiftUI
import WidgetKit

/// Download progress on the Lock Screen, in StandBy and in the Dynamic Island.
struct EchoDownloadActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EchoDownloadActivityAttributes.self) { context in
            EchoDownloadLockScreenView(state: context.state)
                .environment(\.locale, Locale(identifier: context.attributes.language))
                .activityBackgroundTint(.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "echo://open"))
        } dynamicIsland: { context in
            let state = context.state
            let locale = Locale(identifier: context.attributes.language)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    EchoDownloadStatusIcon(state: state)
                        .font(.title2)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EchoDownloadCount(state: state)
                        .font(.headline)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    EchoDownloadHeadline(state: state)
                        .environment(\.locale, locale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EchoDownloadDetails(state: state)
                        .environment(\.locale, locale)
                }
            } compactLeading: {
                EchoDownloadStatusIcon(state: state)
            } compactTrailing: {
                EchoDownloadCount(state: state)
                    .font(.caption.weight(.semibold))
            } minimal: {
                if state.finished {
                    EchoDownloadStatusIcon(state: state)
                } else {
                    ProgressView(value: state.progress)
                        .progressViewStyle(.circular)
                        .tint(.blue)
                }
            }
            .widgetURL(URL(string: "echo://open"))
            .keylineTint(.blue)
        }
    }
}

private struct EchoDownloadLockScreenView: View {
    let state: EchoDownloadActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                EchoDownloadStatusIcon(state: state)
                    .font(.title2)
                EchoDownloadHeadline(state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                EchoDownloadCount(state: state)
                    .font(.headline)
            }
            EchoDownloadDetails(state: state)
        }
        .padding(14)
        .foregroundStyle(.white)
    }
}

private struct EchoDownloadHeadline: View {
    let state: EchoDownloadActivityAttributes.ContentState

    var body: some View {
        Text(LocalizedStringKey(state.finished ? "fetch_notification_done_title" : "fetch_background_title"))
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
    }
}

private struct EchoDownloadDetails: View {
    let state: EchoDownloadActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: state.progress)
                .progressViewStyle(.linear)
                .tint(state.finished && state.failed > 0 ? .orange : .blue)
            HStack(spacing: 8) {
                if state.finished {
                    Text("download_activity_added \(state.added)")
                    if state.failed > 0 {
                        Text("download_activity_failed \(state.failed)")
                            .foregroundStyle(.orange)
                    }
                } else if let title = state.currentTitle {
                    Text(verbatim: [title, state.currentArtist].compactMap { $0 }.joined(separator: " · "))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if !state.finished, let end = state.finishesAt {
                    // Counts down on its own; the app does not need to update every second.
                    Label {
                        Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 64, alignment: .trailing)
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
        }
    }
}

private struct EchoDownloadStatusIcon: View {
    let state: EchoDownloadActivityAttributes.ContentState

    var body: some View {
        Image(systemName: state.finished
              ? (state.failed > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
              : "arrow.down.circle.fill")
            .foregroundStyle(state.finished && state.failed > 0 ? Color.orange : state.finished ? Color.green : Color.blue)
            .symbolEffect(.pulse, isActive: !state.finished)
            .accessibilityHidden(true)
    }
}

private struct EchoDownloadCount: View {
    let state: EchoDownloadActivityAttributes.ContentState

    var body: some View {
        Text(verbatim: "\(state.done)/\(state.total)")
            .monospacedDigit()
            .foregroundStyle(.white)
    }
}
