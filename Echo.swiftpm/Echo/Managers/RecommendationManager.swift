import Foundation
import SwiftUI

@MainActor
@Observable
final class RecommendationManager {

    static let shared = RecommendationManager()

    struct SongLearningData: Codable {
        var playCount: Int = 0
        var completionCount: Int = 0
        var skipCount: Int = 0
        var lastStartedAt: Date?
        var lastCompletedAt: Date?
    }

    private(set) var learningData: [UUID: SongLearningData] = [:]
    private(set) var revision: Int = 0
    private(set) var dailyCounts: [UUID: [String: Int]] = [:]
    private(set) var listeningEvents: [ListeningEvent] = []
    private(set) var trackingStartedAt = Date()
    @ObservationIgnored private var accumulator = ListeningAccumulator()
    @ObservationIgnored private var pendingEndReason: ListeningEndReason = .selected
    @ObservationIgnored private var observedAudibleSeconds: Double = 0

    func selectionSnapshot(songs: [Song], favorites: [UUID], seed: UInt64 = 0) -> SmartMusicSelection {
        SmartMusicSelection(songs: songs, favorites: Set(favorites), learning: learningData.mapValues {
            .init(plays: $0.playCount, completions: $0.completionCount, skips: $0.skipCount, lastPlayed: $0.lastStartedAt)
        }, now: Date(), seed: seed)
    }
    func historicalPeriods(songIDs: Set<UUID>) -> [HistoricalMusicPeriod] {
        HistoricalMusicPeriod.available(daily: dailyCounts, songIDs: songIDs)
    }
    func playbackWillChange(_ reason: ListeningEndReason, position: Double, playing: Bool) {
        sampleListening(position: position, playing: playing)
        observedMaximumTime = accumulator.audibleSeconds
        pendingEndReason = reason
        finishObservedSongIfNeeded()
    }
    func playbackStateChanged(position: Double, playing: Bool) {
        sampleListening(position: position, playing: playing)
        if !playing { checkpointListening() }
    }
    func playbackSeeked(position: Double) { accumulator.reanchor(at: Date(), position: position) }
    private func sampleListening(position: Double, playing: Bool) {
        accumulator.sample(at: Date(), position: position, playing: playing)
    }
    private func checkpointListening() {
        accumulator.checkpoint()
        if let event = accumulator.event { storeListening(event) }
    }
    private func storeListening(_ event: ListeningEvent) {
        guard event.seconds > 0 else { return }
        if let index = listeningEvents.lastIndex(where: { $0.id == event.id }) { listeningEvents[index] = event }
        else { listeningEvents.append(event) }
        saveAndPublish()
    }
    var smartSnapshot: SmartListeningSnapshot {
        _ = revision
        return SmartListeningSnapshot(total: learningData.mapValues(\.playCount), daily: dailyCounts)
    }
    func playbackStarted(_ song: Song) {
        guard song.podcastEpisodeID == nil else { return }
        finishObservedSongIfNeeded()
        beginObserving(song)
        accumulator.begin(song: song, at: Date())
    }

    @ObservationIgnored private let storageQueue = DispatchQueue(label: "com.echomusic.listening-storage", qos: .utility)
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    private let storageKey = "EchoRecommendationLearningDataV1"

    private var monitorTimer: Timer?
    private var observedSongID: UUID?
    private var observedMaximumTime: Double = 0
    private var observedDuration: Double = 0
    private var completionRecordedForObservedSong = false

    private init() {
        load()
        startMonitoringPlayback()
    }

    // MARK: - Public recommendations

