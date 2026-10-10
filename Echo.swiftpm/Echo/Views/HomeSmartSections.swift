import SwiftUI

struct HomeSmartSections: View {
    let coverWidth: CGFloat
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = HomeSmartSectionsModel.shared
    @State private var selectedSong: Song?
    @State private var showQueue = false
    @State private var feedback = 0
    @State private var refreshing = false
    @State private var surpriseBusy = false
    @State private var smartSurprise = true
    @State private var confirmation: Song?
    @State private var activeVibe: MusicVibe?
    private let engine = RecommendationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !model.gems.isEmpty { hiddenGems }
            weeklyMusic
            pickVibe
            surpriseMe
            echoFlow
            if !model.albums.isEmpty { revisitingAlbums }
            if !model.periods.isEmpty { timeMachine }
            upNext
        }
        .task(id: library.songRevision) { await model.prepare(library: library); await model.updateListening() }
        .task(id: library.favoriteRevision) { await model.prepare(library: library) }
        .task(id: engine.revision) { await model.updateListening() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await model.prepare(library: library); await model.updateListening() } } }
        .sheet(item: $selectedSong) { SongOptionsView(song: $0) }
        .sheet(isPresented: $showQueue) { QueueView() }
        .alert("smart_playback_error", isPresented: Binding(get: { model.errorKey != nil }, set: { if !$0 { model.dismissError() } })) {
            Button("action_close") { model.dismissError() }
        } message: { Text(LocalizedStringKey(model.errorKey ?? "smart_file_unavailable")) }
        .sensoryFeedback(.selection, trigger: feedback)
    }

    private var hiddenGems: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HomeSectionTitle(title: "smart_hidden_gems")
                Spacer()
                Button {
                    refreshing = true
                    Task { await model.refreshGems(); refreshing = false; feedback += 1 }
                } label: {
                    Image(systemName: "arrow.clockwise").rotationEffect(.degrees(refreshing && !reduceMotion ? 180 : 0))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: refreshing).frame(width: 44, height: 44)
                }.buttonStyle(HomePressStyle()).disabled(refreshing).accessibilityLabel("smart_refresh_gems")
            }.padding(.horizontal, 20)
            HomeSongRail(songs: model.gems, width: coverWidth, play: { play($0, model.gems) }, options: { selectedSong = $0 })
        }
    }
    private var weeklyMusic: some View {
        section("smart_week") {
            NavigationLink {
                ListeningStatisticsView().toolbarVisibility(.visible, for: .navigationBar)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        metric(SmartMusicFormatting.duration(model.week.seconds), "smart_listening_time")
                        metric(model.week.plays.formatted(), "smart_songs")
                        metric(model.week.artists.formatted(), "smart_artists")
                    }
                    HStack {
                        if let artist = model.week.topArtists.first {
                            Text(artist.name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        } else { Text("smart_tracking_now").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                }.smartCard()
            }.buttonStyle(HomePressStyle()).accessibilityIdentifier("smart-week-open")
        }
    }
    private func metric(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.bold()).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var pickVibe: some View {
        section("smart_vibe") {
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                ForEach(MusicVibe.allCases) { vibe in
                    Button {
                        if let songs = model.vibes[vibe], let first = songs.first, model.play(first, queue: songs) {
                            activeVibe = vibe; feedback += 1
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: vibe.symbol).font(.title3).foregroundStyle(vibeColor(vibe))
                            Text(LocalizedStringKey("smart_vibe_" + vibe.rawValue)).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: activeVibe == vibe && player.isPlaying ? "speaker.wave.2.fill" : "play.fill").font(.caption)
                        }.smartCard().frame(maxWidth: .infinity)
                    }.buttonStyle(HomePressStyle()).disabled(model.available.isEmpty)
                        .accessibilityIdentifier("smart-vibe-" + vibe.rawValue)
                }
            }
        }
    }
    private func vibeColor(_ vibe: MusicVibe) -> Color {
        switch vibe { case .chill: return .teal; case .energy: return .accentColor; case .focus: return .indigo; case .throwback: return .orange }
    }
    private var surpriseMe: some View {
        section("smart_surprise") {
            Button(action: surprise) {
                HStack(spacing: 12) {
                    Image(systemName: "dice.fill").font(.title2).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("smart_unexpected").font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                        if let confirmation { Text(confirmation.title).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: surpriseBusy ? "hourglass" : "shuffle").font(.body.bold()).frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.12), in: .circle)
                }.smartCard()
            }.buttonStyle(HomePressStyle()).disabled(model.available.isEmpty || surpriseBusy)
                .accessibilityIdentifier("smart-surprise-play")
                .contextMenu {
                    Button("smart_totally_random", systemImage: "dice") { smartSurprise = false; surprise() }
                    Button("smart_smart_surprise", systemImage: "sparkles") { smartSurprise = true; surprise() }
                }
        }
    }
    private func surprise() {
        guard !surpriseBusy else { return }; surpriseBusy = true
        Task { confirmation = await model.surprise(smart: smartSurprise); surpriseBusy = false; if confirmation != nil { feedback += 1 } }
    }
    private var echoFlow: some View {
        section("smart_flow") {
            HStack(spacing: 12) {
                Image(systemName: "waveform").font(.title)
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor, options: .repeating, isActive: player.flowActive && player.isPlaying && !reduceMotion)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("smart_flow").font(.headline)
                        if player.flowActive { Circle().fill(Color.accentColor).frame(width: 6, height: 6).accessibilityLabel("smart_flow_active") }
                    }
                    Text("smart_flow_detail").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Menu {
                        Picker("smart_flow_mode", selection: Bindable(player).flowMode) {
                            ForEach(EchoFlowMode.allCases, id: \.self) { Text(LocalizedStringKey("smart_flow_" + $0.rawValue)).tag($0) }
                        }
                        if player.flowActive { Button("smart_flow_stop", systemImage: "stop.fill") { player.stopEchoFlow(); feedback += 1 }.accessibilityIdentifier("smart-flow-stop") }
                        Text("smart_flow_repeat_rule")
                    } label: {
                        Label(LocalizedStringKey("smart_flow_" + player.flowMode.rawValue), systemImage: "chevron.down")
                            .font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
                    }.accessibilityLabel("smart_flow_mode").accessibilityIdentifier("smart-flow-mode")
                }
                Spacer(minLength: 0)
                Button {
                    if player.flowActive { player.togglePlayPause() } else { player.startEchoFlow() }
                    feedback += 1
                } label: { roundIcon(player.flowActive && player.isPlaying ? "pause.fill" : "play.fill") }
                    .buttonStyle(HomePressStyle()).disabled(model.available.isEmpty)
                    .accessibilityLabel(player.flowActive ? (player.isPlaying ? "home_pause" : "home_play") : "smart_flow_start")
                    .accessibilityIdentifier("smart-flow-play")
            }.smartCard().overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.accentColor.opacity(player.flowActive ? 0.35 : 0.12)) }
        }
    }
    private var revisitingAlbums: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionLink(title: "smart_revisit") { SmartAlbumsOverview(albums: model.albums) }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array(model.albums.prefix(12))) { album in
                        NavigationLink { AlbumDetailView(album: album).toolbarVisibility(.visible, for: .navigationBar) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                if let song = album.songs.first {
                                    SongArtworkView(song: song, cornerRadius: 13).frame(width: coverWidth, height: coverWidth).homeCoverShadow()
                                }
                                Text(album.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.frame(width: coverWidth, alignment: .leading)
                        }.buttonStyle(HomePressStyle()).albumFavoriteActions(FavoriteAlbum(album: album))
                    }
                }.padding(.horizontal, 20).padding(.vertical, 8)
            }.scrollIndicators(.hidden)
        }
    }
    private var timeMachine: some View {
        section("smart_time_machine") {
            VStack(alignment: .leading, spacing: 10) {
                if model.periods.count > 1 {
                    Picker("smart_period", selection: $model.selectedPeriod) {
                        ForEach(model.periods) { period in Text(SmartMusicFormatting.period(period.monthsAgo)).tag(period.id) }
                    }.pickerStyle(.menu)
                }
                if let period = model.periods.first(where: { $0.id == model.selectedPeriod }) {
                    let indexed = Dictionary(uniqueKeysWithValues: model.available.map { ($0.id, $0) })
                    let songs = period.songIDs.compactMap { indexed[$0] }
                    HStack(spacing: 10) {
                        NavigationLink {
                            SmartMusicCollectionView(title: SmartMusicFormatting.period(period.monthsAgo), songIDs: period.songIDs)
                                .toolbarVisibility(.visible, for: .navigationBar)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.accentColor)
                                HStack(spacing: -12) {
                                    ForEach(Array(songs.prefix(3))) { SongArtworkView(song: $0, cornerRadius: 8).frame(width: 36, height: 36).homeCoverShadow() }
                                }.accessibilityHidden(true)
                                Text(SmartMusicFormatting.period(period.monthsAgo)).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption)
                            }.contentShape(.rect)
                        }.buttonStyle(HomePressStyle())
                        Button { if let first = songs.first { play(first, songs) } } label: { roundIcon("play.fill") }
                            .buttonStyle(HomePressStyle()).accessibilityLabel("action_play_now")
                    }
                }
            }.smartCard()
        }
    }
    private var upNext: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HomeSectionTitle(title: "smart_up_next"); Spacer()
                Button { showQueue = true } label: { Image(systemName: "list.bullet").frame(width: 44, height: 44) }
                    .buttonStyle(HomePressStyle()).accessibilityLabel("queue_action").accessibilityIdentifier("smart-queue-open")
            }
            if player.homeUpcomingSongs.isEmpty {
                HStack {
                    Text("smart_queue_empty").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("smart_flow_start") { player.startEchoFlow(); feedback += 1 }.font(.caption.bold()).disabled(model.available.isEmpty)
                }.padding(.vertical, 8)
            } else {
                ForEach(Array(player.homeUpcomingSongs.enumerated()), id: \.offset) { _, song in
                    Button {
                        if player.queue.contains(where: { $0.id == song.id }) { player.playFromQueue(song) }
                        else { play(song, [song]) }
                        feedback += 1
                    } label: {
                        HStack(spacing: 10) {
                            SongArtworkView(song: song, cornerRadius: 8).frame(width: 42, height: 42).homeCoverShadow().accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: player.flowActive && player.flowSongIDs.contains(song.id) ? "waveform" : "text.line.first.and.arrowtriangle.forward")
                                .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                        }.padding(.vertical, 4).contentShape(.rect)
                    }.buttonStyle(HomePressStyle())
                        .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in selectedSong = song })
                        .accessibilityAction(named: Text("home_song_options")) { selectedSong = song }
                }
            }
        }.padding(.horizontal, 20)
    }
    private func play(_ song: Song, _ songs: [Song]) { if model.play(song, queue: songs) { feedback += 1 } }
    private func roundIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.body.bold()).foregroundStyle(Color.accentColor).frame(width: 44, height: 44)
            .background(Color.accentColor.opacity(0.12), in: .circle).contentShape(.circle)
    }
    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { HomeSectionTitle(title: title); content() }.padding(.horizontal, 20)
    }
}

extension View {
    func smartCard() -> some View {
        self.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.06)) }
            .contentShape(.rect(cornerRadius: 18))
    }
}
