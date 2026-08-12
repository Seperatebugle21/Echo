import Foundation
import SwiftUI
import AVFoundation

// MARK: - Import Conflict Models

struct ImportConflict: Identifiable {
    let id = UUID()
    let fileURL: URL
    let existingSong: Song
    let newTitle: String
}

enum ConflictAction {
    case skip
    case replace
}

// MARK: - Music Library Manager

@Observable
class MusicLibraryManager {
    
    static let shared = MusicLibraryManager()
    
    // MARK: - Song Editing
    
    var editingSong: Song?
    var showEditSheet = false
    var songToAddToPlaylist: Song?
    
    var favoriteSongIDs: [UUID] = []
    
    // MARK: - Import Conflict State
    
    var pendingConflicts: [ImportConflict] = []
    var currentConflict: ImportConflict?
    var applyToAllChoice: ConflictAction? = nil
    
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
    
    // MARK: - Lyrics & Metadata Updates
    
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
    
    func updateSong(
        _ song: Song,
        title: String,
        artist: String
    ) {
        if let index = songs.firstIndex(where: { $0.id == song.id }) {
            songs[index].title = title
            songs[index].artist = artist
        }
    }
    
    // MARK: - Folder Sync & Import
    
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
            
            // Reset "Pas toe op alles" voor een nieuwe synchronisatie
            applyToAllChoice = nil
            
            for url in fileURLs {
                let extensionName = url.pathExtension.lowercased()
                guard audioExtensions.contains(extensionName) else { continue }
                
                // Verwerk de mogelijke import/conflict
                processImport(from: url)
            }
        } catch {
            print("Fout bij synchroniseren van de map:", error)
        }
    }
    
    func importSong(from url: URL) {
        processImport(from: url)
    }
    
    private func processImport(from url: URL) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let fileName = url.lastPathComponent
        
        // 1. Controleer of het bestand al bestaat in de bibliotheek
        if let existingSong = songs.first(where: { $0.fileName == fileName }) {
            
            // Als de gebruiker eerder op "Pas toe op alles" heeft geklikt:
            if let choice = applyToAllChoice {
                let conflict = ImportConflict(fileURL: url, existingSong: existingSong, newTitle: fileName)
                resolveConflict(conflict, action: choice, applyToAll: true)
                return
            }
            
            // Voeg conflict toe aan de wachtrij
            let conflict = ImportConflict(fileURL: url, existingSong: existingSong, newTitle: fileName)
            if !pendingConflicts.contains(where: { $0.fileURL == url }) {
                pendingConflicts.append(conflict)
            }
            
            if currentConflict == nil {
                currentConflict = pendingConflicts.first
            }
            return
        }
        
        // 2. Geen dubbelganger? Importeer direct
        importNewSong(from: url)
    }
    
    // MARK: - Conflict Resolution Logic
    
    func resolveConflict(_ conflict: ImportConflict, action: ConflictAction, applyToAll: Bool = false) {
        if applyToAll {
            applyToAllChoice = action
        }
        
        switch action {
        case .skip:
            // Verwijder het dubbele bestand van de schijf als het in Documents staat
            let destination = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(conflict.fileURL.lastPathComponent)
            
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            print("Nummer overgeslagen en opgeruimd:", conflict.newTitle)
            
        case .replace:
            // Verwijder het oude nummer uit het geheugen
            deleteSong(conflict.existingSong)
            // Importeer het nieuwe bestand
            importNewSong(from: conflict.fileURL)
            print("Nummer vervangen:", conflict.newTitle)
        }
        
        // Werk de wachtrij bij
        pendingConflicts.removeAll { $0.id == conflict.id }
        currentConflict = pendingConflicts.first
    }
    
    private func importNewSong(from url: URL) {
        let fileName = url.lastPathComponent
        let destination = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        
        do {
            if url != destination && !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: url, to: destination)
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
            
            let song = Song(
                title: title,
                artist: artist,
                fileName: fileName,
                album: album,
                coverData: coverData
            )
            
            songs.append(song)
            print("Opgeslagen:", song.title)
            
        } catch {
            print("Import fout:", error.localizedDescription)
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
    
    // MARK: - Playlists & Cache
    
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
    
    // MARK: - File Management & Persistence
    
    func getURL(for song: Song) -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(song.fileName)
    }
    
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