    func recommendations(
        from songs: [Song],
        favoriteSongIDs: [UUID],
        limit: Int = 12
    ) -> [Song] {

        guard !songs.isEmpty else {
            return []
        }

        let favoriteIDs = Set(favoriteSongIDs)

        let artistAffinity = makeArtistAffinity(
            songs: songs,
            favoriteIDs: favoriteIDs
        )

        let albumAffinity = makeAlbumAffinity(
            songs: songs,
            favoriteIDs: favoriteIDs
        )

        let scored = songs.map { song -> (song: Song, score: Double) in

            let data =
                learningData[song.id]
                ?? SongLearningData()

            var score = 0.0

            // Het nummer zelf.
            score += Double(data.playCount) * 1.25
            score += Double(data.completionCount) * 5.0
            score -= Double(data.skipCount) * 4.5

            if favoriteIDs.contains(song.id) {
                score += 9.0
            }

            // Artiest- en albumvoorkeur.
            let artistKey = normalized(song.artist)

            score +=
                (artistAffinity[artistKey] ?? 0)
                * 0.55

            if let album = song.album,
               !album
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty {

                score +=
                    (albumAffinity[normalized(album)] ?? 0)
                    * 0.35
            }

            // Discovery: nieuwe / weinig beluisterde songs
            // krijgen bewust ook een kans.
            if data.playCount == 0 {
                score += 3.0
            } else if data.playCount == 1 {
                score += 1.0
            }

            // Niet meteen hetzelfde nummer opnieuw pushen.
            if let lastStartedAt = data.lastStartedAt {

                let age =
                    Date()
                        .timeIntervalSince(lastStartedAt)

                if age < 60 * 30 {
                    score -= 7.0
                } else if age < 60 * 60 * 6 {
                    score -= 3.0
                } else if age < 60 * 60 * 24 {
                    score -= 1.0
                }
            }

            // Kleine exploration-factor zodat de lijst
            // niet voor altijd exact hetzelfde blijft.
            score += Double.random(in: 0...2.5)

            return (song, score)
        }

        let ranked =
            scored
                .sorted {
                    $0.score > $1.score
                }
                .map(\.song)

        let wantedCount =
            min(limit, songs.count)

        let discoveryCount =
            wantedCount >= 5
            ? max(1, wantedCount / 5)
            : 0

        let learnedCount =
            wantedCount - discoveryCount

        var result =
            Array(
                ranked.prefix(learnedCount)
            )

        // Ongeveer 20% discovery.
        if discoveryCount > 0 {

            let alreadyChosen =
                Set(result.map(\.id))

            let discoveryPool =
                songs
                    .filter {
                        !alreadyChosen.contains($0.id)
                        &&
                        (
                            learningData[$0.id]?
                                .playCount
                            ?? 0
                        ) <= 1
                    }
                    .shuffled()

            result.append(
                contentsOf:
                    discoveryPool
                        .prefix(discoveryCount)
            )
        }

        if result.count < wantedCount {

            let chosen =
                Set(result.map(\.id))

            result.append(
                contentsOf:
                    ranked
                        .filter {
                            !chosen.contains($0.id)
                        }
                        .prefix(
                            wantedCount
                            - result.count
                        )
            )
        }

        return result
    }

    func resetLearning() {
        learningData.removeAll()
        dailyCounts.removeAll()
        saveAndPublish()
    }

    // MARK: - Playback learning

    private func startMonitoringPlayback() {

        monitorTimer?.invalidate()

        monitorTimer =
            Timer.scheduledTimer(
                withTimeInterval: 1.0,
                repeats: true
            ) {
                [weak self] _ in

                Task { @MainActor in
                    self?.samplePlayback()
                }
            }
    }

    private func samplePlayback() {

        let player =
            AudioPlayerManager.shared

        guard !player.isPreviewing else { return }
        guard let currentSong =
                player.currentSong, currentSong.podcastEpisodeID == nil
        else {
            finishObservedSongIfNeeded()
            return
        }

        if observedSongID != currentSong.id {
            // Starts are registered by the audio engine, including repeats.
            // During a crossfade metadata still belongs to the outgoing song.
            return
        }

        sampleListening(position: player.currentTime, playing: player.isPlaying && (player.localPlaybackState == .playing || player.localPlaybackState == .transitioning))
        observedAudibleSeconds = accumulator.audibleSeconds
        observedMaximumTime = observedAudibleSeconds

        observedDuration =
            max(
                observedDuration,
                player.duration
            )

        guard observedDuration > 0 else {
            return
        }

        let progress =
            observedMaximumTime
            /
            observedDuration

        // Vanaf 70% telt dit als een succesvolle luisterbeurt.
        if progress >= 0.70,
           !completionRecordedForObservedSong {

            recordCompletion(
                for: currentSong.id
            )

            completionRecordedForObservedSong =
                true
        }
    }

    private func beginObserving(
        _ song: Song
    ) {

        observedSongID =
            song.id

        observedMaximumTime =
            0
        observedAudibleSeconds = 0

        observedDuration =
            0

        completionRecordedForObservedSong =
            false

        var data =
            learningData[song.id]
            ?? SongLearningData()

        data.playCount += 1
        let now = Date()
        dailyCounts[song.id, default: [:]][SmartListeningSnapshot.dayKey(now), default: 0] += 1
        data.lastStartedAt = now
        MusicLibraryManager.shared.recordSmartPlaylistPlay(song, at: now)

        learningData[song.id] =
            data

        saveAndPublish()
    }

    private func finishObservedSongIfNeeded() {

        guard let songID =
                observedSongID
        else {
            return
        }

        // Alleen een echt snelle skip bestraffen.
        // Half beluisteren of pauzeren is dus niet negatief.
        if pendingEndReason == .skipped,
           !completionRecordedForObservedSong,
           observedMaximumTime > 0,
           observedMaximumTime < 15 {

            var data =
                learningData[songID]
                ?? SongLearningData()

            data.skipCount += 1

            learningData[songID] =
                data

            saveAndPublish()
        }

        if pendingEndReason == .completed, !completionRecordedForObservedSong,
           observedDuration > 0, accumulator.audibleSeconds >= observedDuration * 0.70 {
            recordCompletion(for: songID)
        }
        if let event = accumulator.finish(pendingEndReason) { storeListening(event) }
        pendingEndReason = .selected

        observedSongID =
            nil

        observedMaximumTime =
            0

        observedDuration =
            0

        completionRecordedForObservedSong =
            false
    }

