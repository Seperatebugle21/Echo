import SwiftUI

struct AudioOptionsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AudioSettings.monoKey) private var mono = false
    @AppStorage(AudioSettings.transitionKey) private var mode = AudioTransitionMode.direct.rawValue
    @AppStorage(AudioSettings.crossfadeKey) private var seconds = 5.0
    @State private var showPreview = false
    private var transition: AudioTransitionMode { AudioTransitionMode(rawValue: mode) ?? .direct }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("audio_design_title").font(.title2.bold())
                    Text("audio_design_detail").font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        CustomizationIcon(symbol: "headphones", size: 54)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(LocalizedStringKey(transition.key)).font(.title3.bold())
                            Text(mono ? "audio_mono" : "audio_stereo").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    AudioTransitionDiagram(mode: transition)
                    Button { showPreview = true } label: {
                        Label("audio_preview_title", systemImage: "play.circle.fill")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent)
                }.padding(20).customizationSurface()
                VStack(alignment: .leading, spacing: 12) {
                    Text("audio_output_mode").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    outputChoice(mono: false)
                    outputChoice(mono: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("audio_transitions_title").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    ForEach(AudioTransitionMode.allCases) { option in
                        VStack(alignment: .leading, spacing: 16) {
                            Button { mode = option.rawValue } label: {
                                AudioChoiceLabel(title: option.key, detail: option.detailKey,
                                                 symbol: option.symbol, selected: transition == option)
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(transition == option ? .isSelected : [])
                            if option == .crossfade && transition == .crossfade {
                                Divider()
                                HStack {
                                    Text("audio_crossfade_duration").font(.subheadline)
                                    Spacer()
                                    Text("audio_crossfade_seconds \(Int(seconds))").font(.headline).monospacedDigit()
                                }
                                Slider(value: $seconds, in: 1...12, step: 1)
                                    .accessibilityLabel("audio_crossfade_duration")
                            }
                        }.padding(18).customizationSurface()
                            .overlay { RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(transition == option ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5) }
                    }
                }
            }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.echoBackground().navigationTitle("settingsview_audio").navigationBarTitleDisplayMode(.inline)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.88), value: mode)
            .sheet(isPresented: $showPreview) { AudioTransitionPreviewView() }
            .onChange(of: mono) { NotificationCenter.default.post(name: AudioSettings.didChange, object: nil) }
    }

    private func outputChoice(mono value: Bool) -> some View {
        Button { mono = value } label: {
            AudioChoiceLabel(title: value ? "audio_mono" : "audio_stereo",
                             detail: value ? "audio_mono_short" : "audio_stereo_short",
                             symbol: value ? "speaker.wave.2" : "hifispeaker.2", selected: mono == value)
                .padding(18).customizationSurface()
        }.buttonStyle(.plain).accessibilityAddTraits(mono == value ? .isSelected : [])
    }
}

private struct AudioChoiceLabel: View {
    let title: String
    let detail: String
    let symbol: String
    let selected: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CustomizationIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(title)).font(.headline).foregroundStyle(.primary)
                Text(LocalizedStringKey(detail)).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.4))
                .font(.title3).accessibilityHidden(true)
        }.contentShape(.rect)
    }
}

private extension AudioTransitionMode {
    var symbol: String {
        switch self {
        case .direct: "forward.end"
        case .gapless: "link"
        case .crossfade: "arrow.triangle.merge"
        case .mix: "waveform"
        }
    }
}

