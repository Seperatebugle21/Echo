import SwiftUI
import Charts

enum SmartMusicFormatting {
    static func duration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.calendar?.locale = Locale(identifier: UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en")
        return formatter.string(from: max(0, seconds.isFinite ? seconds : 0)) ?? "0"
    }
    static func period(_ months: Int) -> String { EchoLocalization.string("smart_period_\(months)") }
}

struct ListeningStatisticsView: View {
    @State private var model = HomeSmartSectionsModel.shared
    private let engine = RecommendationManager.shared
    var body: some View {
        List {
            Section("smart_week") {
                statistic("smart_listening_time", SmartMusicFormatting.duration(model.week.seconds))
                statistic("smart_songs", model.week.plays.formatted())
                statistic("smart_artists", model.week.artists.formatted())
                Text("smart_tracking_since \(engine.trackingStartedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("smart_daily_time") {
                Chart(model.week.days) { day in
                    BarMark(x: .value(EchoLocalization.string("smart_day"), day.id, unit: .day),
                            y: .value(EchoLocalization.string("smart_minutes"), day.seconds / 60))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel(day.id.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(SmartMusicFormatting.duration(day.seconds))
                }.frame(height: 150)
            }
            if !model.week.topSongs.isEmpty {
                Section("smart_top_songs") {
                    ForEach(model.week.topSongs) { song in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) { Text(song.title); Text(song.artist).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Text(SmartMusicFormatting.duration(song.seconds)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("smart_top_artists") {
                    ForEach(model.week.topArtists) { artist in statistic(Text(verbatim: artist.name), SmartMusicFormatting.duration(artist.seconds)) }
                }
            }
            if engine.trackingStartedAt <= model.previousWeek.interval.start && model.previousWeek.seconds > 0 {
                Section("smart_previous_week") {
                    statistic("smart_listening_time", SmartMusicFormatting.duration(model.previousWeek.seconds))
                    let difference = (model.week.seconds / model.previousWeek.seconds - 1) * 100
                    statistic("smart_week_change", difference.formatted(.number.precision(.fractionLength(0)).sign(strategy: .always())) + "%")
                }
            } else { Section { Text("smart_history_unavailable").font(.caption).foregroundStyle(.secondary) } }
        }
        .echoBackground().navigationTitle("smart_week").navigationBarTitleDisplayMode(.inline)
        .task(id: engine.revision) { await model.updateListening() }
    }
    private func statistic(_ key: LocalizedStringKey, _ value: String) -> some View { statistic(Text(key), value) }
    private func statistic(_ label: Text, _ value: String) -> some View {
        HStack { label; Spacer(); Text(value).foregroundStyle(.secondary).monospacedDigit() }
    }
}

struct SmartAlbumsOverview: View {
    let albums: [AlbumGroup]
    @Environment(MusicLibraryManager.self) private var library
    @State private var resolved: [AlbumGroup] = []
    var body: some View {
        List(resolved) { album in
                NavigationLink { AlbumDetailView(album: album) } label: {
                    HStack(spacing: 12) {
                        if let song = album.songs.first { SongArtworkView(song: song, cornerRadius: 10).frame(width: 52, height: 52) }
                        VStack(alignment: .leading, spacing: 3) { Text(album.name); Text(album.artist).font(.caption).foregroundStyle(.secondary) }
                    }
                }.albumFavoriteActions(FavoriteAlbum(album: album), swipe: true)
        }.echoBackground().navigationTitle("smart_revisit").navigationBarTitleDisplayMode(.inline)
            .task(id: library.songRevision) {
                let songs = library.songs, ids = albums.map(\.id)
                resolved = await Task.detached(priority: .utility) {
                    let groups = Dictionary(uniqueKeysWithValues: LibraryAlbums.groups(from: songs).map { ($0.id, $0) })
                    return ids.compactMap { groups[$0] }
                }.value
            }
    }
}

struct SmartMusicCollectionView: View {
    let title: String
    let songIDs: [UUID]
    @Environment(MusicLibraryManager.self) private var library
    @State private var songs: [Song] = []
    @State private var selectedSong: Song?
    private let model = HomeSmartSectionsModel.shared
    var body: some View {
        List {
            if let first = songs.first {
                HStack {
                    Button("action_play_now", systemImage: "play.fill") { _ = model.play(first, queue: songs) }
                    Spacer()
                    Button("smart_shuffle", systemImage: "shuffle") {
                        let shuffled = songs.shuffled()
                        if let first = shuffled.first { _ = model.play(first, queue: shuffled) }
                    }
                }.buttonStyle(.borderless).foregroundStyle(Color.accentColor)
            }
            ForEach(songs) { song in
                Button { _ = model.play(song, queue: songs) } label: { LibrarySongRow(song: song) }
                    .buttonStyle(.plain)
                    .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in selectedSong = song })
                    .accessibilityAction(named: Text("home_song_options")) { selectedSong = song }
            }
            if songs.isEmpty { Text("smart_collection_empty").foregroundStyle(.secondary) }
        }.echoBackground().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .task(id: library.songRevision) {
                songs = songIDs.compactMap { library.song(withID: $0) }.filter {
                    library.getURL(for: $0).map { FileManager.default.fileExists(atPath: $0.path) } == true
                }
            }
            .sheet(item: $selectedSong) { SongOptionsView(song: $0) }
    }
}
