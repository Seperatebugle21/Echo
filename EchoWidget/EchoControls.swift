import AppIntents
import SwiftUI
import WidgetKit

struct EchoControlsBundle: WidgetBundle {
    var body: some Widget {
        EchoPlayPauseControl()
        EchoNextTrackControl()
        EchoFlowControl()
        EchoOpenControl()
    }
}

/// Play/pause in Control Center, on the Lock Screen and on the Action button.
struct EchoPlayPauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: EchoWidgetKinds.playPauseControl, provider: Provider()) { isPlaying in
            ControlWidgetToggle("control_play_pause_title", isOn: isPlaying, action: EchoControlPlaybackIntent()) { playing in
                Label(playing ? LocalizedStringKey("control_playing") : LocalizedStringKey("control_paused"),
                      systemImage: playing ? "pause.fill" : "play.fill")
            }
            .tint(.pink)
        }
        .displayName("control_play_pause_title")
        .description("control_play_pause_description")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool {
            EchoWidgetSnapshotStore.load().isPlaying ?? false
        }
    }
}

struct EchoNextTrackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: EchoWidgetKinds.nextControl) {
            ControlWidgetButton(action: EchoWidgetPlaybackIntent(.next)) {
                Label("control_next_title", systemImage: "forward.fill")
            }
        }
        .displayName("control_next_title")
        .description("control_next_description")
    }
}

struct EchoFlowControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: EchoWidgetKinds.flowControl) {
            ControlWidgetButton(action: EchoWidgetPlaybackIntent(.flow)) {
                Label("control_flow_title", systemImage: "waveform")
            }
        }
        .displayName("control_flow_title")
        .description("control_flow_description")
    }
}

struct EchoOpenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: EchoWidgetKinds.openControl) {
            ControlWidgetButton(action: EchoOpenAppIntent()) {
                Label("control_open_title", systemImage: "music.note")
            }
        }
        .displayName("control_open_title")
        .description("control_open_description")
    }
}
