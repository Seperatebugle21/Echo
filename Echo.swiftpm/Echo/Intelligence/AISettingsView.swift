import SwiftUI
import AVFoundation

struct AISettingsView: View {
    @Bindable private var store = AISettingsStore.shared
    @State private var credential = ""
    @State private var notice: String?
    @State private var checking = false
    @State private var checkTask: Task<Void, Never>?
    @State private var clearHistory = false
    @State private var deleteModel = false
    private let local = QwenModelStore.shared
    var body: some View {
        Form {
            Section("ai_provider") {
                Picker("ai_provider", selection: $store.value.provider) {
                    ForEach(AIProviderID.allCases) { provider in Text(LocalizedStringKey(provider.key)).tag(provider) }
                }
                Toggle("ai_offline", isOn: $store.value.offlineOnly)
                Text("ai_offline_detail").font(.caption).foregroundStyle(.secondary)
                Text(AIProviderManager.appleAvailable ? "ai_apple_available" : "ai_apple_unavailable").font(.caption)
                if store.value.provider.isOnline || store.value.provider == .automatic {
                    Toggle("ai_cloud_consent", isOn: $store.value.cloudConsent).disabled(store.value.offlineOnly)
                    Text("ai_cloud_detail").font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.value.provider.isOnline { networkSettings }
            if store.value.provider == .qwen || store.value.provider == .automatic { localSettings }
            Section("ai_permissions") {
                Picker("ai_permissions", selection: $store.value.permission) {
                    ForEach(AIPermission.allCases) { mode in Text(LocalizedStringKey(mode.key)).tag(mode) }
                }
                Text("ai_permissions_detail").font(.caption).foregroundStyle(.secondary)
            }
            Section("ai_voice") {
                Toggle("ai_voice_input", isOn: $store.value.voiceInput)
                Toggle("ai_spoken", isOn: $store.value.spokenResponses)
                Text("ai_voice_detail").font(.caption).foregroundStyle(.secondary)
                Picker("ai_voice", selection: $store.value.voiceID) {
                    Text("ai_default").tag("")
                    ForEach(AVSpeechSynthesisVoice.speechVoices(), id: \.identifier) { voice in Text("\(voice.name) · \(voice.language)").tag(voice.identifier) }
                }
                Picker("ai_music_during_speech", selection: $store.value.speechBehavior) {
                    Text("ai_mix").tag("mix"); Text("ai_duck").tag("duck"); Text("ai_interrupt").tag("interrupt")
                }
            }
            Section("ai_universe") {
                Toggle("ai_auto_rotate", isOn: $store.value.autoRotate)
                Slider(value: $store.value.intensity, in: 0...1) { Text("ai_intensity") }
                Picker("ai_quality", selection: $store.value.quality) {
                    Text("ai_default").tag("automatic"); Text("ai_low").tag("low"); Text("ai_high").tag("high")
                }
                Text("ai_motion_detail").font(.caption).foregroundStyle(.secondary)
            }
            Section("ai_history") {
                Toggle("ai_save_history", isOn: $store.value.saveHistory)
                Text("ai_history_detail").font(.caption).foregroundStyle(.secondary)
                NavigationLink("ai_history") { AIHistorySettingsView() }
                Button("ai_clear_history", role: .destructive) { clearHistory = true }
            }
            if let notice { Section { Text(notice).font(.caption).textSelection(.enabled) } }
        }
        .navigationTitle("ai_title").echoBackground()
        .onAppear(perform: loadCredential)
        .onChange(of: store.value.provider) { checkTask?.cancel(); loadCredential() }
        .onChange(of: store.value.offlineOnly) { checkTask?.cancel() }
        .onChange(of: store.value.cloudConsent) { checkTask?.cancel() }
        .onDisappear { checkTask?.cancel(); credential = "" }
        .confirmationDialog("ai_clear_history", isPresented: $clearHistory, titleVisibility: .visible) {
            Button("ai_delete", role: .destructive) { AIHistoryStore.shared.clear() }
        }
        .confirmationDialog("ai_delete_model", isPresented: $deleteModel, titleVisibility: .visible) {
            Button("ai_delete", role: .destructive) { do { try local.delete() } catch { notice = error.localizedDescription } }
        }
    }
    private var networkSettings: some View {
        Section("ai_connection") {
            if store.value.provider == .custom {
                TextField("ai_server_url", text: $store.value.customURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("ai_model", text: $store.value.customModel).textInputAutocapitalization(.never).autocorrectionDisabled()
            } else if store.value.provider == .openAI {
                TextField("ai_model", text: $store.value.openAIModel).textInputAutocapitalization(.never).autocorrectionDisabled()
            } else { TextField("ai_model", text: $store.value.geminiModel).textInputAutocapitalization(.never).autocorrectionDisabled() }
            SecureField("ai_key", text: $credential).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("ai_save_key") {
                do { try AICredentials.save(credential.trimmingCharacters(in: .whitespacesAndNewlines), provider: store.value.provider); notice = EchoLocalization.string("ai_saved") }
                catch { notice = error.localizedDescription }
            }
            Button("ai_check") {
                checking = true; notice = nil
                let settings = store.value
                let enteredKey = credential.trimmingCharacters(in: .whitespacesAndNewlines)
                checkTask = Task {
                    defer { checking = false }
                    do {
                        let provider = NetworkAIProvider(id: settings.provider, settings: settings, credentialOverride: enteredKey)
                        _ = try await provider.respond(messages: [AIMessage(role: .user, text: "Reply OK.")], instructions: "Connection test. No tools.", tools: [], update: { _ in }, execute: { _ in throw AIError.permission })
                        try Task.checkCancellation(); notice = EchoLocalization.string("ai_connected")
                    } catch is CancellationError {} catch { notice = error.localizedDescription }
                }
            }.disabled(checking || store.value.offlineOnly || !store.value.cloudConsent)
            Text("ai_check_detail").font(.caption).foregroundStyle(.secondary)
            if checking { ProgressView() }
        }
    }
    private var localSettings: some View {
        Section("ai_provider_qwen") {
            Text("Qwen3 · 0.6B · 4-bit").font(.headline)
            Text("ai_qwen_detail").font(.caption).foregroundStyle(.secondary)
            if !QwenModelStore.compatible { Text("ai_qwen_unavailable").font(.caption) }
            if local.downloading {
                ProgressView(value: local.progress)
                Button("ai_cancel_download") { local.cancel() }
            } else if local.installed {
                Text(ByteCountFormatter.string(fromByteCount: local.storageBytes, countStyle: .file))
                Button("ai_delete_model", role: .destructive) { deleteModel = true }
            } else { Button("ai_download_model") { local.download() }.disabled(!QwenModelStore.compatible) }
            if let error = local.error { Text(error).font(.caption) }
        }
    }
    private func loadCredential() { credential = AICredentials.read(store.value.provider) ?? ""; notice = nil }
}
private struct AIHistorySettingsView: View {
    private let history = AIHistoryStore.shared
    var body: some View {
        List {
            Section("ai_history") {
                ForEach(history.conversations) { conversation in
                    NavigationLink(conversation.title) {
                        ScrollView { VStack(alignment: .leading, spacing: 20) {
                            ForEach(conversation.messages.filter { $0.role != .tool && !$0.text.isEmpty }) { message in
                                Text(message.role == .assistant ? AIResponseText.visible(message.text) : message.text).textSelection(.enabled)
                            }
                        }.padding() }.navigationTitle("ai_conversation")
                    }.swipeActions { Button("ai_delete", role: .destructive) { history.delete(conversation.id) } }
                }
            }
            Section("ai_action_history") {
                ForEach(history.actions) { record in
                    VStack(alignment: .leading) {
                        Text(LocalizedStringKey("ai_tool_" + record.name))
                        Text(record.date, style: .time).font(.caption).foregroundStyle(.secondary)
                        Text(record.result).font(.caption).lineLimit(6).textSelection(.enabled)
                    }
                }
            }
        }.navigationTitle("ai_history")
    }
}
