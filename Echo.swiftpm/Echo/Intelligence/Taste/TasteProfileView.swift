import SwiftUI

/// "What Echo knows about your taste": insights, evolution timeline, corrections and controls.
struct TasteProfileView: View {
    @State private var taste = TasteAIManager.shared
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Toggle("taste_enabled", isOn: $taste.enabled)
                Text("taste_enabled_detail").font(.caption).foregroundStyle(.secondary)
            }
            if taste.enabled {
                Section("taste_summary") {
                    if taste.profile.summary.isEmpty {
                        Text("taste_empty").foregroundStyle(.secondary)
                    } else {
                        Text(taste.profile.summary)
                        if let updated = taste.profile.updatedAt {
                            Text(updated, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        Task { await taste.refreshProfile() }
                    } label: {
                        HStack {
                            Text("taste_refresh")
                            Spacer()
                            if taste.status == .analyzing { ProgressView() }
                        }
                    }.disabled(taste.status == .analyzing || !taste.active)
                    if case .failed(let message) = taste.status { Text(message).font(.caption).foregroundStyle(.red) }
                    if !taste.active { Text("taste_requires_intelligence").font(.caption).foregroundStyle(.secondary) }
                }
                if !taste.profile.insights.isEmpty {
                    Section {
                        ForEach(taste.profile.insights) { insight in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.text)
                                if !insight.evidence.isEmpty {
                                    Text(insight.evidence.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button("taste_wrong", role: .destructive) { taste.forget(insight) }
                            }
                            .contextMenu {
                                Button("taste_wrong", systemImage: "hand.thumbsdown", role: .destructive) { taste.forget(insight) }
                            }
                        }
                    } header: { Text("taste_insights") } footer: { Text("taste_insights_footer") }
                }
                if taste.profile.history.count > 1 {
                    Section("taste_evolution") {
                        ForEach(taste.profile.history.reversed()) { snapshot in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snapshot.date, format: .dateTime.day().month().year()).font(.caption.bold()).foregroundStyle(.secondary)
                                Text(snapshot.summary).font(.subheadline)
                            }
                        }
                    }
                }
                if !taste.profile.corrections.isEmpty {
                    Section("taste_corrections") {
                        ForEach(Array(taste.profile.corrections.enumerated()), id: \.offset) { _, text in
                            Text(text).font(.caption).foregroundStyle(.secondary).strikethrough()
                        }
                    }
                }
                Section {
                    Text("taste_privacy").font(.caption).foregroundStyle(.secondary)
                    Button("taste_clear", role: .destructive) { confirmClear = true }
                }
            }
        }
        .navigationTitle(Text("taste_title"))
        .confirmationDialog("taste_clear", isPresented: $confirmClear) {
            Button("taste_clear", role: .destructive) { taste.clearProfile() }
        }
    }
}

/// Home section "For you, now": curated songs with the curator's personal reason.
struct TasteHomeSection: View {
    let play: (Song, [Song]) -> Void
    let options: (Song) -> Void
    @State private var taste = TasteAIManager.shared

    var body: some View {
        if taste.active {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HomeSectionTitle(title: "taste_home_title")
                    Spacer()
                    if taste.status == .curating { ProgressView().frame(width: 44, height: 44) }
                    else {
                        Button { Task { await taste.refreshHomeIfNeeded(force: true) } } label: {
                            Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                        }.buttonStyle(HomePressStyle()).accessibilityLabel("taste_refresh_picks")
                    }
                }
                if taste.homePicks.isEmpty {
                    Text(LocalizedStringKey(taste.status == .curating ? "taste_curating" : "taste_home_empty")).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(taste.homePicks.prefix(6)) { song in
                        Button { play(song, taste.homePicks) } label: {
                            HStack(spacing: 10) {
                                SongArtworkView(song: song, cornerRadius: 8).frame(width: 46, height: 46).homeCoverShadow().accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    if let reason = taste.reason(for: song.id) {
                                        Label(reason, systemImage: "sparkles").font(.caption2).foregroundStyle(Color.accentColor).lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }.padding(.vertical, 3).contentShape(.rect)
                        }.buttonStyle(HomePressStyle())
                            .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in options(song) })
                            .accessibilityAction(named: Text("home_song_options")) { options(song) }
                    }
                    Button {
                        Task { await taste.curateQueue(startNow: AudioPlayerManager.shared.currentSong == nil) }
                    } label: {
                        Label("taste_curate_queue", systemImage: "sparkles").font(.subheadline.bold())
                    }.buttonStyle(.bordered).disabled(taste.status == .curating)
                }
            }
            .padding(.horizontal, 20)
            .task { await taste.refreshHomeIfNeeded() }
        }
    }
}
