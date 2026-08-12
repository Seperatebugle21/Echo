import Foundation
import SwiftUI
import AVFoundation

// MARK: - Duplicate Resolution Option
enum DuplicateOption {
    case skip
    case replace
}

// MARK: - Pending Import Item
struct PendingImport: Identifiable {
    let id = UUID()
    let url: URL
    let destinationURL: URL
    let song: Song
}

@Observable
class MusicLibraryManager {
    
    static let shared = MusicLibraryManager()
    
    // MARK: - Song Editing
    
    var editingSong: Song?
    var showEditSheet = false
    var songToAddToPlaylist: Song?
    
    // MARK: - Duplicate Handling Queue
    var pendingImports: [PendingImport] = []
    var currentConflict: PendingImport?
    var showDuplicateAlert = false
    
    // Bewaart de keuze als de gebruiker kiest voor "Pas toe op alle volgende"
    private var applyToAllOption: DuplicateOption?
    
    var favoriteSongIDs: [UUID] = []
    
    // MARK: - Songs
    
    var songs: [Song] = [] {
        didSet {
            saveSongs()
        }
    }
    
    // MARK: - Playlists
    
    var playlists: [Playlist] = [] {
        didSet {
            savePlaylists()
        }
    }
    
    private let saveKey = "EchoSongs"
    private let playlistSaveKey = "EchoPlaylists"
    private let favoriteSaveKey = "EchoFavorites"
    
    
    init() {
        loadSongs()
        loadPlaylists()
        loadFavorites()
        syncDocumentsFolder()
    }
    
    // MARK: - Lyrics
    
    func removeAllLyrics() {
        for index in songs.indices {
            songs[index].lyrics = nil
            songs[index].syncedLyrics = nil
        }
        
        saveSongs()
        print("Alle opgeslagen lyrics verwijderd")
    }
    
    func updateLyrics(
        for song: Song,
        lyrics: String?,
        syncedLyrics: String?
    ) {
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else {
            print("Song niet gevonden voor lyrics:", song.title)
            return
        }
        
        songs[index].lyrics = lyrics
        songs[index].syncedLyrics = syncedLyrics
        
        saveSongs()
        print("Lyrics permanent opgeslagen voor:", songs[index].title)
    }
    
    // MARK: - Song Editing
    
    func updateSong(_ song: Song, title: String, artist: String) {
        if let index = songs.firstIndex(where: { $0.id == song.id }) {
            songs[index].title = title
            songs[index].artist = artist
        }
    }
    
    // MARK: - Import & Sync
    
    func syncDocumentsFolder() {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: documentsURL, 
                includingPropertiesForKeys: nil, 
                options: .skipsHiddenFiles
            )
            
            let audioExtensions = ["mp3", "m4a", "wav", "flac"]
            
