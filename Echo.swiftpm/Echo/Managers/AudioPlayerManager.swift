import Foundation
import AVFoundation
import MediaPlayer
import AVFAudio
import UIKit
import Intents


enum RepeatMode: Equatable {
    case off
    case all
    case one
}


@Observable
class AudioPlayerManager:
    NSObject,
    EqualizedAudioPlayerDelegate {

    static let shared =
        AudioPlayerManager()


    override init() {

        super.init()

        setupRemoteCommands()
    }


    var lastPlaybackDirection:
        PlaybackDirection =
        .fade


    enum PlaybackDirection {
        case next
        case previous
        case fade
    }


    private let lyricsManager =
        LyricsManager.shared


    private var player:
        EqualizedAudioPlayer?

    @ObservationIgnored private var podcastPlayer: AVPlayer?
    @ObservationIgnored private var podcastTimeObserver: Any?
    @ObservationIgnored private var podcastEndObserver: NSObjectProtocol?
    @ObservationIgnored private var podcastInterruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var podcastRouteObserver: NSObjectProtocol?
    @ObservationIgnored private var podcastStatusObserver: NSKeyValueObservation?
    @ObservationIgnored private var podcastArtworkTask: Task<Void, Never>?
    @ObservationIgnored private var podcastLastSaved: Double = -1
    @ObservationIgnored private var podcastDidPrepare = false
    private var podcastWantsPlayback = false
    private var podcastResumeAfterInterruption = false
    var podcastSpeed: Float = 1
    var isPodcast: Bool { currentSong?.podcastEpisodeID != nil }


    private var timer:
        Timer?


    private var preloadedSong:
        Song?


    private var preloadedPlayer:
        EqualizedAudioPlayer?


    var currentLyrics:
        String?


    var currentSyncedLyrics:
        String?


    var currentLyricsSource: LyricsProvider?
    var currentLyricsSourceURL: URL?
    var isLoadingLyrics = false
    var lyricsStatusKey: String?
    @ObservationIgnored private var lyricsTask: Task<Void, Never>?
    @ObservationIgnored private var lyricsRequestID = UUID()

    var lyricsNeedsInternet =
        false


    var isPlaying =
        false {
        didSet {
            if isPlaying != oldValue { EchoWidgetSnapshotPublisher.requestUpdate() }
        }
    }


    var currentSong:
        Song? {
        didSet { EchoWidgetSnapshotPublisher.requestUpdate() }
    }


    var currentTime:
        Double =
        0


    var duration:
        Double =
        0


    var queue:
        [Song] = []


    private var originalQueue:
        [Song] = []


    var currentIndex:
        Int =
        0


    var history:
        [Song] = []


    var autoNextQueue:
        [Song] = []


    var autoNextIndex:
        Int =
        0


    var allSongs:
        [Song] = []


    var shuffleEnabled =
        false


    var repeatMode:
        RepeatMode =
        .off


    // ========================================================
    // MARK: - Siri Playback Helpers
    // ========================================================

    func setShuffle(
        _ enabled: Bool
    ) {

        guard shuffleEnabled !=
                enabled
        else {
            return
        }

        toggleShuffle()
    }


    func setRepeatMode(
        _ mode: RepeatMode
    ) {

        repeatMode =
            mode
    }


    // ========================================================
    // MARK: - Siri Playback Donation
    // ========================================================

    func donatePlaybackToSiri(
        song: Song
    ) {

        var artwork:
            INImage? =
            nil


        if let data =
            song.coverData {

            artwork =
                INImage(
                    imageData:
                        data
                )
        }


        let mediaItem =
            INMediaItem(
                identifier:
                    song.id.uuidString,

                title:
                    song.title,

                type:
                    .song,

                artwork:
                    artwork,

                artist:
                    song.artist
            )


        let intent =
            INPlayMediaIntent(
                mediaItems:
                    [
                        mediaItem
                    ],

                mediaContainer:
                    nil,

                playShuffled:
                    nil,

                playbackRepeatMode:
                    .unknown,

                resumePlayback:
                    nil,

                playbackQueueLocation:
                    .unknown,

                playbackSpeed:
                    nil,

                mediaSearch:
                    nil
            )


        let interaction =
            INInteraction(
                intent:
                    intent,

                response:
                    nil
            )


        interaction.identifier =
            "echo.play.\(song.id.uuidString)"


        interaction.donate {
            error in


            if let error {

                print(
                    "Siri playback donation mislukt:",
                    error.localizedDescription
                )


            } else {

                print(
                    "Siri playback donation opgeslagen:",
                    song.title
                )
            }
        }
    }


    // ========================================================
    // MARK: - Now Playing
    // ========================================================

    func updateNowPlaying() {
        if isPodcast { updatePodcastNowPlaying(); return }

        guard
            let song =
                currentSong,

            let player =
                player
        else {
            return
        }


        var info:
            [String: Any] =
            [:]


        info[
            MPMediaItemPropertyTitle
        ] =
            song.title


        info[
            MPMediaItemPropertyArtist
        ] =
            song.artist


        info[
            MPNowPlayingInfoPropertyElapsedPlaybackTime
        ] =
            player.currentTime


        info[
            MPMediaItemPropertyPlaybackDuration
        ] =
            player.duration


        info[
            MPNowPlayingInfoPropertyPlaybackRate
        ] =
            isPlaying
            ? 1.0
            : 0.0


        if
            let data =
                song.coverData,

            let image =
                UIImage(
                    data:
                        data
                ) {

            let artwork =
                MPMediaItemArtwork(
                    boundsSize:
                        image.size
                ) {
                    _ in

                    image
                }


            info[
                MPMediaItemPropertyArtwork
            ] =
                artwork
        }


        MPNowPlayingInfoCenter
            .default()
            .nowPlayingInfo =
            info
    }


    // ========================================================
    // MARK: - Audio Session
    // ========================================================

    func setupAudioSession() {

        do {

            let session =
                AVAudioSession
                    .sharedInstance()


            try session.setCategory(
                .playback,
                mode:
                    .default
            )


            try session.setActive(
                true
            )


        } catch {

            print(
                "Audio session fout:",
                error
            )
        }
    }


    // ========================================================
    // MARK: - Remote Commands
    // ========================================================

    func setupRemoteCommands() {
        let podcastCommands = MPRemoteCommandCenter.shared()
        podcastCommands.skipBackwardCommand.preferredIntervals = [15]
        podcastCommands.skipForwardCommand.preferredIntervals = [30]
        podcastCommands.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self, self.isPodcast else { return .commandFailed }
            self.seek(to: self.currentTime - 15)
            return .success
        }
        podcastCommands.skipForwardCommand.addTarget { [weak self] _ in
            guard let self, self.isPodcast else { return .commandFailed }
            self.seek(to: self.currentTime + 30)
            return .success
        }

        let commandCenter =
            MPRemoteCommandCenter
                .shared()


        commandCenter
            .playCommand
            .addTarget {
                [weak self]
                _ in


                if self?.isPlaying == false { self?.togglePlayPause() }


                return .success
            }


        commandCenter
            .pauseCommand
            .addTarget {
                [weak self]
                _ in


                if self?.isPlaying == true { self?.togglePlayPause() }


                return .success
            }


        commandCenter
            .nextTrackCommand
            .addTarget {
                [weak self]
                _ in


                self?
                    .next()


                return .success
            }


        commandCenter
            .previousTrackCommand
            .addTarget {
                [weak self]
                _ in


                self?
                    .previous()


                return .success
            }


        commandCenter
            .changePlaybackPositionCommand
            .isEnabled =
            true


        commandCenter
            .changePlaybackPositionCommand
            .addTarget {
                [weak self]
                event in


                guard
                    let self,

                    let event =
                        event as?
                        MPChangePlaybackPositionCommandEvent
                else {
                    return .commandFailed
                }


                self.seek(
                    to:
                        event.positionTime
                )


                return .success
            }
    }


    // ========================================================
    // MARK: - Play
    // ========================================================

    func play(
        song: Song,
        url: URL,
        queue: [Song] = [], queuePosition: Int? = nil, repeatingCurrent: Bool = false
    ) {

        setupAudioSession()

        stopPodcastPlayback()


        if !queue.isEmpty {

            self.queue =
                queue

            self.originalQueue =
                queue
        }


        if let queuePosition, self.queue.indices.contains(queuePosition),
           self.queue[queuePosition].id == song.id {
            currentIndex = queuePosition
        } else if let index = self.queue.firstIndex(where: { $0.id == song.id }) {
            currentIndex = index
        } else {
            self.queue = [song]
            self.originalQueue = [song]
            currentIndex = 0
        }
        if let id = song.podcastEpisodeID, let episode = PodcastStore.shared.state.episodes[id] {
            startPodcastPlayback(episode, song: song)
            return
        }
        do {

            timer?
                .invalidate()


            player =
                try EqualizedAudioPlayer(
                    contentsOf:
                        url
                )


            player?
                .delegate =
                self


            player?
                .prepareToPlay()


            duration =
                player?
                    .duration
                ??
                0


            currentTime =
                0


            if
                let oldSong =
                    currentSong,

                oldSong.id !=
                    song.id {

                history.append(
                    oldSong
                )
            }



            currentSong =
                song


            currentLyrics =
                nil


            currentSyncedLyrics =
                nil


            loadLyrics(
                for:
                    song
            )


            player?
                .play()


            UIApplication.shared
                .beginReceivingRemoteControlEvents()


            isPlaying =
                player?.isPlaying ?? false


            updateNowPlaying()

            startTimer()


            // --------------------------------------------
            // Tell Siri that Echo played this song.
            // Helps Siri learn Echo as a music app.
            // --------------------------------------------

            donatePlaybackToSiri(
                song:
                    song
            )


            fillQueue(
                from:
                    queue
            )


            if !repeatingCurrent { updateRepeatForSelection() }

        } catch {

            print(
                "Kan nummer niet afspelen:",
                error.localizedDescription
            )
        }
    }


    // ========================================================
    // MARK: - Lyrics
    // ========================================================

    func loadLyrics(for song: Song, forceRefresh: Bool = false, provider: LyricsProvider = .automatic) {
        lyricsTask?.cancel()
        let requestID = UUID()
        lyricsRequestID = requestID
        isLoadingLyrics = false
        lyricsStatusKey = nil
        lyricsNeedsInternet = false
        if !forceRefresh {
            currentLyrics = nil
            currentSyncedLyrics = nil
            currentLyricsSource = nil
            currentLyricsSourceURL = nil
            if let saved = MusicLibraryManager.shared.songs.first(where: { $0.id == song.id }),
               saved.lyrics != nil || saved.syncedLyrics != nil {
                currentLyrics = saved.lyrics
                currentSyncedLyrics = saved.syncedLyrics
                currentLyricsSource = saved.lyricsSource.flatMap(LyricsProvider.init(rawValue:))
                currentLyricsSourceURL = saved.lyricsSourceURL
                return
            }
        }
        let key = provider == .musixmatch ? "musixmatchApiKey" : "geniusAccessToken"
        if (provider == .musixmatch || provider == .genius),
           (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lyricsStatusKey = "lyrics_missing_key"
            return
        }
        let songDuration = duration
        isLoadingLyrics = true
        lyricsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await lyricsManager.fetchLyrics(for: song, duration: songDuration, provider: provider)
            guard !Task.isCancelled, lyricsRequestID == requestID, currentSong?.id == song.id else { return }
            isLoadingLyrics = false
            if let result {
                currentLyrics = result.plainLyrics
                currentSyncedLyrics = result.syncedLyrics
                currentLyricsSource = result.source
                currentLyricsSourceURL = result.sourceURL
                MusicLibraryManager.shared.updateLyrics(for: song, lyrics: result.plainLyrics,
                    syncedLyrics: result.syncedLyrics, source: result.source, sourceURL: result.sourceURL)
            } else {
                // Keep existing lyrics when a manual refresh fails.
                lyricsStatusKey = "lyrics_fetch_failed"
            }
        }
    }

    func refreshLyrics(provider: LyricsProvider) {
        guard let song = currentSong else { return }
        loadLyrics(for: song, forceRefresh: true, provider: provider)
    }

    // ========================================================
    // MARK: - Next
    // ========================================================

    func next(manuallyInitiated: Bool = true) {
        if isPodcast && currentIndex + 1 >= queue.count {
            podcastPlayer?.pause()
            podcastWantsPlayback = false
            isPlaying = false
            savePodcastPosition()
            updateNowPlaying()
            return
        }

        lastPlaybackDirection =
            .next


        if manuallyInitiated { updateRepeatForSelection() }

        if queue.count >
            currentIndex + 1 {

            currentIndex +=
                1


            playPreloadedOrNextSong(repeatingCurrent: !manuallyInitiated)

            return
        }


        if
            repeatMode ==
                .all,

            !queue.isEmpty {

            currentIndex =
                0


            playSongAtIndex(repeatingCurrent: !manuallyInitiated)

            return
        }


        if let nextSong = autoNextQueue.first, let url = getURL(for: nextSong) {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let savedQueue = queue
            let savedIndex = currentIndex
            queue.append(nextSong)
            currentIndex = queue.count - 1
            play(song: nextSong, url: url, queue: queue, queuePosition: currentIndex)
            if player?.isPlaying == true {
                autoNextQueue.removeFirst()
                fillAutoNext(from: allSongs)
            } else {
                queue = savedQueue
                currentIndex = savedIndex
            }
            return
        }
        player?.stop()
        isPlaying =
            false


        updateNowPlaying()
    }


    // ========================================================
    // MARK: - Preloaded Next
    // ========================================================

    private func playPreloadedOrNextSong(repeatingCurrent: Bool) {
        playSongAtIndex(repeatingCurrent: repeatingCurrent)
    }


    // ========================================================
    // MARK: - Previous
    // ========================================================

    func previous() {
        lastPlaybackDirection = .previous

        if currentTime > 3 { updateRepeatForSelection(); seek(to: 0); return }
        if let song = previousQueuedSong { playPreviousSong(song) }
        else { updateRepeatForSelection(); seek(to: 0) }
    }

    private func updateRepeatForSelection() {
        guard repeatMode != .off else { return }
        // Count the complete queue: repeat-all also includes entries before the current song.
        repeatMode = queue.count > 1 ? .all : .off
    }

    var previousQueuedSong: Song? {
        if queue.indices.contains(currentIndex), queue[currentIndex].id == currentSong?.id,
           currentIndex > 0 { return queue[currentIndex - 1] }
        return history.last
    }


    // ========================================================
    // MARK: - Play Next
    // ========================================================

    func playNext(_ song: Song) {
        guard let currentSong else { return }
        if !queue.indices.contains(currentIndex) || queue[currentIndex].id != currentSong.id {
            queue = [currentSong]
            currentIndex = 0
        }
        // Never remove the playing occurrence or invalidate its insertion index.
        let prefix = Array(queue.prefix(currentIndex + 1))
        let upcoming = queue.dropFirst(currentIndex + 1).filter { $0.id != song.id }
        queue = prefix + [song] + upcoming
    }


    // ========================================================
    // MARK: - Play Song At Index
    // ========================================================

    private func playSongAtIndex(repeatingCurrent: Bool = false) {
        guard queue.indices.contains(currentIndex), let url = getURL(for: queue[currentIndex]) else { return }
        play(song: queue[currentIndex], url: url, queue: queue, queuePosition: currentIndex, repeatingCurrent: repeatingCurrent)
    }


    // ========================================================
    // MARK: - Fill Queue
    // ========================================================

    func fillQueue(
        from songs: [Song]
    ) {

        guard let currentSong else {
            return
        }


        let upcoming = queue.dropFirst(max(0, currentIndex + 1))

        let missing =
            30
            -
            upcoming.count


        if missing >
            0 {

            let availableSongs =
                songs.filter {
                    song in


                    song.id !=
                        currentSong.id
                    &&
                    !queue.contains(
                        where: {
                            queuedSong in

                            queuedSong.id ==
                                song.id
                        }
                    )
                }


            let extra =
                availableSongs
                    .shuffled()
                    .prefix(
                        missing
                    )


            queue.append(
                contentsOf:
                    extra
            )
        }
    }


    // ========================================================
    // MARK: - Previous Song Playback
    // ========================================================

    func playPreviousSong(_ song: Song) {
        guard let url = getURL(for: song), song.podcastEpisodeID != nil || FileManager.default.fileExists(atPath: url.path) else { return }
        let savedHistory = history
        let savedQueue = queue
        let savedIndex = currentIndex
        let previousIndex = currentIndex - 1
        if queue.indices.contains(previousIndex), queue[previousIndex].id == song.id {
            currentIndex = previousIndex
        } else {
            let upcoming = Array(queue.dropFirst(max(0, currentIndex + 1)))
            queue = [song] + (currentSong.map { [$0] } ?? []) + upcoming
            currentIndex = 0
        }
        play(song: song, url: url, queue: queue, queuePosition: currentIndex)
        guard player?.isPlaying == true || podcastPlayer != nil else {
            queue = savedQueue
            currentIndex = savedIndex
            history = savedHistory
            return
        }
        history = savedHistory
        if history.last?.id == song.id { history.removeLast() }
        lastPlaybackDirection = .previous
    }


    // ========================================================
    // MARK: - Queue Operations
    // ========================================================

    func addToQueue(
        _ song: Song
    ) {

        if !queue.contains(
            where: {
                $0.id ==
                    song.id
            }
        ) {

            queue.append(
                song
            )
        }
    }


    func playFromQueue(
        _ song: Song
    ) {

        let upcomingIndex = queue.indices.first {
            $0 > currentIndex && queue[$0].id == song.id
        }
        guard let index = upcomingIndex ?? queue.firstIndex(where: { $0.id == song.id }) else { return }
        currentIndex =
            index


        playSongAtIndex()
    }


    func moveQueue(
        from source: IndexSet,
        to destination: Int
    ) {

        queue.move(
            fromOffsets:
                source,

            toOffset:
                destination
        )
    }


    func removeFromQueue(
        at offsets: IndexSet
    ) {

        queue.remove(
            atOffsets:
                offsets
        )
    }


    // ========================================================
    // MARK: - Auto Next
    // ========================================================

    func fillAutoNext(
        from songs: [Song]
    ) {

        while autoNextQueue.count <
            10 {

            let availableSongs =
                songs.filter {
                    song in


                    song.id !=
                        currentSong?.id
                    &&
                    !queue.contains(
                        where: {
                            $0.id ==
                                song.id
                        }
                    )
                    &&
                    !autoNextQueue.contains(
                        where: {
                            $0.id ==
                                song.id
                        }
                    )
                }


            guard let randomSong =
                availableSongs
                    .randomElement()
            else {
                return
            }


            autoNextQueue.append(
                randomSong
            )
        }
    }


    // ========================================================
    // MARK: - Play / Pause
    // ========================================================

    func togglePlayPause() {
        if let podcastPlayer {
            if podcastPlayer.currentItem?.status == .failed, let song = currentSong, let url = getURL(for: song) {
                play(song: song, url: url, queue: queue, queuePosition: currentIndex)
                return
            }
            podcastWantsPlayback.toggle()
            if podcastWantsPlayback { podcastPlayer.playImmediately(atRate: podcastSpeed) }
            else { podcastPlayer.pause(); savePodcastPosition() }
            isPlaying = podcastWantsPlayback
            updateNowPlaying()
            return
        }

        guard let player else {
            return
        }


        if player.isPlaying {

            player.pause()

            isPlaying =
                false


        } else {

            player.play()

            isPlaying =
                player.isPlaying


            startTimer()
        }


        updateNowPlaying()
    }


    // ========================================================
    // MARK: - Shuffle
    // ========================================================

    func toggleShuffle() {

        shuffleEnabled
            .toggle()


        if shuffleEnabled {

            if originalQueue
                .isEmpty {

                originalQueue =
                    queue
            }


            let playedSongs =
                Array(
                    queue.prefix(
                        currentIndex + 1
                    )
                )


            let upcomingSongs =
                Array(
                    queue.dropFirst(
                        currentIndex + 1
                    )
                )
                .shuffled()


            queue =
                playedSongs
                +
                upcomingSongs


        } else {

            if
                let current =
                    currentSong,

                let originalIndex =
                    originalQueue
                        .firstIndex(
                            where: {
                                $0.id ==
                                    current.id
                            }
                        ) {

                queue =
                    originalQueue


                currentIndex =
                    originalIndex
            }
        }
    }


    // ========================================================
    // MARK: - Repeat
    // ========================================================

    func toggleRepeat() {

        switch repeatMode {

        case .off:
            repeatMode =
                .all

        case .all:
            repeatMode =
                .one

        case .one:
            repeatMode =
                .off
        }
    }


    // ========================================================
    // MARK: - Timer
    // ========================================================

    private func startTimer() {

        timer?
            .invalidate()


        timer =
            Timer.scheduledTimer(
                withTimeInterval:
                    0.1,

                repeats:
                    true
            ) {
                [weak self]
                _ in


                guard let self else {
                    return
                }


                let playing = self.player?.isPlaying ?? false
                if self.isPlaying != playing {
                    self.isPlaying = playing
                    self.updateNowPlaying()
                }
                self.currentTime =
                    self.player?
                        .currentTime
                    ??
                    0
            }
    }


    // ========================================================
    // MARK: - Seeking
    // ========================================================

    func seek(
        to time: Double
    ) {
        if let podcastPlayer {
            guard time.isFinite else { return }
            let target = max(0, duration > 0 ? min(time, duration) : time)
            currentTime = target
            podcastPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600))
            if let id = currentSong?.podcastEpisodeID { PodcastStore.shared.record(id, position: target) }
            updateNowPlaying()
            return
        }

        player?
            .currentTime =
            time


        currentTime =
            time


        updateNowPlaying()
    }


    func pauseForSeeking() {
        if let podcastPlayer { podcastPlayer.pause(); return }

        player?
            .pause()
    }


    func resumeAfterSeeking() {
        if let podcastPlayer {
            if podcastWantsPlayback { podcastPlayer.playImmediately(atRate: podcastSpeed) }
            updateNowPlaying()
            return
        }

        player?
            .play()


        updateNowPlaying()
    }


    // ========================================================
    // MARK: - Song URL
    // ========================================================

    func getURL(
        for song: Song
    ) -> URL? {
        if let id = song.podcastEpisodeID, let episode = PodcastStore.shared.state.episodes[id] {
            return PodcastStore.shared.playbackURL(episode)
        }

        return FileManager.default
            .urls(
                for:
                    .documentDirectory,

                in:
                    .userDomainMask
            )[0]
            .appendingPathComponent(
                song.fileName
            )
    }


    // ========================================================
    // MARK: - EqualizedAudioPlayer Delegate
    // ========================================================

    func audioPlayerDidFinishPlaying(
        _ player: EqualizedAudioPlayer,
        successfully flag: Bool
    ) {

        guard self.player === player else { return }
        guard flag else {
            isPlaying = false
            updateNowPlaying()
            return
        }

        if repeatMode ==
            .one {

            if
                let song =
                    currentSong,

                let url =
                    getURL(
                        for:
                            song
                    ) {

                play(
                    song:
                        song,

                    url:
                        url,

                    queue:
                        queue, queuePosition: currentIndex, repeatingCurrent: true
                )
            }


        } else {

            next(manuallyInitiated: false)
        }
    }
}

