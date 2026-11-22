import SwiftUI
import Charts
import UIKit

/// "Echo Recap": listening totals, rankings and charts per week, month, year or all time.
struct ListeningRecapView: View {
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let engine = RecommendationManager.shared

    @State private var period = ListeningRecapPeriod.month
    @State private var offset = 0
    @State private var recap: ListeningRecap?
    @State private var earliest: Date?
    @State private var sharePayload: RecapShareImage?
    @State private var feedback = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Picker("recap_period_picker", selection: $period) {
                    ForEach(ListeningRecapPeriod.allCases) { Text(LocalizedStringKey($0.titleKey)).tag($0) }
                }
                .pickerStyle(.segmented)

                periodNavigator

                if let recap {
                    if recap.isEmpty {
                        ContentUnavailableView("recap_empty_title", systemImage: "waveform",
                                               description: Text("recap_empty_detail"))
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        hero(recap)
                        highlights(recap)
                        chart(recap)
                        topSongs(recap)
                        topArtists(recap)
                        topAlbums(recap)
                        genres(recap)
                        hourChart(recap)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 120)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: recap?.period)
        }
        .echoBackground()
        .navigationTitle("recap_title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { shareRecap() } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("recap_share")
                    .disabled(recap?.isEmpty ?? true)
            }
        }
        .sheet(item: $sharePayload) { RecapShareSheet(image: $0) }
        .sensoryFeedback(.selection, trigger: feedback)
        .onChange(of: period) { offset = 0; feedback += 1 }
        .task(id: RecapRequest(period: period, offset: offset, revision: engine.revision, songs: library.songRevision)) {
            await reload()
        }
    }

    // MARK: - Loading

    private struct RecapRequest: Equatable {
        var period: ListeningRecapPeriod
        var offset: Int
        var revision: Int
        var songs: UInt64
    }

    private func reload() async {
        let events = engine.listeningEvents, daily = engine.dailyCounts, songs = library.songs
        let period = period, offset = offset
        let result = await Task.detached(priority: .userInitiated) {
            (ListeningRecap.calculate(period: period, offset: offset, events: events, daily: daily, songs: songs),
             ListeningRecap.earliestActivity(events: events, daily: daily))
        }.value
        guard !Task.isCancelled else { return }
        recap = result.0
        earliest = result.1
    }

    // MARK: - Period

    private var canGoBack: Bool {
        guard period != .allTime, let interval = ListeningRecap.interval(for: period, offset: offset, now: Date(), calendar: .current)
        else { return false }
        return (earliest ?? Date()) < interval.start
    }

    private var periodNavigator: some View {
        HStack {
            Button { offset += 1; feedback += 1 } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .disabled(!canGoBack)
            .accessibilityLabel("recap_previous_period")
            Spacer()
            Text(periodTitle).font(.headline).multilineTextAlignment(.center)
                .contentTransition(.numericText())
            Spacer()
            Button { offset -= 1; feedback += 1 } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(offset == 0 || period == .allTime)
            .accessibilityLabel("recap_next_period")
        }
        .buttonStyle(.echoPress)
        .opacity(period == .allTime ? 0.001 : 1)
        .accessibilityHidden(period == .allTime)
    }

    private var periodTitle: String {
        let locale = EchoLanguage.current.locale
        guard let interval = ListeningRecap.interval(for: period, offset: offset, now: Date(), calendar: .current) else {
            return EchoLocalization.string("recap_period_all_time")
        }
        switch period {
        case .week:
            if offset == 0 { return EchoLocalization.string("recap_this_week") }
            let end = interval.end.addingTimeInterval(-1)
            return interval.start.formatted(.dateTime.day().month(.abbreviated).locale(locale)) + " – "
                + end.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year().locale(locale)).capitalized(with: locale)
        case .year:
            return interval.start.formatted(.dateTime.year().locale(locale))
        case .allTime:
            return EchoLocalization.string("recap_period_all_time")
        }
    }

    // MARK: - Sections

    private func hero(_ recap: ListeningRecap) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("recap_minutes_listened").font(.subheadline.weight(.semibold)).opacity(0.85)
            Text(Int((recap.seconds / 60).rounded()).formatted())
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1)
                .contentTransition(.numericText())
            Text("recap_minutes_unit").font(.headline).opacity(0.85)
            if let top = recap.topArtists.first {
                Text("recap_top_artist_line \(top.title)")
                    .font(.subheadline).opacity(0.85).padding(.top, 6)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background {
            LinearGradient(colors: [Color.accentColor, Color.accentColor.mix(with: .black, by: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(.rect(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.accentColor.opacity(0.3), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
    }

    private func highlights(_ recap: ListeningRecap) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile("play.fill", recap.plays.formatted(), "recap_plays")
            tile("music.note", recap.distinctSongs.formatted(), "recap_different_songs")
            tile("person.2.fill", recap.distinctArtists.formatted(), "recap_artists")
            tile("calendar", recap.activeDays.formatted(), "recap_active_days")
            tile("flame.fill", recap.longestStreak.formatted(), "recap_longest_streak")
            tile("clock.fill", recap.peakHour.map(hourLabel) ?? "–", "recap_peak_hour")
        }
    }

    private func tile(_ symbol: String, _ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(Color.accentColor)
            Text(value).font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .smartCard()
        .accessibilityElement(children: .combine)
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour().locale(EchoLanguage.current.locale))
    }

    @ViewBuilder private func chart(_ recap: ListeningRecap) -> some View {
        if recap.buckets.count > 1 {
            let useMinutes = recap.seconds >= 60
            sectionTitle(useMinutes ? "recap_chart_minutes" : "recap_chart_plays")
            Chart(recap.buckets) { bucket in
                BarMark(x: .value(EchoLocalization.string("smart_day"), bucket.id, unit: unit(recap.bucketUnit)),
                        y: .value(EchoLocalization.string("smart_minutes"), useMinutes ? bucket.seconds / 60 : Double(bucket.plays)))
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(3)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 170)
            .padding(14)
            .customizationSurface(cornerRadius: 18)
        }
    }

    private func unit(_ unit: ListeningRecap.BucketUnit) -> Calendar.Component {
        switch unit {
        case .day: .day
        case .month: .month
        case .year: .year
        }
    }

    @ViewBuilder private func topSongs(_ recap: ListeningRecap) -> some View {
        if !recap.topSongs.isEmpty {
            HStack {
                sectionTitle("recap_top_songs")
                Spacer()
                Button { playTopSongs(recap) } label: {
                    Label("recap_play_top_songs", systemImage: "play.fill").font(.subheadline.bold())
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
                .disabled(!recap.topSongs.contains { $0.songID != nil })
            }
            VStack(spacing: 0) {
                ForEach(Array(recap.topSongs.enumerated()), id: \.element.id) { index, item in
                    Button { play(item, in: recap) } label: {
                        rankedRow(index: index, item: item, artwork: item.songID.flatMap(library.song(withID:)))
                    }
                    .buttonStyle(.plain)
                    .disabled(item.songID == nil)
                    if index < recap.topSongs.count - 1 { Divider().padding(.leading, 96) }
                }
            }
            .customizationSurface(cornerRadius: 18)
        }
    }

    @ViewBuilder private func topArtists(_ recap: ListeningRecap) -> some View {
        if !recap.topArtists.isEmpty {
            sectionTitle("recap_top_artists")
            VStack(spacing: 0) {
                ForEach(Array(recap.topArtists.prefix(5).enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        RecapArtistDestination(key: item.id, name: item.title)
                    } label: {
                        rankedRow(index: index, item: item, artwork: item.songID.flatMap(library.song(withID:)), circular: true)
                    }
                    .buttonStyle(.plain)
                    if index < min(5, recap.topArtists.count) - 1 { Divider().padding(.leading, 96) }
                }
            }
            .customizationSurface(cornerRadius: 18)
        }
    }

    @ViewBuilder private func topAlbums(_ recap: ListeningRecap) -> some View {
        if !recap.topAlbums.isEmpty {
            sectionTitle("recap_top_albums")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(recap.topAlbums) { item in
                        NavigationLink {
                            RecapAlbumDestination(identity: item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                artwork(item.songID.flatMap(library.song(withID:)), size: 140, radius: 14)
                                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 140)
                        }
                        .buttonStyle(.echoPress)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
        }
    }

    @ViewBuilder private func genres(_ recap: ListeningRecap) -> some View {
        if !recap.topGenres.isEmpty {
            sectionTitle("recap_top_genres")
            let total = max(1, recap.topGenres.map(\.plays).reduce(0, +))
            VStack(spacing: 10) {
                ForEach(recap.topGenres) { genre in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(genre.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text((Double(genre.plays) / Double(total)).formatted(.percent.precision(.fractionLength(0))))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        GeometryReader { proxy in
                            Capsule().fill(Color.accentColor.opacity(0.15))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.accentColor.gradient)
                                        .frame(width: proxy.size.width * CGFloat(genre.plays) / CGFloat(total))
                                }
                        }
                        .frame(height: 8)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
            .customizationSurface(cornerRadius: 18)
        }
    }

    @ViewBuilder private func hourChart(_ recap: ListeningRecap) -> some View {
        if recap.peakHour != nil {
            sectionTitle("recap_time_of_day")
            Chart(Array(recap.hours.enumerated()), id: \.offset) { hour, seconds in
                AreaMark(x: .value("hour", hour), y: .value(EchoLocalization.string("smart_minutes"), seconds / 60))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor.opacity(0.25).gradient)
                LineMark(x: .value("hour", hour), y: .value(EchoLocalization.string("smart_minutes"), seconds / 60))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisGridLine()
                    AxisValueLabel { if let hour = value.as(Int.self) { Text(hourLabel(hour)) } }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 130)
            .padding(14)
            .customizationSurface(cornerRadius: 18)
        }
    }

    // MARK: - Rows

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.title3.bold()).padding(.top, 4)
    }

    private func rankedRow(index: Int, item: ListeningRecap.Ranked, artwork song: Song?, circular: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
            artwork(song, size: 48, radius: circular ? 24 : 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body.weight(.semibold)).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("recap_plays_count \(item.plays)").font(.caption.weight(.semibold)).monospacedDigit()
                if item.seconds >= 60 {
                    Text(SmartMusicFormatting.duration(item.seconds)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func artwork(_ song: Song?, size: CGFloat, radius: CGFloat) -> some View {
        if let song {
            SongArtworkView(song: song, cornerRadius: radius).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.quaternary)
                .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
                .frame(width: size, height: size)
        }
    }

    // MARK: - Actions

    private func playable(_ recap: ListeningRecap) -> [Song] {
        recap.topSongs.compactMap { $0.songID.flatMap(library.song(withID:)) }.filter {
            library.getURL(for: $0).map { FileManager.default.fileExists(atPath: $0.path) } == true
        }
    }

    private func play(_ item: ListeningRecap.Ranked, in recap: ListeningRecap) {
        let queue = playable(recap)
        guard let song = queue.first(where: { $0.id == item.songID }), let url = library.getURL(for: song) else { return }
        player.lastPlaybackDirection = .fade
        player.allSongs = library.songs
        player.play(song: song, url: url, queue: queue)
        feedback += 1
    }

    private func playTopSongs(_ recap: ListeningRecap) {
        let queue = playable(recap)
        guard let first = queue.first, let url = library.getURL(for: first) else { return }
        player.lastPlaybackDirection = .fade
        player.allSongs = library.songs
        player.play(song: first, url: url, queue: queue)
        feedback += 1
    }

    @MainActor private func shareRecap() {
        guard let recap else { return }
        let cover = (recap.topSongs.first?.songID).flatMap(library.song(withID:)).flatMap { $0.coverData ?? $0.imageData }
            .flatMap(UIImage.init(data:))?.preparingThumbnail(of: CGSize(width: 600, height: 600))
        let card = RecapShareCard(recap: recap, periodTitle: periodTitle, cover: cover)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        sharePayload = RecapShareImage(image: image, title: periodTitle)
    }
}

// MARK: - Destinations

private struct RecapArtistDestination: View {
    let key: String
    let name: String
    @Environment(MusicLibraryManager.self) private var library
    var body: some View {
        if let group = library.artistGroupsByID.values.first(where: { SmartMusicSelection.artistKey($0.name) == key })
            ?? library.artistGroupsByID.values.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            ArtistDetailView(artist: group)
        } else {
            ContentUnavailableView(name, systemImage: "person.crop.circle.badge.questionmark")
        }
    }
}

private struct RecapAlbumDestination: View {
    let identity: String
    @Environment(MusicLibraryManager.self) private var library
    var body: some View {
        if let album = LibraryAlbums.groups(from: library.songs).first(where: { $0.id == identity }) {
            AlbumDetailView(album: album)
        } else {
            ContentUnavailableView("recap_album_missing", systemImage: "square.stack")
        }
    }
}

// MARK: - Sharing

struct RecapShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
    let title: String
}

struct RecapShareCard: View {
    let recap: ListeningRecap
    let periodTitle: String
    let cover: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor, Color.accentColor.mix(with: .black, by: 0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let cover {
                Image(uiImage: cover).resizable().scaledToFill().frame(width: 360, height: 640)
                    .blur(radius: 70).opacity(0.3).clipped()
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform").font(.system(size: 14, weight: .bold))
                    Text(verbatim: "Echo Recap").font(.system(size: 16, weight: .heavy, design: .rounded))
                    Spacer()
                    Text(verbatim: periodTitle).font(.system(size: 13, weight: .semibold)).opacity(0.85)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: Int((recap.seconds / 60).rounded()).formatted())
                        .font(.system(size: 66, weight: .heavy, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                    Text("recap_minutes_unit").font(.system(size: 17, weight: .semibold)).opacity(0.85)
                }
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill().frame(width: 120, height: 120)
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                }
                HStack(alignment: .top, spacing: 18) {
                    list("recap_top_songs", recap.topSongs.prefix(5).map(\.title))
                    list("recap_top_artists", recap.topArtists.prefix(5).map(\.title))
                }
                Spacer(minLength: 0)
                HStack(spacing: 18) {
                    stat(recap.plays.formatted(), "recap_plays")
                    stat(recap.activeDays.formatted(), "recap_active_days")
                    stat(recap.longestStreak.formatted(), "recap_longest_streak")
                }
            }
            .padding(28)
            .foregroundStyle(.white)
        }
        .frame(width: 360, height: 640)
        .clipShape(.rect)
        .environment(\.colorScheme, .dark)
    }

    private func list(_ title: LocalizedStringKey, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .bold)).textCase(.uppercase).opacity(0.75)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Text(verbatim: "\(index + 1)  \(item)").font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value).font(.system(size: 22, weight: .heavy, design: .rounded))
            Text(label).font(.system(size: 11, weight: .medium)).opacity(0.8).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RecapShareSheet: View {
    let image: RecapShareImage
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(uiImage: image.image).resizable().scaledToFit()
                    .clipShape(.rect(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                    .frame(maxHeight: 520)
                ShareLink(item: Image(uiImage: image.image),
                          preview: SharePreview(Text(verbatim: "Echo Recap · \(image.title)"), image: Image(uiImage: image.image))) {
                    Label("share_action", systemImage: "square.and.arrow.up")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .navigationTitle("recap_share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action_done") { dismiss() }.tint(.primary) }
            }
        }
        .presentationDetents([.large])
    }
}

/// Library card artwork for Echo Recap.
struct RecapFeatureArtwork: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor, Color.accentColor.mix(with: .black, by: 0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(alignment: .bottom, spacing: 7) {
                ForEach([0.45, 0.75, 0.55, 1.0, 0.7], id: \.self) { height in
                    Capsule().fill(.white.opacity(0.9)).frame(width: 14, height: 80 * height)
                }
            }
            .padding(.top, 20)
        }
        .accessibilityHidden(true)
    }
}
