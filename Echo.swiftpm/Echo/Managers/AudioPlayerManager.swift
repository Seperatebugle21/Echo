import Foundation
import AVFoundation
import MediaPlayer
import AVFAudio
import UIKit


enum RepeatMode:
    Equatable {

    case off
    case all
    case one
}


@Observable
class AudioPlayerManager:
    NSObject,
    AVAudioPlayerDelegate {

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
        AVAudioPlayer?


    private var timer:
        Timer?


    private var preloadedSong:
        Song?


    private var preloadedPlayer:
        AVAudioPlayer?


    var currentLyrics:
        String?


    var currentSyncedLyrics:
        String?


    var lyricsNeedsInternet =
        false


    var isPlaying =
        false


    var currentSong:
        Song?


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
        queue: [Song] = []
    ) {

        setupAudioSession()


        if !queue.isEmpty {

            self.queue =
                queue


            self.originalQueue =
                queue
        }


        if let index =
            self.queue
                .firstIndex(
                    where: {

                        $0.id ==
                            song.id
                    }
                ) {

            currentIndex =
                index
        }


        do {

            timer?
                .invalidate()


            player =
                try AVAudioPlayer(
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
                true


            updateNowPlaying()

            startTimer()

            fillQueue(
                from:
                    queue
            )


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

    func loadLyrics(
        for song: Song
    ) {

        if let savedSong =
            MusicLibraryManager.shared
                .songs
                .first(
                    where: {

                        $0.id ==
                            song.id
                    }
                ) {

            if
                savedSong.lyrics !=
                    nil
                ||
                savedSong.syncedLyrics !=
                    nil {

                currentLyrics =
                    savedSong.lyrics


                currentSyncedLyrics =
                    savedSong.syncedLyrics


                lyricsNeedsInternet =
                    false


                print(
                    "Opgeslagen lyrics geladen voor:",
                    song.title
                )


                return
            }
        }


        lyricsNeedsInternet =
            false


        Task {

            let result =
                await lyricsManager
                    .fetchLyrics(
                        for:
                            song,

                        duration:
                            duration
                    )


            await MainActor.run {

                if let result {

                    self.currentLyrics =
                        result.plainLyrics


                    self.currentSyncedLyrics =
                        result.syncedLyrics


                    self.lyricsNeedsInternet =
                        false


                    MusicLibraryManager.shared
                        .updateLyrics(
                            for:
                                song,

                            lyrics:
                                result.plainLyrics,

                            syncedLyrics:
                                result.syncedLyrics
                        )


                    print(
                        "Nieuwe lyrics opgeslagen voor:",
                        song.title
                    )


                } else {

                    self.currentLyrics =
                        nil


                    self.currentSyncedLyrics =
                        nil


                    self.lyricsNeedsInternet =
                        true


                    print(
                        "Geen opgeslagen lyrics en ophalen mislukt voor:",
                        song.title
                    )
                }
            }
        }
    }


    // ========================================================
    // MARK: - Next
    // ========================================================

    func next() {

        lastPlaybackDirection =
            .next


        if repeatMode ==
            .one {

            repeatMode =
                .all
        }


        if queue.count >
            currentIndex + 1 {

            currentIndex +=
                1


            playPreloadedOrNextSong()

            return
        }


        if
            repeatMode ==
                .all,

            !queue.isEmpty {

            currentIndex =
                0


            playSongAtIndex()

            return
        }


        if let nextSong =
            autoNextQueue.first {

            autoNextQueue
                .removeFirst()


            if let url =
                getURL(
                    for:
                        nextSong
                ) {

                play(
                    song:
                        nextSong,

                    url:
                        url,

                    queue:
                        []
                )


                fillAutoNext(
                    from:
                        allSongs
                )
            }


            return
        }


        isPlaying =
            false


        updateNowPlaying()
    }


    // ========================================================
    // MARK: - Preloaded Next
    // ========================================================

    private func playPreloadedOrNextSong() {

        let song =
            queue[
                currentIndex
            ]


        if
            preloadedSong?.id ==
                song.id,

            let preparedPlayer =
                preloadedPlayer {

            player?
                .stop()


            player =
                preparedPlayer


            player?
                .delegate =
                self


            currentSong =
                song


            currentTime =
                0


            duration =
                player?
                    .duration
                ??
                0


            preloadedSong =
                nil


            preloadedPlayer =
                nil


            player?
                .play()


            isPlaying =
                true


            startTimer()

            updateNowPlaying()


        } else {

            playSongAtIndex()
        }
    }


    // ========================================================
    // MARK: - Previous
    // ========================================================

    func previous() {

        lastPlaybackDirection =
            .previous


        if repeatMode ==
            .one {

            repeatMode =
                .all
        }


        if currentTime >
            3 {

            seek(
                to:
                    0
            )


            return
        }


        if let previousSong =
            history.popLast() {

            playPreviousSong(
                previousSong
            )


        } else {

            seek(
                to:
                    0
            )
        }
    }


    // ========================================================
    // MARK: - Play Next
    // ========================================================

    func playNext(
        _ song: Song
    ) {

        guard let currentIndex =
            queue.firstIndex(
                where: {

                    $0.id ==
                        currentSong?.id
                }
            )

        else {

            return
        }


        queue.removeAll {

            $0.id ==
                song.id
        }


        queue.insert(
            song,

            at:
                currentIndex + 1
        )
    }


    // ========================================================
    // MARK: - Play Song At Index
    // ========================================================

    private func playSongAtIndex() {

        guard queue.indices
            .contains(
                currentIndex
            )

        else {

            return
        }


        let song =
            queue[
                currentIndex
            ]


        if let url =
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
                    queue
            )
        }
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


        let upcoming =
            queue
                .drop(
                    while: {

                        $0.id !=
                            currentSong.id
                    }
                )
                .dropFirst()


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

    func playPreviousSong(
        _ song: Song
    ) {

        guard let url =
            getURL(
                for:
                    song
            )

        else {

            return
        }


        player?
            .stop()


        player =
            try? AVAudioPlayer(
                contentsOf:
                    url
            )


        player?
            .delegate =
            self


        duration =
            player?
                .duration
            ??
            0


        currentTime =
            0


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


        isPlaying =
            true


        startTimer()

        updateNowPlaying()
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

        guard let index =
            queue.firstIndex(
                where: {

                    $0.id ==
                        song.id
                }
            )

        else {

            return
        }


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
                true


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
    // MARK: - AVAudioPlayer Delegate
    // ========================================================

    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {

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
                        queue
                )
            }


        } else {

            next()
        }
    }
}