extension AudioPlayerManager {
    func playPodcast(_ episode: PodcastEpisode) {
        let song = podcastSong(episode)
        play(song: song, url: PodcastStore.shared.playbackURL(episode), queue: [song])
    }

    func queuePodcastNext(_ episode: PodcastEpisode) {
        let song = podcastSong(episode)
        if currentSong == nil { playPodcast(episode) }
        else { playNext(song) }
    }

    private func podcastSong(_ episode: PodcastEpisode) -> Song {
        PodcastStore.shared.remember(episode)
        PodcastStore.shared.flush()
        var song = Song(id: episode.playbackID, title: episode.title, artist: episode.show.title,
                        fileName: "", coverData: PodcastStore.shared.artwork(episode))
        song.podcastEpisodeID = episode.id
        return song
    }

    func setPodcastSpeed(_ speed: Float) {
        guard [Float(0.75), 1, 1.25, 1.5, 1.75, 2].contains(speed) else { return }
        podcastSpeed = speed
        if podcastWantsPlayback { podcastPlayer?.rate = speed }
        updateNowPlaying()
    }

    func savePodcastPosition() {
        guard let id = currentSong?.podcastEpisodeID else { return }
        PodcastStore.shared.record(id, position: currentTime)
        PodcastStore.shared.flush()
    }