/// A schematic, not a simulated audio meter: illustrates how A leads into B.
private struct AudioTransitionDiagram: View {
    let mode: AudioTransitionMode
    var body: some View {
        HStack(spacing: mode == .direct ? 18 : 0) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(mode == .crossfade || mode == .mix ? 0.15 : 0.8)], startPoint: .leading, endPoint: .trailing))
                .overlay { Text("A").font(.title3.bold()).foregroundStyle(.primary) }
            Image(systemName: mode.symbol).font(.title3).padding(.horizontal, 10).foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [.accentColor.opacity(mode == .crossfade || mode == .mix ? 0.15 : 0.8), .accentColor], startPoint: .leading, endPoint: .trailing))
                .overlay { Text("B").font(.title3.bold()).foregroundStyle(.primary) }
        }.frame(height: 58).accessibilityHidden(true)
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
    @State private var generation = UUID()
    private let player = AudioPlayerManager.shared
    private var transition: AudioTransitionMode { AudioSettings.transition }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 14) {
                        CustomizationIcon(symbol: transition.symbol, size: 54)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey(transition.key)).font(.title2.bold())
                            Text(LocalizedStringKey(transition.detailKey)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Picker("audio_preview_source", selection: $own) {
                        Text("audio_preview_builtin").tag(false)
                        Text("audio_preview_library").tag(true)
                    }.pickerStyle(.segmented).onChange(of: own) { stop() }
                    VStack(spacing: 18) {
                        trackCard(first: true)
                        AudioTransitionDiagram(mode: transition)
                        trackCard(first: false)
                    }.padding(20).customizationSurface()
                    VStack(spacing: 16) {
                        if loading { ProgressView("audio_preview_loading") }
                        if playing {
                            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                                let position = player.transitionPreviewPosition
                                ProgressView(value: min(position.elapsed, max(1, position.duration)), total: max(1, position.duration))
                                    .accessibilityLabel("audio_preview_progress")
                                HStack {
                                    Text(Duration.seconds(position.elapsed), format: .time(pattern: .minuteSecond))
                                    Spacer()
                                    Text(Duration.seconds(position.duration), format: .time(pattern: .minuteSecond))
                                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            if playing || loading { stop() } else { listen() }
                        } label: {
                            Label(LocalizedStringKey(playing || loading ? "audio_preview_stop" : "audio_preview_play"),
                                  systemImage: playing || loading ? "stop.fill" : "play.fill")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.borderedProminent)
                            .disabled(own && (first == nil || second == nil) && !playing && !loading)
                        Text("audio_preview_detail").font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }.padding(20).customizationSurface()
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }.echoBackground().navigationTitle("audio_preview_title").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Group {
                    Button("action_done") { stop(); dismiss() }.tint(.primary)
                    }.tint(.primary)
                } }
                .alert("podcasts_error_title", isPresented: $failed) { Button("podcasts_ok", role: .cancel) {} } message: { Text("audio_preview_error") }
                .onDisappear { stop() }
                .onChange(of: first) { stop() }.onChange(of: second) { stop() }
        }
    }

    private func trackCard(first isFirst: Bool) -> some View {
        let song = own ? library.songs.first { $0.id == (isFirst ? first : second) } : nil
        return VStack(alignment: .leading, spacing: 12) {
            Text(isFirst ? "audio_preview_first" : "audio_preview_second").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                CachedSongArtwork(data: song?.coverData ?? song?.imageData)
                    .frame(width: 76, height: 76).clipShape(.rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 6) {
                    if let song {
                        Text(song.title).font(.headline).lineLimit(2)
                        Text(song.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Text(own ? "audio_preview_choose" : (isFirst ? "audio_demo_a" : "audio_demo_b")).font(.headline)
                        Text(own ? "audio_preview_choose_detail" : "audio_demo_detail").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if own { songPicker(isFirst ? "audio_preview_first" : "audio_preview_second", selection: isFirst ? $first : $second) }
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
        let request = UUID(); generation = request
        task = Task { @MainActor in
            do {
                try await player.startTransitionPreview(first: urls.0, second: urls.1)
                guard !Task.isCancelled, generation == request else { return }
                guard player.isPreviewing else { loading = false; playing = false; return }
                loading = false; playing = true
                player.previewFinished = { loading = false; playing = false }
            } catch {
                guard !Task.isCancelled, generation == request else { return }
                failed = true; loading = false; playing = false
            }
        }
    }
    private func stop() { generation = UUID(); task?.cancel(); task = nil; player.stopTransitionPreview(); loading = false; playing = false }
}
