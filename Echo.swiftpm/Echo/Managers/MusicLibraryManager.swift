import Foundation
import SwiftUI
import AVFoundation

@Observable
class MusicLibraryManager {
    
    static let shared = MusicLibraryManager()
    
    // MARK: - Song Editing
    
    var editingSong: Song?
    var showEditSheet = false
    var songToAddToPlaylist: Song?
    
    var showDuplicateAlert = false
    var duplicateSongName = ""
    
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
        
        guard let index = songs.firstIndex(
            where: {
                $0.id == song.id
            }
        ) else {
            print("Song niet gevonden voor lyrics:", song.title)
            return
        }
        
        songs[index].lyrics = lyrics
        songs[index].syncedLyrics = syncedLyrics
        
        // Meteen permanent opslaan
        saveSongs()
        
        print(
            "Lyrics permanent opgeslagen voor:",
            songs[index].title
        )
    }
    
    
    
    // MARK: - Song Editing
    
    func updateSong(
        _ song: Song,
        title: String,
        artist: String
    ) {
        
        if let index = songs.firstIndex(where: {
            $0.id == song.id
        }) {
            
            songs[index].title = title
            songs[index].artist = artist
        }
    }
    
    
    // MARK: - Import
    
    // MARK: - Import

func syncDocumentsFolder() {
    let fileManager = FileManager.default
    guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    
    do {
        // Haal alle bestanden uit de app-map op
        let fileURLs = try fileManager.contentsOfDirectory(
            at: documentsURL, 
            includingPropertiesForKeys: nil, 
            options: .skipsHiddenFiles
        )
        
        let audioExtensions = ["mp3", "m4a", "wav", "flac"]
        
        for url in fileURLs {
            let extensionName = url.pathExtension.lowercased()
            let fileName = url.lastPathComponent
            
            // Sla het JSON-bestand en niet-audiobestanden over
            guard audioExtensions.contains(extensionName) else { continue }
            
            // Als het nummer nog NIET in de bibliotheek staat, importeer het
            if !songs.contains(where: { $0.fileName == fileName }) {
                importSong(from: url)
            }
        }
    } catch {
        print("Fout bij synchroniseren van de map:", error)
    }
}

    
    func importSong(from url: URL) {
        
        let accessGranted = url.startAccessingSecurityScopedResource()
        
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let fileName = url.lastPathComponent
        
        if songs.contains(where: { $0.fileName == fileName }) {
            
            duplicateSongName = fileName
            showDuplicateAlert = true
            print("Nummer bestaat al.")
            return
        }
        
        
        
        let destination = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        
        do {
            
            if !FileManager.default.fileExists(atPath: destination.path) {
                
                try FileManager.default.copyItem(
                    at: url,
                    to: destination
                )
            }
            
            let asset = AVAsset(url: destination)
            
            var title = url.deletingPathExtension().lastPathComponent
            var artist = "Onbekende artiest"
            var album: String?
            var coverData: Data?
            
            for item in asset.commonMetadata {
                
                guard let key = item.commonKey else {
                    continue
                }
                
                switch key {
                    
                case .commonKeyTitle:
                    
                    if let value = item.stringValue {
                        title = value
                    }
                    
                case .commonKeyArtist:
                    
                    if let value = item.stringValue {
                        artist = value
                    }
                    
                case .commonKeyAlbumName:
                    
                    if let value = item.stringValue {
                        album = value
                    }
                    
                case .commonKeyArtwork:
                    
                    if let data = item.dataValue {
                        coverData = data
                    }
                    
                default:
                    break
                }
            }
            
            if songs.contains(where: {
                $0.title.caseInsensitiveCompare(title) == .orderedSame &&
                $0.artist.caseInsensitiveCompare(artist) == .orderedSame
            }) {
                duplicateSongName = title
                showDuplicateAlert = true
                print("Dit nummer staat al in de bibliotheek.")
                return
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
        
        songs.removeAll {
            $0.id == song.id
        }
        
        if let url = getURL(for: song) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    
    func deleteAllSongs() {
        
        // Verwijder alle bestanden uit de opslag
        for song in songs {
            
            if let url = getURL(for: song) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        
        
        // Verwijder ook de bibliotheek
        songs.removeAll()
    }
    
    
    
    func isFavorite(_ song: Song) -> Bool {
        favoriteSongIDs.contains(song.id)
    }
    
    func toggleFavorite(_ song: Song) {
        
        if favoriteSongIDs.contains(song.id) {
            
            favoriteSongIDs.removeAll {
                $0 == song.id
            }
            
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
    
    
    // MARK: - Save Favorites
    
    private func saveFavorites() {
        
        if let data = try? JSONEncoder().encode(favoriteSongIDs) {
            
            UserDefaults.standard.set(
                data,
                forKey: favoriteSaveKey
            )
        }
    }
    
    
    private func loadFavorites() {
        
        guard let data = UserDefaults.standard.data(
            forKey: favoriteSaveKey
        ) else {
            return
        }
        
        
        if let saved = try? JSONDecoder().decode(
            [UUID].self,
            from: data
        ) {
            
            favoriteSongIDs = saved
        }
    }
    
    
    // MARK: - Playlist
    
    func createPlaylist(
        name: String,
        imageData: Data? = nil
    ) {
        
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
        
        if let cacheURL = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first {
            
            try? fileManager.removeItem(
                at: cacheURL
            )
        }
        
        
        print("Cache gewist")
    }
    
    func markAsPlayed(_ song: Song) {
        
        if let index = songs.firstIndex(where: {
            $0.id == song.id
        }) {
            
            songs[index].lastPlayed = Date()
        }
    }
    
    
    
    func addSong(
        _ song: Song,
        to playlist: Playlist
    ) {
        
        guard let index = playlists.firstIndex(where: {
            $0.id == playlist.id
        }) else { return }
        
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
    
    
    // MARK: - Save Songs
    
    
    
    
    private var songsFileURL: URL {
        FileManager.default
            .urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]
            .appendingPathComponent("EchoSongs.json")
    }
    
    
    private func saveSongs() {
        
        do {
            
            let data = try JSONEncoder().encode(songs)
            
            try data.write(
                to: songsFileURL,
                options: [.atomic]
            )
            
            print("Songs opgeslagen:", songs.count)
            
        } catch {
            
            print(
                "Songs opslaan mislukt:",
                error.localizedDescription
            )
        }
    }
    
    
    private func loadSongs() {
        
        guard FileManager.default.fileExists(
            atPath: songsFileURL.path
        ) else {
            return
        }
        
        do {
            
            let data = try Data(
                contentsOf: songsFileURL
            )
            
            songs = try JSONDecoder().decode(
                [Song].self,
                from: data
            )
            
            print(
                "Songs geladen:",
                songs.count
            )
            
        } catch {
            
            print(
                "Songs laden mislukt:",
                error.localizedDescription
            )
        }
    }
    
    
    // MARK: - Save Playlists
    
    private func savePlaylists() {
        
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(
                data,
                forKey: playlistSaveKey
            )
        }
    }
    
    
    private func loadPlaylists() {
        
        guard let data = UserDefaults.standard.data(
            forKey: playlistSaveKey
        ) else { return }
        
        if let saved = try? JSONDecoder().decode(
            [Playlist].self,
            from: data
        ) {
            playlists = saved
        }
    }
    
    
    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll {
            $0.id == playlist.id
        }
    }
    
}