            for url in fileURLs {
                let extensionName = url.pathExtension.lowercased()
                let fileName = url.lastPathComponent
                
                guard audioExtensions.contains(extensionName) else { continue }
                
                if !songs.contains(where: { $0.fileName == fileName }) {
                    importSong(from: url)
                }
            }
        } catch {
            print("Fout bij synchroniseren van de map:", error)
        }
    }
    
    /// Importeer meerdere nummers tegelijk (bijv. via een DocumentPicker)
    func importSongs(from urls: [URL]) {
        // Reset de "pas toe op alles" keuze bij een nieuwe batch
        applyToAllOption = nil
        
        for url in urls {
            processImportURL(url)
        }
        
        // Start het afhandelen van de wachtrij
        processNextPendingImport()
    }
    
    /// Enkel nummer importeren
    func importSong(from url: URL) {
        importSongs(from: [url])
    }
    
    private func processImportURL(_ url: URL) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let fileName = url.lastPathComponent
        let destination = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        
        // Tijdelijk kopiëren om metadata uit te lezen als het bestand er nog niet staat
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: destination.path) {
            try? fileManager.copyItem(at: url, to: destination)
        }
        
        let asset = AVAsset(url: destination)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Onbekende artiest"
        var album: String?
        var coverData: Data?
        
        for item in asset.commonMetadata {
            guard let key = item.commonKey else { continue }
            
            switch key {
            case .commonKeyTitle:
                if let value = item.stringValue { title = value }
            case .commonKeyArtist:
                if let value = item.stringValue { artist = value }
            case .commonKeyAlbumName:
                if let value = item.stringValue { album = value }
            case .commonKeyArtwork:
                if let data = item.dataValue { coverData = data }
            default:
                break
            }
        }
        
        let newSong = Song(
            title: title,
            artist: artist,
            fileName: fileName,
            album: album,
            coverData: coverData
        )
        
        let pending = PendingImport(url: url, destinationURL: destination, song: newSong)
        pendingImports.append(pending)
    }
    
    private func processNextPendingImport() {
        guard !pendingImports.isEmpty else {
            showDuplicateAlert = false
            currentConflict = nil
            applyToAllOption = nil
            return
        }
        
        let nextItem = pendingImports.removeFirst()
        
        // Controleer op dubbelingen (op bestandnaam óf Titel+Artiest)
        let isDuplicate = songs.contains(where: {
            $0.fileName == nextItem.song.fileName ||
            ($0.title.caseInsensitiveCompare(nextItem.song.title) == .orderedSame &&
             $0.artist.caseInsensitiveCompare(nextItem.song.artist) == .orderedSame)
        })
        
        if isDuplicate {
            // Als de gebruiker eerder koos voor "Pas toe op alle volgende"
            if let autoOption = applyToAllOption {
                resolveConflict(for: nextItem, option: autoOption)
                processNextPendingImport() // Ga direct door naar de volgende
            } else {
                // Toon de pop-up aan de gebruiker
                currentConflict = nextItem
                showDuplicateAlert = true
            }
        } else {
            // Geen dubbeling, direct toevoegen
            songs.append(nextItem.song)
            print("Opgeslagen:", nextItem.song.title)
            processNextPendingImport()
        }
    }
    
    /// Wordt aangeroepen vanuit de UI-alert
    func resolveCurrentConflict(with option: DuplicateOption, applyToAll: Bool) {
        guard let conflict = currentConflict else { return }
        
        if applyToAll {
            self.applyToAllOption = option
        }
        
        resolveConflict(for: conflict, option: option)
        
        // Verwerk de volgende in de wachtrij
        processNextPendingImport()
    }
    
    private func resolveConflict(for item: PendingImport, option: DuplicateOption) {
        switch option {
        case .skip:
            // Verwijder het nieuw gekopieerde bestand als het dubbel is
            try? FileManager.default.removeItem(at: item.destinationURL)
            print("Overgeslagen en nieuw bestand verwijderd:", item.song.title)
            
        case .replace:
            // Verwijder het oude nummer uit de lijst
            songs.removeAll {
                $0.fileName == item.song.fileName ||
                ($0.title.caseInsensitiveCompare(item.song.title) == .orderedSame &&
                 $0.artist.caseInsensitiveCompare(item.song.artist) == .orderedSame)
            }
            // Voeg het nieuwe nummer toe
            songs.append(item.song)
            print("Vervangen door nieuw nummer:", item.song.title)
        }
    }
    
    // MARK: - Delete
    
    func deleteSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        if let url = getURL(for: song) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    func deleteAllSongs() {
        for song in songs {
            if let url = getURL(for: song) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        songs.removeAll()
    }
    
    // MARK: - Favorites
    
    func isFavorite(_ song: Song) -> Bool {
        favoriteSongIDs.contains(song.id)
    }
    
    func toggleFavorite(_ song: Song) {
        if favoriteSongIDs.contains(song.id) {
            favoriteSongIDs.removeAll { $0 == song.id }
        } else {
            favoriteSongIDs.append(song.id)
        }
        saveFavorites()
    }
    
    var favoriteSongs: [Song] {
        favoriteSongIDs.compactMap { id in
            songs.first { $0.id == id }
        }
    }
    
    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favoriteSongIDs) {
            UserDefaults.standard.set(data, forKey: favoriteSaveKey)
        }
    }
    
    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: favoriteSaveKey) else { return }
        if let saved = try? JSONDecoder().decode([UUID].self, from: data) {
            favoriteSongIDs = saved
        }
    }
    
    // MARK: - Playlist
    
    func createPlaylist(name: String, imageData: Data? = nil) {
        playlists.append(
            Playlist(
                id: UUID(),
                name: name,
                songIDs: [],
                imageData: imageData
            )
        )
    }
    
    func clearCache() {
        let fileManager = FileManager.default
        if let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? fileManager.removeItem(at: cacheURL)
        }
        print("Cache gewist")
    }
    
    func markAsPlayed(_ song: Song) {
        if let index = songs.firstIndex(where: { $0.id == song.id }) {
            songs[index].lastPlayed = Date()
        }
    }
    
    func addSong(_ song: Song, to playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        if !playlists[index].songIDs.contains(song.id) {
            playlists[index].songIDs.append(song.id)
        }
    }
    
    // MARK: - File URL
    
    func getURL(for song: Song) -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(song.fileName)
    }
    
    // MARK: - Save/Load Songs
    
    private var songsFileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EchoSongs.json")
    }
    
    private func saveSongs() {
        do {
            let data = try JSONEncoder().encode(songs)
            try data.write(to: songsFileURL, options: [.atomic])
            print("Songs opgeslagen:", songs.count)
        } catch {
            print("Songs opslaan mislukt:", error.localizedDescription)
        }
    }
    
    private func loadSongs() {
        guard FileManager.default.fileExists(atPath: songsFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: songsFileURL)
            songs = try JSONDecoder().decode([Song].self, from: data)
            print("Songs geladen:", songs.count)
        } catch {
            print("Songs laden mislukt:", error.localizedDescription)
        }
    }
    
    // MARK: - Save/Load Playlists
    
    private func savePlaylists() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: playlistSaveKey)
        }
    }
    
    private func loadPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: playlistSaveKey) else { return }
        if let saved = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = saved
        }
    }
    
    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
    }
}
