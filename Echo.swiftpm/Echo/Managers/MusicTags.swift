import AVFoundation

enum MusicTags {
    static func read(_ url: URL) async -> (genre: String?, year: Int?, readable: Bool) {
        let asset = AVURLAsset(url: url)
        guard let formats = try? await asset.load(.availableMetadataFormats) else { return (nil, nil, false) }
        var genre: String?, year: Int?
        for format in formats {
            guard let metadata = try? await asset.loadMetadata(for: format) else { continue }
            for item in metadata {
                let key = (item.identifier?.rawValue ?? String(describing: item.key)).lowercased()
                let isGenre = item.identifier == .id3MetadataContentType || item.identifier == .iTunesMetadataUserGenre || key.contains("genre") || key.contains("tcon") || key.contains("©gen")
                let isYear = item.identifier == .iTunesMetadataReleaseDate || key.contains("year") || key.contains("release") || key.contains("tdrc") || key.contains("tyer") || key.contains("tdor") || key.contains("tory") || key.contains("©day")
                guard isGenre || isYear else { continue }
                guard let value = try? await item.load(.stringValue), !value.isEmpty else { continue }
                if isGenre { genre = genre ?? value }
                if isYear {
                    if let match = value.range(of: "(?:18|19|20|21)[0-9]{2}", options: .regularExpression), let parsed = Int(value[match]) {
                        year = key.contains("original") || key.contains("tdor") || key.contains("tory") ? parsed : year ?? parsed
                    }
                }
            }
        }
        return (genre, year, true)
    }
}

extension MusicLibraryManager {
    @MainActor func enrichMissingTags() async {
        guard !isEnrichingTags else { return }
        isEnrichingTags = true
        defer { isEnrichingTags = false }
        var inspected = Set<UUID>()
        while !Task.isCancelled {
            // Also pick up imports that arrived while the previous batch was loading.
            let batch = Array(songs.lazy.filter { $0.tagsInspected != true && !inspected.contains($0.id) }.prefix(24))
            guard !batch.isEmpty else { break }
            var updates: [SongMetadataUpdate] = []
            for song in batch {
                guard !Task.isCancelled else { break }
                inspected.insert(song.id)
                guard let url = getURL(for: song) else { continue }
                let tags = await MusicTags.read(url)
                updates.append(SongMetadataUpdate(id: song.id, fileName: song.fileName,
                    genre: tags.genre, year: tags.year, readable: tags.readable))
            }
            var updated = songs
            if SongMetadataUpdates.apply(updates, to: &updated) { songs = updated }
            await Task.yield()
        }
    }
}
