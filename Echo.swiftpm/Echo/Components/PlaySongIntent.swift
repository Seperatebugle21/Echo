import AppIntents


struct PlaySongError: Error, LocalizedError {
    
    var errorDescription: String? {
        "Ik kan dat nummer niet vinden."
    }
}


struct PlaySongIntent: AppIntent {
    
    static var title: LocalizedStringResource = "Speel nummer"
    
    @Parameter(title: "Nummer")
    var songName: String
    
    
    func perform() async throws -> some IntentResult {
        
        let library = MusicLibraryManager.shared
        let audioPlayer = AudioPlayerManager.shared
        
        
        guard let song = library.songs.first(where: {
            $0.title.localizedCaseInsensitiveContains(songName) ||
            $0.artist.localizedCaseInsensitiveContains(songName)
        }) else {
            
            throw PlaySongError()
        }
        
        
        if let url = library.getURL(for: song) {
            
            await MainActor.run {
                
                audioPlayer.play(
                    song: song,
                    url: url,
                    queue: library.songs
                )
            }
        }
        
        
        return .result()
    }
}
