import Foundation
import AVFoundation
import MediaPlayer
import AVFAudio

enum RepeatMode: Equatable {
    case off
    case all
    case one
}



@Observable
class AudioPlayerManager: NSObject, AVAudioPlayerDelegate {
    
    override init() {
        super.init()
        setupRemoteCommands()
    }
    
    static let shared = AudioPlayerManager()
    
    var lastPlaybackDirection: PlaybackDirection = .fade
    
    enum PlaybackDirection {
        case next
        case previous
        case fade
    }
    
    private let lyricsManager = LyricsManager.shared
    
    
    private var player: AVAudioPlayer?
    private var timer: Timer?
    
    private var preloadedSong: Song?
    private var preloadedPlayer: AVAudioPlayer?
    
    var currentLyrics: String?
    var currentSyncedLyrics: String?
    
    var lyricsNeedsInternet = false
    
    var isPlaying = false
    var currentSong: Song?
    
    var currentTime: Double = 0
    var duration: Double = 0
    
    
    var queue: [Song] = []
    var currentIndex: Int = 0
    var history: [Song] = []
    
    
    var autoNextQueue: [Song] = []
    var autoNextIndex: Int = 0
    
    
    var allSongs: [Song] = []
    
    
    
    var shuffleEnabled = false
    var repeatMode: RepeatMode = .off
    
    
    
    
    
    
    func updateNowPlaying() {
        
        guard let song = currentSong else {
            return
        }
        
        var info: [String: Any] = [:]
        
        info[MPMediaItemPropertyTitle] = song.title
        info[MPMediaItemPropertyArtist] = song.artist
        
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        
        info[MPNowPlayingInfoPropertyPlaybackRate] =
        isPlaying ? 1 : 0
        
        
        if let data = song.coverData,
           let image = UIImage(data: data) {
            
            let artwork = MPMediaItemArtwork(
                boundsSize: image.size
            ) { _ in
                image
            }
            
            info[MPMediaItemPropertyArtwork] = artwork
        }
        
        
        MPNowPlayingInfoCenter.default()
            .nowPlayingInfo = info
    }
    
    
    
    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            try session.setCategory(
                .playback,
                mode: .default
            )
            
