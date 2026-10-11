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
    private var playbackRequest = UUID()
    private var localIntent = PlaybackIntent()
    var playbackGeneration: UUID { playbackRequest }
    private var transitionTask: Task<Void, Never>?
    private var transitionStarts: [UUID: Song] = [:]
    private typealias PreparedTransition = (token: UUID, song: Song, index: Int?, automatic: Bool)
    private var transitionTarget: PreparedTransition?
    private var transitionCancellationPending = false
    private var lastTransitionMode = AudioSettings.transition
    private var lastFadeSeconds = AudioSettings.crossfadeSeconds
    private var lastPublishedRate = 1.0
    var localPlaybackState: LocalPlaybackState = .idle
    var playbackErrorKey: String?
    var isPreparingAudio: Bool { !isPodcast && localPlaybackState.isBusy }
    @ObservationIgnored private var artworkSongID: UUID?
    @ObservationIgnored private var lockscreenArtwork: MPMediaItemArtwork?
    @ObservationIgnored private var lockscreenArtworkTask: Task<Void, Never>?
    var isPreviewing = false
    private var previewPlayer: EqualizedAudioPlayer?
    private var previewResume = false
    private var previewTimeout: Task<Void, Never>?
    private var previewNextURL: URL?
    var previewFinished: (() -> Void)?

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
        [Song] = [] {
        didSet { requestFlowRefill() }
    }

    private(set) var flowActive = false
    var flowMode: EchoFlowMode = EchoFlowMode(rawValue: UserDefaults.standard.string(forKey: "EchoFlowModeV1") ?? "familiar") ?? .familiar {
        didSet { UserDefaults.standard.set(flowMode.rawValue, forKey: "EchoFlowModeV1"); requestFlowRefill() }
    }
    private(set) var flowSongIDs: Set<UUID> = []
    @ObservationIgnored private var flowRecent: [UUID] = []
    @ObservationIgnored private var flowRefillTask: Task<Void, Never>?
    @ObservationIgnored private var flowGeneration = UUID()
    @ObservationIgnored private var flowSeed: UInt64 = 0
    @ObservationIgnored private var flowFailedIDs: Set<UUID> = []


    private var originalQueue:
        [Song] = []


    var currentIndex:
        Int =
        0 { didSet { requestFlowRefill() } }


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
        .off { didSet { requestFlowRefill() } }


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
        guard !isPreviewing else { return }
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
            currentTime


        info[
            MPMediaItemPropertyPlaybackDuration
        ] =
            duration


        info[
            MPNowPlayingInfoPropertyPlaybackRate
        ] =
            isPlaying
            ? player.currentRate
            : 0.0


        if artworkSongID != song.id {
            artworkSongID = song.id; lockscreenArtwork = nil; lockscreenArtworkTask?.cancel()
            let data = song.coverData
            lockscreenArtworkTask = Task { @MainActor [weak self] in
                let image = await CoverThumbnailCache.shared.image(data: data, builtin: nil, pixels: 512)
                guard !Task.isCancelled, let self, self.currentSong?.id == song.id, !self.isPreviewing else { return }
                if let image { self.lockscreenArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
                self.updateNowPlaying()
            }
        }
        if let lockscreenArtwork { info[MPMediaItemPropertyArtwork] = lockscreenArtwork }

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


                self?.setPlaybackDesired(true)


                return .success
            }


        commandCenter
            .pauseCommand
            .addTarget {
                [weak self]
                _ in


                self?.setPlaybackDesired(false)


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
        recordListeningChange(repeatingCurrent ? .completed : .selected)
        if song.podcastEpisodeID != nil { stopEchoFlow() }
        stopTransitionPreview(resume: false)
        transitionTask?.cancel(); transitionTask = nil; transitionTarget = nil
        transitionCancellationPending = false
        transitionStarts.removeAll()
        playbackRequest = UUID()
        localIntent.set(true)
        lastTransitionMode = AudioSettings.transition
        lastFadeSeconds = AudioSettings.crossfadeSeconds
        playbackErrorKey = nil
        localPlaybackState = .preparing

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
        if PlaybackRecommendations.consume(song.id, from: &autoNextQueue) {
            fillAutoNext(from: allSongs)
        }
        if let id = song.podcastEpisodeID, let episode = PodcastStore.shared.state.episodes[id] {
            startPodcastPlayback(episode, song: song)
            return
        }
        do {

            timer?
                .invalidate()


            if let player { try player.replace(with: url) }
            else { player = try EqualizedAudioPlayer(contentsOf: url) }
            let request = playbackRequest
            player?.onStateChanged = { [weak self, weak player = self.player] update in
                guard let self, let player, self.player === player,
                    self.playbackRequest == request, !self.isPreviewing,
                    update.intentRevision == self.localIntent.revision else { return }
                self.localIntent.reconcile(update.wantsPlayback, revision: update.intentRevision)
                RecommendationManager.shared.playbackStateChanged(position: update.position,
                    playing: self.isPlaying && (self.localPlaybackState == .playing || self.localPlaybackState == .transitioning))
                self.localPlaybackState = update.state
                self.currentTime = update.position
                self.duration = update.duration
                self.isPlaying = update.wantsPlayback && update.state != .failed && update.state != .idle
                if update.state == .failed {
                    RecommendationManager.shared.playbackWillChange(.failed, position: update.position, playing: false)
                    self.continueFlowAfterFailure()
                }
                self.updateNowPlaying()
            }
            player?.onStarted = { [weak self] identifier in
                    guard let self, self.playbackRequest == request, !self.isPreviewing else { return }
                    let started = identifier.flatMap { self.transitionStarts.removeValue(forKey: $0) } ?? (identifier == nil ? self.currentSong : nil)
                    if let started {
                        if identifier != nil {
                            RecommendationManager.shared.playbackWillChange(.completed, position: self.currentTime, playing: self.isPlaying)
                        }
                        RecommendationManager.shared.playbackStarted(started)
                        self.flowRecent.append(started.id)
                        if self.flowRecent.count > 40 { self.flowRecent.removeFirst(self.flowRecent.count - 40) }
                        self.requestFlowRefill()
                        MusicLibraryManager.shared.markAsPlayed(started)
                        self.donatePlaybackToSiri(song: started)
                        if identifier == nil { self.loadLyrics(for: started); self.fillQueue(from: queue) }
                    }
            }
            player?.onPromote = { [weak self] token in self?.promoteTransition(token) }


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


                let commands = MPRemoteCommandCenter.shared()
                commands.skipBackwardCommand.isEnabled = false
                commands.skipForwardCommand.isEnabled = false
                commands.nextTrackCommand.isEnabled = true
                commands.previousTrackCommand.isEnabled = true


            currentLyrics =
                nil


            currentSyncedLyrics =
                nil





            player?
                .play(intentRevision: localIntent.revision)


            UIApplication.shared
                .beginReceivingRemoteControlEvents()


            isPlaying = true


            updateNowPlaying()

            startTimer()


            if !repeatingCurrent { updateRepeatForSelection() }

        } catch {
            playbackErrorKey = "audio_playback_failed"
            localPlaybackState = .failed; isPlaying = false
            currentSong = song
            Task { @MainActor [weak self] in
                RecommendationManager.shared.playbackWillChange(.failed, position: 0, playing: false)
                self?.continueFlowAfterFailure()
            }
            updateNowPlaying()
        }
    }


    private func nextTransitionSong() -> (song: Song, index: Int?, automatic: Bool)? {
        if repeatMode == .one, let song = currentSong { return (song, currentIndex, false) }
        if queue.indices.contains(currentIndex + 1) { return (queue[currentIndex + 1], currentIndex + 1, false) }
        if repeatMode == .all, let first = queue.first { return (first, 0, false) }
        if flowActive { return nil }
        return autoNextQueue.first.map { ($0, nil, true) }
    }
    private func prepareAutomaticTransition() {
        guard !isPreviewing, !isPodcast, !transitionCancellationPending,
              let player, player.isPlaying, let currentSong else { return }
        let mode = AudioSettings.transition, seconds = AudioSettings.crossfadeSeconds
        let next = nextTransitionSong()
        if lastTransitionMode != mode || lastFadeSeconds != seconds ||
           (transitionTarget != nil && (transitionTarget?.song.id != next?.song.id || transitionTarget?.index != next?.index || transitionTarget?.automatic != next?.automatic)) {
            cancelUpcomingTransition()
            lastTransitionMode = mode; lastFadeSeconds = seconds
            return
        }
        guard mode != .direct, player.canPrepareNext, transitionTask == nil,
              player.duration - player.currentTime > (mode == .gapless ? 0.5 : min(mode == .crossfade ? seconds : 12, player.duration / 2) + 0.5),
              let next, next.song.podcastEpisodeID == nil,
              let outgoingURL = getURL(for: currentSong), let incomingURL = getURL(for: next.song) else { return }
        let request = playbackRequest, token = UUID(), outgoingDuration = player.duration
        transitionTarget = (token, next.song, next.index, next.automatic)
        transitionStarts[token] = next.song
        transitionTask = Task { @MainActor [weak self] in
            defer {
                if self?.playbackRequest == request && self?.transitionTarget?.token == token {
                    self?.transitionTask = nil
                }
            }
            do {
                let duration = try await AVURLAsset(url: incomingURL).load(.duration).seconds
                var outro = BeatAnalysis(), intro = BeatAnalysis()
                if mode == .mix {
                    outro = (try? await AudioBeatCache.shared.analysis(outgoingURL).outro) ?? BeatAnalysis()
                    intro = (try? await AudioBeatCache.shared.analysis(incomingURL).intro) ?? BeatAnalysis()
                }
                try Task.checkCancellation()
                guard let self, self.playbackRequest == request, self.transitionTarget?.token == token,
                      self.nextTransitionSong()?.song.id == next.song.id else { return }
                let plan = AudioTransitionPlan.make(mode: mode, seconds: seconds, outgoingDuration: outgoingDuration,
                                                    incomingDuration: duration, outro: outro, intro: intro)
                player.prepareNext(url: incomingURL, identifier: token, plan: plan)
            } catch {
                if self?.transitionTarget?.token == token { self?.transitionTarget = nil; self?.transitionTask = nil }
            }
        }
    }
    private func cancelUpcomingTransition() {
        guard !transitionCancellationPending else { return }
        let target = transitionTarget, request = playbackRequest
        transitionTask?.cancel(); transitionTask = nil; transitionTarget = nil
        guard let player else { return }
        transitionCancellationPending = true
        player.cancelPreparedNext { [weak self] promoted in
            guard let self, self.playbackRequest == request else { return }
            self.transitionCancellationPending = false
            // A promotion can reach the render thread just before this edit.
            // Preserve that audible song even if its UI callback was pending.
            if let target, promoted == target.token { self.promoteTransition(target: target) }
            else if let target { self.transitionStarts.removeValue(forKey: target.token) }
            self.prepareAutomaticTransition()
        }
    }
    private func promoteTransition(_ token: UUID) {
        guard let target = transitionTarget, target.token == token, !isPreviewing else { return }
        promoteTransition(target: target)
        transitionTarget = nil
    }
    private func promoteTransition(target: PreparedTransition) {
        guard !isPreviewing else { return }
        lastPlaybackDirection = .next
        if let old = currentSong, old.id != target.song.id { history.append(old) }
        if let index = target.index, queue.indices.contains(index), queue[index].id == target.song.id {
            currentIndex = index
        } else if let index = queue.firstIndex(where: { $0.id == target.song.id }) {
            currentIndex = index
        }
        else {
            queue.append(target.song); currentIndex = queue.count - 1
        }
        currentSong = target.song
        if target.automatic {
            PlaybackRecommendations.consume(target.song.id, from: &autoNextQueue)
            fillAutoNext(from: allSongs)
        }
        currentTime = player?.currentTime ?? 0; duration = player?.duration ?? 0
        currentLyrics = nil; currentSyncedLyrics = nil
        loadLyrics(for: target.song); updateNowPlaying()
    }

    @MainActor func startTransitionPreview(first: URL, second: URL) async throws {
        stopTransitionPreview()
        let request = playbackRequest
        previewResume = isPlaying
        isPreviewing = true
        if let podcastPlayer { podcastPlayer.pause() } else { player?.pause() }
        do {
            let demo = try EqualizedAudioPlayer(contentsOf: first)
            previewPlayer = demo
            let demoDuration = try await demo.preparedDuration()
            let mode = AudioSettings.transition
            let nextDuration = try await AVURLAsset(url: second).load(.duration).seconds
            var intro = BeatAnalysis(), outro = BeatAnalysis()
            if mode == .mix {
                outro = try await AudioBeatCache.shared.analysis(first).outro
                intro = try await AudioBeatCache.shared.analysis(second).intro
            }
            try Task.checkCancellation()
            guard request == playbackRequest, isPreviewing else { return }
            let plan = AudioTransitionPlan.make(mode: mode, seconds: AudioSettings.crossfadeSeconds,
                outgoingDuration: demoDuration, incomingDuration: nextDuration, outro: outro, intro: intro)
            demo.currentTime = max(0, demoDuration - min(15, max(4, plan.overlap + 2)))
            demo.onStarted = { [weak self, weak demo] id in
                guard id == nil, let self, self.isPreviewing else { return }
                if mode == .direct {
                    // Direct demo starts B only after A has finished.
                    return
                }
                demo?.prepareNext(url: second, identifier: UUID(), plan: plan)
            }
            demo.delegate = self
            if mode == .direct { previewNextURL = second }
            demo.play()
            previewTimeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(20))
                if !Task.isCancelled { self?.stopTransitionPreview() }
            }
        } catch { stopTransitionPreview(); throw error }
    }
    func stopTransitionPreview(resume: Bool = true) {
        guard isPreviewing else { return }
        previewTimeout?.cancel(); previewTimeout = nil
        previewPlayer?.stop(); previewPlayer = nil; previewNextURL = nil
        isPreviewing = false
        if resume && previewResume {
            if let podcastPlayer, podcastWantsPlayback { podcastPlayer.playImmediately(atRate: podcastSpeed) }
            else { setPlaybackDesired(true) }
        } else if !isPodcast {
            setPlaybackDesired(false)
        }
        previewResume = false
        let finished = previewFinished; previewFinished = nil; finished?()
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
            if let saved = MusicLibraryManager.shared.song(withID: song.id),
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
        recordListeningChange(manuallyInitiated ? .skipped : .completed)
        stopTransitionPreview(resume: false)
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
            queue.append(nextSong)
            currentIndex = queue.count - 1
            play(song: nextSong, url: url, queue: queue, queuePosition: currentIndex)
            return
        }
        player?.stop()
        localIntent.set(false)
        localPlaybackState = .idle
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
        stopTransitionPreview(resume: false)
        lastPlaybackDirection = .previous

        if currentTime > 3 { updateRepeatForSelection(); seek(to: 0); return }
        if let song = previousQueuedSong { playPreviousSong(song) }
        else { updateRepeatForSelection(); seek(to: 0) }
    }

    private func updateRepeatForSelection() {
        guard !flowActive else { return }
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
        flowSongIDs.remove(song.id)
        guard let currentSong else { return }
        if !queue.indices.contains(currentIndex) || queue[currentIndex].id != currentSong.id {
            queue = [currentSong]
            currentIndex = 0
        }
        // Never remove the playing occurrence or invalidate its insertion index.
        let prefix = Array(queue.prefix(currentIndex + 1))
        let upcoming = queue.dropFirst(currentIndex + 1).filter { $0.id != song.id }
        queue = prefix + [song] + upcoming
        cancelUpcomingTransition()
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
        guard !flowActive else { requestFlowRefill(); return }

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

            let queuedIDs = Set(queue.map(\.id))
            let availableSongs = songs.filter { $0.id != currentSong.id && !queuedIDs.contains($0.id) }


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
        guard player?.stateValue != .failed || podcastPlayer != nil else {
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
        flowSongIDs.remove(song.id)

        if !queue.contains(
            where: {
                $0.id ==
                    song.id
            }
        ) {

            queue.append(
                song
            )
            cancelUpcomingTransition()
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
        cancelUpcomingTransition()

    }


    func removeFromQueue(
        at offsets: IndexSet
    ) {

        queue.remove(
            atOffsets:
                offsets
        )
        cancelUpcomingTransition()

    }


    // ========================================================
    /// Atomically replace upcoming songs and cancel any preloaded transition.
    /// Keep the playing occurrence, history and shuffle's original queue consistent.
    func replaceIntelligenceUpcoming(_ songs: [Song]) {
        cancelUpcomingTransition()
        let prefix: [Song]
        if let currentSong, queue.indices.contains(currentIndex), queue[currentIndex].id == currentSong.id {
            prefix = Array(queue.prefix(currentIndex + 1))
        } else { prefix = currentSong.map { [$0] } ?? []; currentIndex = 0 }
        queue = prefix + songs
        originalQueue = queue
        autoNextQueue.removeAll()
        flowSongIDs.removeAll()
    }

    func setIntelligenceDucking(_ enabled: Bool) {
        player?.setIntelligenceGain(enabled ? 0.25 : 1)
        podcastPlayer?.volume = enabled ? 0.25 : 1
    }

    // MARK: - Auto Next
    // ========================================================

    func fillAutoNext(
        from songs: [Song]
    ) {
        guard !flowActive else { return }

        PlaybackRecommendations.refill(&autoNextQueue, from: songs, queue: queue, currentSongID: currentSong?.id)
    }


    // ========================================================
    // MARK: - Play / Pause
    // ========================================================

    func retryPlayback() {
        guard let song = currentSong, let url = getURL(for: song) else { return }
        play(song: song, url: url, queue: queue, queuePosition: currentIndex)
    }
    func togglePlayPause() {
        setPlaybackDesired(!(isPodcast ? podcastWantsPlayback : localIntent.wantsPlayback))
    }

    func setPlaybackDesired(_ playing: Bool) {
        if isPreviewing {
            stopTransitionPreview(resume: false)
        }
        if let podcastPlayer {
            if playing, podcastPlayer.currentItem?.status == .failed,
                let song = currentSong, let url = getURL(for: song) {
                play(song: song, url: url, queue: queue, queuePosition: currentIndex)
                return
            }
            podcastWantsPlayback = playing
            if playing { podcastPlayer.playImmediately(atRate: podcastSpeed) }
            else { podcastPlayer.pause(); savePodcastPosition() }
            isPlaying = playing
            updateNowPlaying()
            return
        }
        guard let player else { return }
        let listeningPosition = player.currentTime
        let wasPlaying = isPlaying
        Task { @MainActor in
            RecommendationManager.shared.playbackStateChanged(position: listeningPosition, playing: wasPlaying)
            if !playing { RecommendationManager.shared.flush() }
            RecommendationManager.shared.playbackSeeked(position: listeningPosition)
        }
        if playing, player.stateValue == .failed { retryPlayback(); return }
        let revision = localIntent.set(playing)
        let request = playbackRequest
        isPlaying = playing
        localPlaybackState = playing ? .preparing : .paused
        currentTime = player.currentTime
        if playing {
            player.play(intentRevision: revision)
            startTimer()
        } else {
            player.pause(intentRevision: revision) { [weak self, weak player] in
                guard let self, let player, self.player === player,
                    self.playbackRequest == request, self.localIntent.revision == revision else { return }
                self.localPlaybackState = player.stateValue
                self.currentTime = player.currentTime
                self.updateNowPlaying()
            }
        }
        // The engine's queued command may not have changed its snapshot yet.
        // Publish the latest intention now, then re-anchor on its state callback.
        updateNowPlaying()
    }


    // ========================================================
    // MARK: - Shuffle
    // ========================================================

    func toggleShuffle() {

        if flowActive && shuffleEnabled {
            shuffleEnabled = false
            let order = Dictionary(originalQueue.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
            let played = Array(queue.prefix(currentIndex + 1))
            let upcoming = queue.dropFirst(currentIndex + 1).enumerated().sorted {
                let left = order[$0.element.id] ?? (originalQueue.count + $0.offset)
                let right = order[$1.element.id] ?? (originalQueue.count + $1.offset)
                return left < right
            }.map(\.element)
            queue = played + upcoming
            cancelUpcomingTransition()
            return
        }

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
        cancelUpcomingTransition()

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
        cancelUpcomingTransition()
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


                guard !self.isPreviewing else { return }
                self.duration = self.player?.duration ?? self.duration
                guard !self.isPreviewing else { return }
                self.prepareAutomaticTransition()
                self.currentTime =
                    self.player?
                        .currentTime
                    ??
                    0
                let rate = self.player?.currentRate ?? 1
                if abs(rate - self.lastPublishedRate) > 0.001 {
                    self.lastPublishedRate = rate
                    if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                        info[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? rate : 0
                        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.currentTime
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                    }
                }
            }
    }


    // ========================================================
    // MARK: - Seeking
    // ========================================================

    func seek(
        to time: Double
    ) {
        stopTransitionPreview(resume: false)
        if let podcastPlayer {
            guard time.isFinite else { return }
            let target = max(0, duration > 0 ? min(time, duration) : time)
            currentTime = target
            podcastPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600))
            if let id = currentSong?.podcastEpisodeID { PodcastStore.shared.record(id, position: target) }
            updateNowPlaying()
            return
        }

        guard time.isFinite, let player, duration > 0 else { return }
        let target = min(duration, max(0, time))
        let listeningPosition = player.currentTime, wasPlaying = isPlaying
        Task { @MainActor in
            RecommendationManager.shared.playbackStateChanged(position: listeningPosition, playing: wasPlaying)
            RecommendationManager.shared.playbackSeeked(position: target)
        }
        transitionTask?.cancel(); transitionTask = nil; transitionTarget = nil
        player.currentTime = target
        currentTime = target
        localPlaybackState = localIntent.wantsPlayback ? .seeking : .paused


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

    @MainActor func audioPlayerDidFinishPlaying(
        _ player: EqualizedAudioPlayer,
        successfully flag: Bool
    ) {

        if previewPlayer === player {
            if let next = previewNextURL, flag {
                previewNextURL = nil
                do { try player.replace(with: next); player.play() }
                catch { stopTransitionPreview() }
            } else { stopTransitionPreview() }
            return
        }
        guard self.player === player else { return }
        RecommendationManager.shared.playbackWillChange(flag ? .completed : .failed, position: player.currentTime, playing: isPlaying)
        guard flag else {
            playbackErrorKey = "audio_playback_failed"
            localPlaybackState = .failed
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
    var homeUpcomingSongs: [Song] {
        guard let currentSong else { return [] }
        if repeatMode == .one { return [currentSong] }
        var upcoming = Array(queue.dropFirst(max(0, currentIndex + 1)).prefix(3))
        if repeatMode == .all { upcoming.append(contentsOf: queue.prefix(max(0, 3 - upcoming.count))) }
        else if !flowActive { upcoming.append(contentsOf: autoNextQueue.prefix(max(0, 3 - upcoming.count))) }
        return Array(upcoming.prefix(3))
    }
    private func recordListeningChange(_ reason: ListeningEndReason) {
        guard !isPreviewing else { return }
        let position = player?.currentTime ?? currentTime, playing = isPlaying
        Task { @MainActor in RecommendationManager.shared.playbackWillChange(reason, position: position, playing: playing) }
    }

    /// Starting Flow explicitly selects endless playback. Later repeat choices suspend refill;
    /// shuffle continues to reorder the one real queue. Activity is intentionally not restored.
    @MainActor func startEchoFlow(from seedSong: Song? = nil) {
        let library = MusicLibraryManager.shared
        let available = library.songs.filter { $0.podcastEpisodeID == nil && getURL(for: $0).map { FileManager.default.fileExists(atPath: $0.path) } == true }
        guard !available.isEmpty else { return }
        flowGeneration = UUID(); flowActive = true; flowSeed &+= 1; flowFailedIDs.removeAll()
        repeatMode = .off
        autoNextQueue.removeAll()
        allSongs = available
        if let seedSong, let song = available.first(where: { $0.id == seedSong.id }), let url = getURL(for: song) {
            let retained = queue.dropFirst(max(0, currentIndex + 1)).filter { $0.id != song.id && !flowSongIDs.contains($0.id) }
            play(song: song, url: url, queue: [song] + retained)
        } else if currentSong == nil || isPodcast || !available.contains(where: { $0.id == currentSong?.id }) {
            let snapshot = RecommendationManager.shared.selectionSnapshot(songs: available, favorites: library.favoriteSongIDs, seed: flowSeed)
            guard let first = snapshot.ranked(limit: 1, discover: flowMode == .discover).first, let url = getURL(for: first) else { stopEchoFlow(); return }
            play(song: first, url: url, queue: [first])
        } else if !isPlaying { setPlaybackDesired(true) }
        requestFlowRefill()
    }
    func stopEchoFlow() {
        flowActive = false; flowGeneration = UUID(); flowRefillTask?.cancel(); flowRefillTask = nil
        // Current playback and every queued item (including manual edits) remain intact.
    }
    private func requestFlowRefill() {
        guard flowActive else { return }
        Task { @MainActor [weak self] in self?.scheduleFlowRefill() }
    }
    @MainActor private func continueFlowAfterFailure() {
        guard flowActive, let currentSong, flowFailedIDs.insert(currentSong.id).inserted else { return }
        if queue.indices.contains(currentIndex + 1) { next(manuallyInitiated: false) }
        else { requestFlowRefill() }
    }
    @MainActor private func scheduleFlowRefill() {
        guard flowActive, flowRefillTask == nil, !isPodcast else { return }
        let upcoming = Array(queue.dropFirst(max(0, currentIndex + 1)))
        guard EchoFlowQueuePolicy.shouldRefill(active: flowActive, repeating: repeatMode != .off,
            upcoming: upcoming.count, automatic: upcoming.filter { flowSongIDs.contains($0.id) }.count) else { return }
        let generation = flowGeneration
        flowRefillTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.flowRefillTask = nil }
            let library = MusicLibraryManager.shared
            let songs = library.songs
            let favorites = library.favoriteSongIDs
            let seed = self.flowSeed; self.flowSeed &+= 1
            let current = self.currentSong, mode = self.flowMode
            let upcomingIDs = upcoming.map(\.id), recent = self.flowRecent, failed = self.flowFailedIDs
            let snapshot = RecommendationManager.shared.selectionSnapshot(songs: songs, favorites: favorites, seed: seed)
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let recommendations = await Task.detached(priority: .utility) {
                let local = snapshot.songs.filter { $0.podcastEpisodeID == nil && FileManager.default.fileExists(atPath: documents.appendingPathComponent($0.fileName).path) }
                var excluded = EchoFlowQueuePolicy.exclusions(current: current?.id, upcoming: upcomingIDs, recent: recent, libraryCount: local.count)
                if local.count == 1 && upcomingIDs.isEmpty, let current { excluded.remove(current.id) }
                excluded.formUnion(failed)
                let selection = SmartMusicSelection(songs: local, favorites: snapshot.favorites, learning: snapshot.learning, now: snapshot.now, seed: snapshot.seed)
                return (selection.ranked(limit: 8, discover: mode == .discover, excluding: excluded, anchor: current), local.count)
            }.value
            guard !Task.isCancelled, self.flowActive, self.flowGeneration == generation, self.repeatMode == .off else { return }
            let pending = self.queue.dropFirst(max(0, self.currentIndex + 1))
            let pendingIDs = Set(pending.map(\.id)), missing = max(0, 8 - pending.count)
            let extra = recommendations.0.filter { !pendingIDs.contains($0.id) && ($0.id != self.currentSong?.id || recommendations.1 == 1) && library.song(withID: $0.id) != nil }
            let chosen = Array(extra.prefix(missing))
            guard !chosen.isEmpty else {
                if self.localPlaybackState == .failed { self.stopEchoFlow() }
                return
            }
            self.flowSongIDs.formUnion(chosen.map(\.id))
            self.queue.append(contentsOf: chosen)
            self.originalQueue.append(contentsOf: chosen)
            // Keep past auto-selected entries bounded without discarding any manual entries.
            if self.currentIndex > 40 {
                let old = Array(self.queue.prefix(self.currentIndex - 20))
                let removed = old.filter { self.flowSongIDs.contains($0.id) }
                let kept = old.filter { !self.flowSongIDs.contains($0.id) }
                self.queue = kept + self.queue.dropFirst(old.count)
                self.currentIndex -= removed.count
                self.originalQueue = self.queue
            }
            if self.localPlaybackState == .failed, let first = chosen.first { self.playFromQueue(first) }
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
        stopTransitionPreview(resume: false)
        transitionTask?.cancel(); transitionTask = nil; transitionTarget = nil
        playbackRequest = UUID()
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
                            if self.podcastWantsPlayback && !self.isPreviewing { self.podcastPlayer?.playImmediately(atRate: self.podcastSpeed) }
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
