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
    
    // MARK: - Duplicate Handling Properties
    var showDuplicateAlert = false
    var duplicateSongName = ""
    var pendingDuplicateURL: URL?
    var applyToAllDuplicates = false
    var lastDuplicateChoice: DuplicateChoice?
    
    enum DuplicateChoice {
        case skip
        case replace
    }
    
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
        removeMissingSongReferences()
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
                    
                    // Als er een dubbel nummer is gevonden en de gebruiker moet nog kiezen,
                    // onderbreken we de synchronisatie tijdelijk tot de gebruiker kiest.
                    if showDuplicateAlert {
                        break
                    }
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
        let isInternalFile = url.deletingLastPathComponent().path == FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        
        // Controleer of het nummer al bestaat in de bibliotheek
        if songs.contains(where: { $0.fileName == fileName }) {
            
            // Als "Pas toe op alle" eerder gekozen is, voer die keuze direct uit
            if applyToAllDuplicates, let choice = lastDuplicateChoice {
                resolveDuplicate(choice: choice, incomingURL: url, fileName: fileName, isInternal: isInternalFile)
                return
            }
            
            // Anders tonen we de alert en bewaren we de data
            duplicateSongName = fileName
            pendingDuplicateURL = url
            showDuplicateAlert = true
            print("Nummer bestaat al. Wachten op gebruikerskeuze.")
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
            
            // Dubbele titel/artiest check
            if songs.contains(where: {
                $0.title.caseInsensitiveCompare(title) == .orderedSame &&
                $0.artist.caseInsensitiveCompare(artist) == .orderedSame
            }) {
                if applyToAllDuplicates, let choice = lastDuplicateChoice {
                    resolveDuplicate(choice: choice, incomingURL: destination, fileName: fileName, isInternal: true)
                    return
                }
                
                duplicateSongName = title
                pendingDuplicateURL = destination
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
    
    // MARK: - Dubbelen Afhandelen
    
    func resolveDuplicate(choice: DuplicateChoice, applyToAll: Bool = false) {
        guard let url = pendingDuplicateURL else { return }
        
        let fileName = url.lastPathComponent
        let isInternal = url.deletingLastPathComponent().path == FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        
        if applyToAll {
            self.applyToAllDuplicates = true
            self.lastDuplicateChoice = choice
        }
        
        resolveDuplicate(choice: choice, incomingURL: url, fileName: fileName, isInternal: isInternal)
        
        self.pendingDuplicateURL = nil
        self.showDuplicateAlert = false
        
        // Synchronisatie hervatten voor eventuele overige bestanden
        syncDocumentsFolder()
    }
    
    private func resolveDuplicate(choice: DuplicateChoice, incomingURL: URL, fileName: String, isInternal: Bool) {
        let fileManager = FileManager.default
        let destination = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        
        switch choice {
        case .skip:
            // Bij overslaan verwijderen we het nieuwe/geïmporteerde bestand als het al in Documents staat
            if isInternal || incomingURL != destination {
                try? fileManager.removeItem(at: incomingURL)
            }
            print("Dubbel nummer overgeslagen en opgeruimd:", fileName)
            
        case .replace:
            // Verwijder het oude nummer uit de `songs` lijst
            if let existingSong = songs.first(where: { $0.fileName == fileName || $0.title.caseInsensitiveCompare(duplicateSongName) == .orderedSame }) {
                deleteSong(existingSong)
            }
            
            // Vervang het bestand indien nodig en importeer het opnieuw
            do {
                if incomingURL != destination {
                    if fileManager.fileExists(atPath: destination.path) {
                        try fileManager.removeItem(at: destination)
                    }
                    try fileManager.copyItem(at: incomingURL, to: destination)
                }
                
                // Her-importeer als nieuw nummer
                let asset = AVAsset(url: destination)
                var title = destination.deletingPathExtension().lastPathComponent
                var artist = "Onbekende artiest"
                var album: String?
                var coverData: Data?
                
                for item in asset.commonMetadata {
                    guard let key = item.commonKey else { continue }
                    switch key {
                    case .commonKeyTitle: if let value = item.stringValue { title = value }
                    case .commonKeyArtist: if let value = item.stringValue { artist = value }
                    case .commonKeyAlbumName: if let value = item.stringValue { album = value }
                    case .commonKeyArtwork: if let data = item.dataValue { coverData = data }
                    default: break
                    }
                }
                
                let newSong = Song(title: title, artist: artist, fileName: fileName, album: album, coverData: coverData)
                songs.append(newSong)
                print("Nummer succesvol vervangen:", title)
                
            } catch {
                print("Fout bij vervangen van nummer:", error.localizedDescription)
            }
        }
    }
    
    
    // MARK: - Delete
    
    func deleteSong(_ song: Song) {
        playlists = playlists.map { playlist in
            var updatedPlaylist = playlist
            updatedPlaylist.songIDs.removeAll { $0 == song.id }
            return updatedPlaylist
        }

        favoriteSongIDs.removeAll { $0 == song.id }
        saveFavorites()

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
        
        
        playlists = playlists.map { playlist in
            var updatedPlaylist = playlist
            updatedPlaylist.songIDs.removeAll()
            return updatedPlaylist
        }

        favoriteSongIDs.removeAll()
        saveFavorites()

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
    
    @discardableResult
    func createPlaylist(
        name: String,
        imageData: Data? = nil
    ) -> Playlist {

        let playlist =
            Playlist(
                id: UUID(),
                name: name,
                songIDs: [],
                imageData: imageData
            )
        
        playlists.append(
            playlist
        )

        return playlist
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

    func songs(in playlist: Playlist) -> [Song] {
        let songsByID = Dictionary(
            uniqueKeysWithValues: songs.map { ($0.id, $0) }
        )

        return playlist.songIDs.compactMap { songsByID[$0] }
    }

    func songCount(in playlist: Playlist) -> Int {
        let availableSongIDs = Set(songs.map(\.id))
        return playlist.songIDs.filter(availableSongIDs.contains).count
    }

    private func removeMissingSongReferences() {
        let availableSongIDs = Set(songs.map(\.id))

        playlists = playlists.map { playlist in
            var updatedPlaylist = playlist
            updatedPlaylist.songIDs.removeAll {
                !availableSongIDs.contains($0)
            }
            return updatedPlaylist
        }

        favoriteSongIDs.removeAll {
            !availableSongIDs.contains($0)
        }
        saveFavorites()
    }

    func addSong(
        _ song: Song,
        toPlaylistID playlistID: UUID,
        at position: Int
    ) {

        guard let playlistIndex =
            playlists.firstIndex(
                where: {
                    $0.id == playlistID
                }
            ),
              !playlists[playlistIndex]
                .songIDs
                .contains(song.id)
        else {
            return
        }

        let insertionIndex =
            min(
                max(position, 0),
                playlists[playlistIndex]
                    .songIDs.count
            )

        playlists[playlistIndex]
            .songIDs
            .insert(
                song.id,
                at: insertionIndex
            )
    }

    func songMatching(
        title: String,
        artist: String
    ) -> Song? {

        let normalizedTitle =
            normalizedLibraryValue(
                title
            )

        let normalizedArtist =
            normalizedLibraryValue(
                artist
            )

        return songs.first { song in

            normalizedLibraryValue(
                song.title
            ) == normalizedTitle
            &&
            normalizedLibraryValue(
                song.artist
            ) == normalizedArtist
        }
    }

    private func normalizedLibraryValue(
        _ value: String
    ) -> String {

        value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive
                ],
                locale: .current
            )
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .lowercased()
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
