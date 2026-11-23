import SwiftUI

/// A compact anchored popover keeps the native AirPlay route picker interactive.
struct NowPlayingOptionsButton: View {
    let song: Song
    let addToPlaylist: () -> Void
    let showLyrics: () -> Void
    @Environment(AudioPlayerManager.self) private var player
    @Environment(MusicLibraryManager.self) private var library
    @State private var expanded = false
    @State private var pending: Action?
    @State private var destination: Destination?
    private enum Action { case flow, shuffle, playlist, lyrics, artist, album, sleep }
    private enum Destination: String, Identifiable {
        case artist, album, sleep
        var id: String { rawValue }
    }

    var body: some View {
        Button { expanded = true } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .overlay(alignment: .topTrailing) {
                    if player.sleepTimer.isActive {
                        Image(systemName: "moon.fill").font(.caption2).foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("player_more_options")
        .popover(isPresented: $expanded, arrowEdge: .top) {
            ScrollView {
                VStack(spacing: 2) {
                    if song.podcastEpisodeID == nil {
                        action("smart_flow_start", icon: "waveform", .flow)
                        action(player.shuffleEnabled ? "player_shuffle_off" : "player_shuffle_on",
                               icon: "shuffle", .shuffle, selected: player.shuffleEnabled)
                        Divider().padding(.vertical, 5)
                        action("add_to_playlist_action", icon: "music.note.list", .playlist)
                        action("lyrics_action", icon: "quote.bubble", .lyrics)
                        Divider().padding(.vertical, 5)
                        action("player_go_artist", icon: "person", .artist)
                            .disabled(ArtistCredits.names(for: song).isEmpty)
                        action("player_go_album", icon: "square.stack", .album)
                            .disabled(album == nil)
                        Divider().padding(.vertical, 5)
                    } else if let id = song.podcastEpisodeID,
                              let episode = PodcastStore.shared.state.episodes[id] {
                        PodcastEpisodeMenu(episode: episode)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        Divider()
                    }
                    // The whole row opens AirPlay, like the other rows: the system
                    // route picker is stretched invisibly over it.
                    HStack {
                        Label("AirPlay", systemImage: "airplay.audio")
                        Spacer()
                    }
                    .padding(12).frame(minHeight: 44)
                    .overlay {
                        AirPlayButton(tintColor: .clear, activeTintColor: .clear)
                            .accessibilityLabel("AirPlay")
                    }
                    Button { select(.sleep) } label: {
                        HStack {
                            Label("sleep_title", systemImage: "moon")
                            Spacer()
                            SleepTimerStatus(state: player.sleepTimer).font(.caption).foregroundStyle(.secondary)
                        }.padding(12).frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }.padding(8)
            }
            .frame(width: 310).frame(maxHeight: 530)
            .foregroundStyle(.primary)
            .presentationCompactAdaptation(.popover)
            .onDisappear { performPendingAction() }
        }
        .sheet(item: Binding(get: { destination == .sleep ? destination : nil },
                             set: { if $0 == nil { destination = nil } })) { _ in
            SleepTimerView()
        }
        // Artist and album open full screen, with a back button, like a pushed page.
        .fullScreenCover(item: Binding(get: { destination == .sleep ? nil : destination },
                                       set: { if $0 == nil { destination = nil } })) { destination in
            switch destination {
            case .sleep: EmptyView()
            case .artist:
                PlayerArtistDestination(song: song)
            case .album:
                if let album {
                    NavigationStack {
                        AlbumDetailView(album: album)
                            .playerDestinationBackButton { self.destination = nil }
                    }
                }
            }
        }
    }

    private var album: AlbumGroup? {
        guard let name = song.album, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let identity = LibraryAlbumDestination(name: name, artist: song.artist).identity
        return LibraryAlbums.groups(from: library.songs).first { $0.id == identity }
    }
    private func action(_ key: String, icon: String, _ action: Action, selected: Bool = false) -> some View {
        Button { select(action) } label: {
            HStack {
                Label(LocalizedStringKey(key), systemImage: icon)
                Spacer()
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }.padding(12).frame(minHeight: 44).contentShape(.rect)
        }.buttonStyle(.plain)
    }
    private func select(_ action: Action) { pending = action; expanded = false }
    private func performPendingAction() {
        guard let pending else { return }
        self.pending = nil
        switch pending {
        case .flow: player.startEchoFlow(from: song)
        case .shuffle: player.toggleShuffle()
        case .playlist: addToPlaylist()
        case .lyrics: showLyrics()
        case .artist: destination = .artist
        case .album: destination = .album
        case .sleep: destination = .sleep
        }
    }
}

private struct PlayerArtistDestination: View {
    let song: Song
    @Environment(MusicLibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let artists = ArtistCredits.navigationGroups(for: song, indexedGroups: library.artistGroupsByID)
        NavigationStack {
            Group {
                if artists.count == 1, let artist = artists.first { ArtistDetailView(artist: artist) }
                else {
                    List(artists) { artist in
                        NavigationLink { ArtistDetailView(artist: artist) } label: { Text(artist.name) }
                    }.navigationTitle("nowplaying_choose_artist")
                }
            }
            .playerDestinationBackButton { dismiss() }
        }
    }
}

private extension View {
    /// The back chevron of a page opened full screen from the player.
    func playerDestinationBackButton(_ close: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: close) {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("action_close")
                .tint(.primary)
            }
        }
    }
}

struct SleepTimerStatus: View {
    let state: SleepTimerState
    var body: some View {
        if let deadline = state.deadline {
            Text(timerInterval: Date()...max(Date(), deadline), countsDown: true)
                .monospacedDigit().fixedSize()
        } else if state.songID != nil { Text("sleep_end_short") }
    }
}

struct SleepTimerView: View {
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 30
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 16) {
                        CustomizationIcon(symbol: "moon.zzz.fill", size: 56)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("sleep_title").font(.title2.bold())
                            if player.sleepTimer.isActive { SleepTimerStatus(state: player.sleepTimer).font(.title3) }
                            else { Text("sleep_detail").font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                        ForEach([15, 30, 45, 60], id: \.self) { duration in
                            Button { player.startSleepTimer(minutes: duration); dismiss() } label: {
                                Text("sleep_minutes \(duration)").font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .customizationSurface()
                            }.buttonStyle(.plain)
                        }
                    }
                    VStack(spacing: 16) {
                        Stepper(value: $minutes, in: 1...720, step: 1) { Text("sleep_minutes \(minutes)").monospacedDigit() }
                        Button("sleep_custom_start") { player.startSleepTimer(minutes: minutes); dismiss() }
                            .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    }.padding(18).customizationSurface()
                    Button {
                        player.sleepAtEndOfItem(); dismiss()
                    } label: {
                        Label(player.isPodcast ? "sleep_end_episode" : "sleep_end_song", systemImage: "moon.stars")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.bordered).disabled(player.currentSong == nil)
                    if player.sleepTimer.isActive {
                        Button("sleep_cancel", role: .destructive) { player.cancelSleepTimer(); dismiss() }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }.echoBackground().navigationTitle("sleep_title").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Group {
                    Button("action_done") { dismiss() }.tint(.primary)
                    }.tint(.primary)
                } }
        }
    }
}