    private func recordCompletion(
        for songID: UUID
    ) {

        var data =
            learningData[songID]
            ?? SongLearningData()

        data.completionCount += 1
        data.lastCompletedAt = Date()

        learningData[songID] =
            data

        saveAndPublish()
    }

    // MARK: - Artist affinity

    private func makeArtistAffinity(
        songs: [Song],
        favoriteIDs: Set<UUID>
    ) -> [String: Double] {

        var totals:
            [String: Double] = [:]

        var counts:
            [String: Int] = [:]

        for song in songs {

            let key =
                normalized(song.artist)

            guard !key.isEmpty else {
                continue
            }

            let data =
                learningData[song.id]
                ?? SongLearningData()

            var value =
                Double(data.playCount)
                * 0.8

            value +=
                Double(data.completionCount)
                * 3.0

            value -=
                Double(data.skipCount)
                * 2.5

            if favoriteIDs.contains(song.id) {
                value += 6.0
            }

            totals[key, default: 0] +=
                value

            counts[key, default: 0] +=
                1
        }

        var result:
            [String: Double] = [:]

        for (key, total) in totals {

            let count =
                max(
                    1,
                    counts[key] ?? 1
                )

            result[key] =
                total
                /
                sqrt(Double(count))
        }

        return result
    }

    // MARK: - Album affinity

    private func makeAlbumAffinity(
        songs: [Song],
        favoriteIDs: Set<UUID>
    ) -> [String: Double] {

        var totals:
            [String: Double] = [:]

        var counts:
            [String: Int] = [:]

        for song in songs {

            guard let album =
                    song.album
            else {
                continue
            }

            let key =
                normalized(album)

            guard !key.isEmpty else {
                continue
            }

            let data =
                learningData[song.id]
                ?? SongLearningData()

            var value =
                Double(data.playCount)
                * 0.6

            value +=
                Double(data.completionCount)
                * 2.5

            value -=
                Double(data.skipCount)
                * 2.0

            if favoriteIDs.contains(song.id) {
                value += 5.0
            }

            totals[key, default: 0] +=
                value

            counts[key, default: 0] +=
                1
        }

        var result:
            [String: Double] = [:]

        for (key, total) in totals {

            let count =
                max(
                    1,
                    counts[key] ?? 1
                )

            result[key] =
                total
                /
                sqrt(Double(count))
        }

        return result
    }

    private func normalized(
        _ value: String
    ) -> String {

        value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .folding(
                options: [
                    .diacriticInsensitive,
                    .caseInsensitive
                ],
                locale: .current
            )
    }

    // MARK: - Persistence

    func flush() {
        let player = AudioPlayerManager.shared
        sampleListening(position: player.currentTime, playing: player.isPlaying && (player.localPlaybackState == .playing || player.localPlaybackState == .transitioning))
        checkpointListening()
        pendingSave?.cancel()
        saveAndPublish(immediately: true)
    }
    private func saveAndPublish(immediately: Bool = false) {
        revision &+= 1
        pendingSave?.cancel()
        let daily = dailyCounts, learning = learningData, key = storageKey
        let events = listeningEvents, started = trackingStartedAt
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(events) { UserDefaults.standard.set(data, forKey: "EchoListeningEventsV1") }
            UserDefaults.standard.set(started, forKey: "EchoListeningTrackingStartedV1")
            if let data = try? JSONEncoder().encode(daily) { UserDefaults.standard.set(data, forKey: "EchoDailyListeningV1") }
            if let data = try? JSONEncoder().encode(learning) { UserDefaults.standard.set(data, forKey: key) }
        }
        pendingSave = work
        if immediately { storageQueue.async(execute: work) }
        else { storageQueue.asyncAfter(deadline: .now() + 0.2, execute: work) }
    }

    private func load() {
        trackingStartedAt = UserDefaults.standard.object(forKey: "EchoListeningTrackingStartedV1") as? Date ?? Date()
        if let data = UserDefaults.standard.data(forKey: "EchoListeningEventsV1"),
           let events = try? JSONDecoder().decode([ListeningEvent].self, from: data) { listeningEvents = events }
        if let data = UserDefaults.standard.data(forKey: "EchoDailyListeningV1"),
           let counts = try? JSONDecoder().decode([UUID: [String: Int]].self, from: data) { dailyCounts = counts }

        guard
            let data =
                UserDefaults.standard
                    .data(
                        forKey: storageKey
                    ),

            let decoded =
                try? JSONDecoder()
                    .decode(
                        [
                            UUID:
                            SongLearningData
                        ].self,
                        from: data
                    )
        else {
            return
        }

        learningData =
            decoded
    }
}