            try session.setActive(true)
            
        } catch {
            print("Audio session fout:", error)
        }
    }
    
    
    func setupRemoteCommands() {
        
        let commandCenter = MPRemoteCommandCenter.shared()
        
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            
            self?.togglePlayPause()
            
            return .success
        }
        
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            
            self?.togglePlayPause()
            
            return .success
        }
        
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            
            self?.next()
            
            return .success
        }
        
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            
            self?.previous()
            
            return .success
        }
    }
    
    
    
    func play(
        song: Song,
        url: URL,
        queue: [Song] = []
    ) {
        do {
            let session = AVAudioSession.sharedInstance()
            
            try session.setCategory(
                .playback,
                mode: .default
            )
            
            try session.setActive(true)
            
        } catch {
            print("Audio session fout:", error)
        }
        
        setupAudioSession()
        
        if !queue.isEmpty {
            self.queue = queue
        }
        
        
        if let index = self.queue.firstIndex(where: {
            $0.id == song.id
        }) {
            currentIndex = index
        }
        
        
        do {
            
            timer?.invalidate()
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            
            player?.prepareToPlay()
            
            
            duration = player?.duration ?? 0
            currentTime = 0
            
            if let oldSong = currentSong,
               oldSong.id != song.id {
                history.append(oldSong)
            }
            
            currentSong = song
            
            currentLyrics = nil
            currentSyncedLyrics = nil
            
            loadLyrics(for: song)
            
            player?.play()
            UIApplication.shared.beginReceivingRemoteControlEvents()
            isPlaying = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.updateNowPlaying()
                print("Now Playing gestuurd:", song.title)
            }
            
            startTimer()
            
            
            fillQueue(from: queue)
            
            
            
        } catch {
            
            print(
                "Kan nummer niet afspelen:",
                error.localizedDescription
            )
        }
    }
    
    
    
    
    
    
    
    func loadLyrics(for song: Song) {
        
        // Eerst kijken of de song zelf al lyrics heeft opgeslagen
        if let savedSong = MusicLibraryManager.shared.songs.first(where: {
            $0.id == song.id
        }) {
            
            if savedSong.lyrics != nil || savedSong.syncedLyrics != nil {
                
                currentLyrics = savedSong.lyrics
                currentSyncedLyrics = savedSong.syncedLyrics
                lyricsNeedsInternet = false
                
                print("Opgeslagen lyrics geladen voor:", song.title)
                return
            }
        }
        
        
        // Geen opgeslagen lyrics → internet proberen
        lyricsNeedsInternet = false
        
        Task {
            
            let result = await lyricsManager.fetchLyrics(
                for: song,
                duration: duration
            )
            
            await MainActor.run {
                
                if let result {
                    
                    self.currentLyrics = result.plainLyrics
                    self.currentSyncedLyrics = result.syncedLyrics
                    self.lyricsNeedsInternet = false
                    
                    // Permanent opslaan
                    MusicLibraryManager.shared.updateLyrics(
                        for: song,
                        lyrics: result.plainLyrics,
                        syncedLyrics: result.syncedLyrics
                    )
                    
                    print("Nieuwe lyrics opgeslagen voor:", song.title)
                    
                } else {
                    
                    // Geen resultaat van API
                    self.currentLyrics = nil
                    self.currentSyncedLyrics = nil
                    
                    // We kunnen hier nog bepalen of er internet is
                    // via je LyricsManager.
                    self.lyricsNeedsInternet = true
                    
                    print("Geen opgeslagen lyrics en ophalen mislukt voor:", song.title)
                }
            }
        }
    }
    
    
    
    
    func next() {
        
        lastPlaybackDirection = .next
        
        // Normale queue
        if queue.count > currentIndex + 1 {
            
            currentIndex += 1
            
            let song = queue[currentIndex]
            
            // Gebruik de vooraf geladen speler
            if preloadedSong?.id == song.id,
               let preparedPlayer = preloadedPlayer {
                
                player?.stop()
                
                player = preparedPlayer
                player?.delegate = self
                
                currentSong = song
                
                currentTime = 0
                duration = player?.duration ?? 0
                
                preloadedSong = nil
                preloadedPlayer = nil
                
                player?.play()
                
                isPlaying = true
                
                startTimer()
                updateNowPlaying()
                
                // Meteen het volgende nummer klaarzetten
                
                
                return
            }
            
            // Fallback als preload nog niet klaar was
            playSongAtIndex()
            
            return
        }
        
        
        // Auto-next queue
        if let nextSong = autoNextQueue.first {
            
            autoNextQueue.removeFirst()
            
            if let url = getURL(for: nextSong) {
                
                play(
                    song: nextSong,
                    url: url,
                    queue: []
                )
                
                fillAutoNext(
                    from: allSongs
                )
            }
            
            return
        }
        
        
        isPlaying = false
    }
    
    
    
    
    func previous() {
        
        lastPlaybackDirection = .previous
        
        // Als je al even aan het luisteren bent:
        // gewoon huidige nummer opnieuw starten
        if currentTime > 3 {
            
            player?.currentTime = 0
            currentTime = 0
            
            return
        }
        
        
        // Anders echt naar vorig nummer
        if let previousSong = history.popLast() {
            
            playPreviousSong(previousSong)
            
        } else {
            
            player?.currentTime = 0
            currentTime = 0
        }
    }
    
    
    func playNext(_ song: Song) {
        
        guard let currentIndex = queue.firstIndex(where: {
            $0.id == currentSong?.id
        }) else {
            return
        }
        
        // voorkomt dubbele nummers direct na elkaar
        queue.removeAll {
            $0.id == song.id
        }
        
        queue.insert(song, at: currentIndex + 1)
    }
    
    
    
    private func playSongAtIndex() {
        
        let song = queue[currentIndex]
        
        if let url = getURL(for: song) {
            
            play(
                song: song,
                url: url,
                queue: queue
            )
        }
    }
    
    
    func fillQueue(
        from songs: [Song]
    ) {
        
        guard let currentSong else {
            return
        }
        
        let upcoming = queue.drop(
            while: { $0.id != currentSong.id }
        )
            .dropFirst()
        
        let missing = 30 - upcoming.count
        
        if missing > 0 {
            
            let availableSongs = songs.filter {
                $0.id != currentSong.id &&
                !queue.contains(where: {
                    $0.id == $0.id
                })
            }
            
            let extra = availableSongs.shuffled()
                .prefix(missing)
            
            queue.append(contentsOf: extra)
        }
    }
    
    
    
    func playPreviousSong(_ song: Song) {
        
        guard let url = getURL(for: song) else {
            return
        }
        
        player?.stop()
        
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        
        duration = player?.duration ?? 0
        currentTime = 0
        
        currentSong = song
        
        // Oude lyrics wissen
        currentLyrics = nil
        currentSyncedLyrics = nil
        
        // Lyrics van het vorige nummer laden
        loadLyrics(for: song)
        
        player?.play()
        isPlaying = true
        
        startTimer()
        
        updateNowPlaying()
    }
    
    
    
    
    func addToQueue(_ song: Song) {
        
        if !queue.contains(where: {
            $0.id == song.id
        }) {
            queue.append(song)
        }
    }
    
    
    
    
    func playFromQueue(_ song: Song) {
        
        guard let index = queue.firstIndex(where: {
            $0.id == song.id
        }) else {
            return
        }
        
        currentIndex = index
        playSongAtIndex()
    }
    
    
    
    
    func moveQueue(
        from source: IndexSet,
        to destination: Int
    ) {
        
        queue.move(
            fromOffsets: source,
            toOffset: destination
        )
    }
    
    
    
    func fillAutoNext(from songs: [Song]) {
        
        while autoNextQueue.count < 10 {
            
            let availableSongs = songs.filter { song in
                
                song.id != currentSong?.id &&
                !queue.contains(where: {
                    $0.id == song.id
                }) &&
                !autoNextQueue.contains(where: {
                    $0.id == song.id
                })
            }
            
            guard let randomSong = availableSongs.randomElement()
            else {
                return
            }
            
            autoNextQueue.append(randomSong)
        }
    }
    
    
    
    
    func removeFromQueue(
        at offsets: IndexSet
    ) {
        
        queue.remove(
            atOffsets: offsets
        )
    }
    
    
    
    
    func togglePlayPause() {
        
        guard let player else { return }
        
        
        if player.isPlaying {
            
            player.pause()
            isPlaying = false
            updateNowPlaying()
            
        } else {
            
            player.play()
            isPlaying = true
            startTimer()
            updateNowPlaying()
        }
    }
    
    
    
    
    func toggleShuffle() {
        
        shuffleEnabled.toggle()
    }
    
    
    
    
    func toggleRepeat() {
        
        switch repeatMode {
            
        case .off:
            repeatMode = .all
            
        case .all:
            repeatMode = .one
            
        case .one:
            repeatMode = .off
        }
    }
    
    
    
    
    private func startTimer() {
        
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.05,
            repeats: true
        ) { _ in
            
            self.currentTime =
            self.player?.currentTime ?? 0
            self.updateNowPlaying()
        }
    }
    
    
    
    
    func seek(
        to time: Double
    ) {
        
        player?.currentTime = time
        currentTime = time
    }
    
    
    
    
    func pauseForSeeking() {
        
        player?.pause()
    }
    
    
    
    
    func resumeAfterSeeking() {
        
        player?.play()
    }
    
    
    
    
    func getURL(
        for song: Song
    ) -> URL? {
        
        FileManager.default
            .urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]
            .appendingPathComponent(
                song.fileName
            )
    }
    
    
    
    
    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        
        
        if repeatMode == .one {
            
            if let song = currentSong,
               let url = getURL(for: song) {
                
                play(
                    song: song,
                    url: url,
                    queue: queue
                )
            }
            
        } else {
            
            next()
        }
    }
}