    private func stopPodcastPlayback() {
        guard let podcastPlayer else { return }
        savePodcastPosition()
        podcastPlayer.pause()
        if let token = podcastTimeObserver { podcastPlayer.removeTimeObserver(token) }
        for token in [podcastEndObserver, podcastInterruptionObserver, podcastRouteObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(token)
        }
        podcastTimeObserver = nil
        podcastEndObserver = nil
        podcastInterruptionObserver = nil
        podcastRouteObserver = nil
        podcastStatusObserver = nil
        podcastArtworkTask?.cancel()
        self.podcastPlayer = nil
        podcastWantsPlayback = false
        let commands = MPRemoteCommandCenter.shared()
        commands.skipBackwardCommand.isEnabled = false
        commands.skipForwardCommand.isEnabled = false
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
    }

    private func startPodcastPlayback(_ episode: PodcastEpisode, song: Song) {
        player?.stop()
        player = nil
        timer?.invalidate()
        preloadedPlayer?.stop()
        preloadedPlayer = nil
        lyricsTask?.cancel()
        currentLyrics = nil
        currentSyncedLyrics = nil
        isLoadingLyrics = false
        shuffleEnabled = false
        repeatMode = .off
        autoNextQueue = []
        if let old = currentSong, old.id != song.id { history.append(old) }
        currentSong = song
        let store = PodcastStore.shared
        store.beginListening(episode.id)
        currentTime = store.state.listening[episode.id]?.position ?? 0
        duration = episode.duration ?? 0
        podcastLastSaved = -1
        podcastDidPrepare = false
        let resumePosition = currentTime
        let item = AVPlayerItem(url: store.playbackURL(episode))
        item.audioTimePitchAlgorithm = .timeDomain
        let stream = AVPlayer(playerItem: item)
        podcastPlayer = stream
        podcastWantsPlayback = true
        isPlaying = true
        podcastStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            DispatchQueue.main.async {
                guard let self, let item, self.podcastPlayer?.currentItem === item else { return }
                if item.status == .failed {
                    self.podcastWantsPlayback = false
                    self.isPlaying = false
                    store.errorKey = "podcasts_playback_error"
                    self.updateNowPlaying()
                } else if item.status == .readyToPlay, !self.podcastDidPrepare {
                    self.podcastDidPrepare = true
                    let length = item.duration.seconds
                    if length.isFinite, length > 0 { self.duration = length }
                    let position = self.duration > 0 ? min(resumePosition, max(0, self.duration - 1)) : resumePosition
                    self.podcastPlayer?.seek(to: CMTime(seconds: position, preferredTimescale: 600)) { [weak self, weak item] finished in
                        DispatchQueue.main.async {
                            guard let self, let item, self.podcastPlayer?.currentItem === item, finished else { return }
                            self.currentTime = position
                            if self.podcastWantsPlayback { self.podcastPlayer?.playImmediately(atRate: self.podcastSpeed) }
                            self.updateNowPlaying()
                        }
                    }
                }
            }
        }
        podcastTimeObserver = stream.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self, weak stream] time in
            guard let self, let stream, self.podcastPlayer === stream, self.podcastDidPrepare,
                  stream.timeControlStatus == .playing else { return }
            let seconds = time.seconds
            if seconds.isFinite { self.currentTime = max(0, seconds) }
            if let length = stream.currentItem?.duration.seconds, length.isFinite, length > 0 { self.duration = length }
            if abs(self.currentTime - self.podcastLastSaved) >= 5 {
                self.podcastLastSaved = self.currentTime
                store.record(episode.id, position: self.currentTime)
                self.updateNowPlaying()
            }
        }
        podcastEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self, self.currentSong?.podcastEpisodeID == episode.id else { return }
            self.currentTime = 0
            store.record(episode.id, position: 0, completed: true)
            self.next(manuallyInitiated: false)
        }
        podcastInterruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self.podcastResumeAfterInterruption = self.podcastWantsPlayback
                if self.podcastWantsPlayback { self.togglePlayPause() }
            } else {
                let rawOptions = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                if options.contains(.shouldResume), self.podcastResumeAfterInterruption, !self.podcastWantsPlayback {
                    self.setupAudioSession()
                    self.togglePlayPause()
                }
                self.podcastResumeAfterInterruption = false
            }
        }
        podcastRouteObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            if self.podcastWantsPlayback { self.togglePlayPause() }
        }
        let commands = MPRemoteCommandCenter.shared()
        commands.skipBackwardCommand.isEnabled = true
        commands.skipForwardCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = false
        UIApplication.shared.beginReceivingRemoteControlEvents()
        updateNowPlaying()
        podcastArtworkTask = Task { @MainActor [weak self] in
            guard let url = episode.artworkURL else { return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode), data.count < 5_000_000,
                      UIImage(data: data) != nil else { return }
                store.cacheArtwork(data, episode: episode)
                guard let self, self.currentSong?.podcastEpisodeID == episode.id else { return }
                self.currentSong?.coverData = data
                self.updateNowPlaying()
            } catch { /* Artwork failure does not interrupt audio. */ }
        }
    }

    private func updatePodcastNowPlaying() {
        guard let song = currentSong else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(podcastSpeed) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(podcastSpeed)]
        if let data = song.coverData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
