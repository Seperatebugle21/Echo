import SwiftUI

struct AudioOptionsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AudioSettings.monoKey) private var mono = false
    @AppStorage(AudioSettings.transitionKey) private var mode = AudioTransitionMode.direct.rawValue
    @AppStorage(AudioSettings.crossfadeKey) private var seconds = 5.0
    @State private var showPreview = false
    private var transition: AudioTransitionMode { AudioTransitionMode(rawValue: mode) ?? .direct }
    var body: some View {
        Form {
            Section {
                Picker("audio_output_mode", selection: $mono) {
                    Text("audio_stereo").tag(false); Text("audio_mono").tag(true)
                }.pickerStyle(.segmented)
            } header: { Text("audio_output_mode") } footer: {
                Text(LocalizedStringKey(mono ? "audio_mono_short" : "audio_stereo_short"))
            }
            Section {
                ForEach(AudioTransitionMode.allCases) { option in
                    Button { mode = option.rawValue } label: {
                        HStack {
                            Text(LocalizedStringKey(option.key)).foregroundStyle(.primary)
                            Spacer()
                            if transition == option { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                        }.frame(minHeight: 36)
                    }.accessibilityAddTraits(transition == option ? .isSelected : [])
                }
                if transition == .crossfade {
                    VStack(alignment: .leading) {
                        Text("audio_crossfade_seconds \(Int(seconds))").monospacedDigit()
                        Slider(value: $seconds, in: 1...12, step: 1).accessibilityLabel("audio_crossfade_duration")
                    }
                }
            } header: { Text("audio_transitions_title") } footer: { Text(LocalizedStringKey(transition.detailKey)) }
            Section {
                Button { showPreview = true } label: { Label("audio_preview_title", systemImage: "speaker.wave.2") }
            }
        }.echoBackground().navigationTitle("settingsview_audio").navigationBarTitleDisplayMode(.inline)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.88), value: mode)
            .sheet(isPresented: $showPreview) { AudioTransitionPreviewView() }
            .onChange(of: mono) { NotificationCenter.default.post(name: AudioSettings.didChange, object: nil) }
    }
}

struct AudioTransitionPreviewView: View {
    @Environment(MusicLibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var own = false
    @State private var first: UUID?
    @State private var second: UUID?
    @State private var loading = false
    @State private var playing = false
    @State private var failed = false
    @State private var task: Task<Void, Never>?
    private let player = AudioPlayerManager.shared
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("audio_preview_source", selection: $own) {
                        Text("audio_preview_builtin").tag(false); Text("audio_preview_library").tag(true)
                    }.pickerStyle(.segmented).onChange(of: own) { stop() }
                    if own {
                        songPicker("audio_preview_first", selection: $first)
                        songPicker("audio_preview_second", selection: $second)
                    }
                }
                Section {
                    if loading { ProgressView("audio_preview_loading") }
                    Button {
                        if playing || loading { stop() } else { listen() }
                    } label: { Label(LocalizedStringKey(playing || loading ? "audio_preview_stop" : "audio_preview_play"), systemImage: playing || loading ? "stop.fill" : "play.fill") }
                        .disabled(own && (first == nil || second == nil) && !playing && !loading)
                } footer: { Text("audio_preview_detail") }
            }.echoBackground().navigationTitle("audio_preview_title").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("action_done") { stop(); dismiss() } } }
                .alert("podcasts_error_title", isPresented: $failed) { Button("podcasts_ok", role: .cancel) {} } message: { Text("audio_preview_error") }
                .onDisappear { stop() }
                .onChange(of: first) { stop() }.onChange(of: second) { stop() }
        }
    }
    private func songPicker(_ key: LocalizedStringKey, selection: Binding<UUID?>) -> some View {
        Picker(key, selection: selection) {
            Text("audio_preview_choose").tag(UUID?.none)
            ForEach(library.songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { song in
                Text("\(song.title) — \(song.artist)").tag(Optional(song.id))
            }
        }
    }
    private func listen() {
        let urls: (URL, URL)?
        if own {
            if let a = library.songs.first(where: { $0.id == first }), let b = library.songs.first(where: { $0.id == second }), let au = library.getURL(for: a), let bu = library.getURL(for: b) { urls = (au, bu) }
            else { urls = nil }
        } else {
            #if SWIFT_PACKAGE
            let bundle = Bundle.module
            #else
            let bundle = Bundle.main
            #endif
            if let a = bundle.url(forResource: "TransitionDemo110", withExtension: "wav"), let b = bundle.url(forResource: "TransitionDemo116", withExtension: "wav") { urls = (a, b) }
            else { urls = nil }
        }
        guard let urls else { failed = true; return }
        loading = true
        task = Task { @MainActor in
            do {
                try await player.startTransitionPreview(first: urls.0, second: urls.1)
                guard !Task.isCancelled else { return }
                loading = false; playing = true
                player.previewFinished = { loading = false; playing = false }
            } catch { if !Task.isCancelled { failed = true }; loading = false; playing = false }
        }
    }
    private func stop() { task?.cancel(); task = nil; player.stopTransitionPreview(); loading = false; playing = false }
}
