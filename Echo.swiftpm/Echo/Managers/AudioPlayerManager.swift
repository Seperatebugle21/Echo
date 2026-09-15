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

        let commandCenter =
            MPRemoteCommandCenter
                .shared()


        commandCenter
            .playCommand
            .addTarget {
                [weak self]
                _ in


                self?
                    .togglePlayPause()


                return .success
            }


        commandCenter
            .pauseCommand
            .addTarget {
                [weak self]
                _ in


                self?
                    .togglePlayPause()


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
        guard let url = getURL(for: song), FileManager.default.fileExists(atPath: url.path) else { return }
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
        guard player?.isPlaying == true else {
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

        player?
            .currentTime =
            time


        currentTime =
            time


        updateNowPlaying()
    }


    func pauseForSeeking() {

        player?
            .pause()
    }


    func resumeAfterSeeking() {

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

        FileManager.default
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
