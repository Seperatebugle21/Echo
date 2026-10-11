import SwiftUI

struct EchoIntelligenceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var conversation = AIConversationController()
    @State private var speech = AISpeechController()
    @State private var showHistory = false
    @State private var showTranscript = false
    @State private var showSettings = false
    @State private var rendererError: String?
    @State private var voiceTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool
    private let settings = AISettingsStore.shared
    private let gold = Color(red: 0.91, green: 0.71, blue: 0.44)
    private var phase: UniversePhase { speech.listening ? .listening : speech.speaking ? .speaking : conversation.phase }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                header
                ZStack(alignment: .bottom) {
                    IntelligenceUniverse(phase: phase, level: speech.level, settings: settings.value,
                                         active: scenePhase == .active && !showHistory && !showSettings && !showTranscript,
                                         reducedMotion: reduceMotion, displayScale: displayScale) { rendererError = $0 }
                    if let rendererError { Text(rendererError).font(.caption).padding() }
                }
                .frame(minHeight: 130, maxHeight: .infinity)
                .layoutPriority(-1)
                status
                if !conversation.latestText.isEmpty {
                    Button { showTranscript = true; inputFocused = false } label: {
                        Text(conversation.latestText).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                            .lineLimit(4).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain).accessibilityHint("ai_expand")
                }
                if let pending = conversation.pending { confirmation(pending) }
                if let error = conversation.error ?? speech.error ?? AIHistoryStore.shared.error {
                    Text(error).font(.caption).foregroundStyle(gold).textSelection(.enabled).padding(.horizontal, 10)
                }
                input
                IntelligenceNowPlaying()
            }
            .padding(.horizontal, geometry.size.width > 600 ? 70 : 22)
            .padding(.top, 8).padding(.bottom, 8)
            .frame(maxWidth: 850).frame(maxWidth: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(gold).tint(gold).preferredColorScheme(.dark)
        .sheet(isPresented: $showHistory) { history }
        .sheet(isPresented: $showTranscript) { transcript }
        .sheet(isPresented: $showSettings) { NavigationStack { AISettingsView() } }
        .onChange(of: settings.value) { conversation.cancel(); speech.stop() }
        .onChange(of: scenePhase) { if scenePhase != .active { conversation.cancel(); voiceTask?.cancel(); speech.stop() } }
        .onChange(of: conversation.navigation) {
            if let destination = conversation.navigation {
                AppRouter.shared.intelligenceDestination = destination
                dismiss()
            }
        }
        .onDisappear { conversation.cancel(); voiceTask?.cancel(); speech.stop() }
    }
    private var header: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44).background(.white.opacity(0.07), in: .circle) }
                .accessibilityLabel("ai_close")
            Spacer()
            VStack(spacing: 4) {
                Text("ai_title").font(.system(size: 19, weight: .light)).tracking(2)
                Text("ai_subtitle").font(.caption).tracking(2).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Menu {
                Button("ai_history", systemImage: "clock") { showHistory = true }
                Button("ai_new", systemImage: "plus") { conversation.newConversation(); speech.stop() }
                Button("ai_settings", systemImage: "slider.horizontal.3") { showSettings = true }
            } label: { Image(systemName: "waveform").frame(width: 44, height: 44).background(.white.opacity(0.07), in: .circle) }
                .accessibilityLabel("ai_options")
        }.buttonStyle(.plain)
    }
    private var status: some View {
        VStack(spacing: 4) {
            Text(LocalizedStringKey(speech.listening ? "ai_listening" : speech.speaking ? "ai_speaking" : conversation.busy ? "ai_thinking" : "ai_ready"))
                .font(.caption).tracking(2)
            if let provider = conversation.providerID {
                Text(LocalizedStringKey(provider.key)).font(.caption2).foregroundStyle(.white.opacity(0.4))
            }
        }.accessibilityElement(children: .combine)
    }
    private var input: some View {
        HStack(spacing: 10) {
            Button { showHistory = true } label: { Image(systemName: "clock").frame(width: 32, height: 44) }.accessibilityLabel("ai_history")
            TextField("ai_prompt", text: $conversation.draft, axis: .vertical)
                .lineLimit(1...4).font(.subheadline).foregroundStyle(.white).focused($inputFocused)
                .submitLabel(.send).onSubmit(send)
                .accessibilityIdentifier("intelligence-input")
            if settings.value.voiceInput {
                Button {
                    if speech.listening { speech.stopListening() }
                    else {
                        conversation.cancel(); inputFocused = false
                        voiceTask = Task { await speech.startListening(update: { conversation.draft = $0 }, finished: {}) }
                    }
                } label: { Image(systemName: speech.listening ? "mic.fill" : "mic").frame(width: 38, height: 44) }
                    .accessibilityLabel(speech.listening ? "ai_stop_listening" : "ai_voice_input")
            }
            if conversation.busy || speech.speaking {
                Button { conversation.cancel(); speech.stopSpeaking() } label: { Image(systemName: "stop.fill").frame(width: 44, height: 44) }.accessibilityLabel("ai_stop")
            } else if !conversation.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.title3).foregroundStyle(.black)
                        .frame(width: 44, height: 44).background(gold.gradient, in: .circle)
                }.accessibilityLabel("ai_send").accessibilityIdentifier("intelligence-send")
            }
        }
        .padding(7).background(.white.opacity(0.05), in: .rect(cornerRadius: 30))
        .overlay { RoundedRectangle(cornerRadius: 30).strokeBorder(.white.opacity(0.19)) }
        .buttonStyle(.plain)
    }
    private func send() {
        speech.stop(); inputFocused = false
        conversation.send { speech.speak($0) }
    }
    private func confirmation(_ call: AIToolCall) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ai_confirm_action").font(.headline)
            Text(LocalizedStringKey("ai_tool_" + call.name)).font(.subheadline)
            ScrollView { Text(call.arguments).font(.caption.monospaced()).textSelection(.enabled) }.frame(maxHeight: 80)
            HStack {
                Button("ai_deny", role: .cancel) { conversation.confirm(false) }.buttonStyle(.bordered)
                Spacer()
                Button("ai_allow") { conversation.confirm(true) }.buttonStyle(.borderedProminent)
            }
        }.padding(14).background(.white.opacity(0.06), in: .rect(cornerRadius: 18))
    }
    private var transcript: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(conversation.conversation.messages.filter { $0.role != .tool && !$0.text.isEmpty }) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message.role == .user ? "ai_you" : "ai_title").font(.caption).foregroundStyle(gold)
                            Text(message.text).textSelection(.enabled).foregroundStyle(.primary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !conversation.streaming.isEmpty { Text(conversation.streaming).textSelection(.enabled) }
                }.padding(24)
            }.navigationTitle("ai_conversation").toolbar { Button("ai_done") { showTranscript = false } }
        }
    }
    private var history: some View {
        NavigationStack {
            List {
                Button("ai_new", systemImage: "plus") { conversation.newConversation(); showHistory = false }
                ForEach(AIHistoryStore.shared.conversations) { item in
                    Button {
                        speech.stop(); conversation.open(item); showHistory = false; showTranscript = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).lineLimit(2)
                            Text(item.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }.swipeActions { Button("ai_delete", role: .destructive) { AIHistoryStore.shared.delete(item.id) } }
                }
            }.navigationTitle("ai_history").toolbar { Button("ai_done") { showHistory = false } }
        }
    }
}
private struct IntelligenceNowPlaying: View {
    private let player = AudioPlayerManager.shared
    var body: some View {
        if let song = player.currentSong {
            Button { player.togglePlayPause() } label: {
                HStack(spacing: 10) {
                    if let data = song.coverData ?? song.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 34, height: 34).clipShape(.rect(cornerRadius: 7))
                    } else { Image(systemName: "music.note").frame(width: 34, height: 34) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.caption).foregroundStyle(.white).lineLimit(1)
                        Text(song.artist).font(.caption2).foregroundStyle(.gray).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 34, height: 44)
                }.padding(.horizontal, 12).frame(maxWidth: 320).background(.white.opacity(0.035), in: .rect(cornerRadius: 15))
            }.buttonStyle(.plain).accessibilityLabel(player.isPlaying ? "ai_pause" : "ai_resume")
        }
    }
}
