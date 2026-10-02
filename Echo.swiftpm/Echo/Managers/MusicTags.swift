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
                guard let value = try? await item.load(.stringValue), !value.isEmpty else { continue }
                if item.identifier == .id3MetadataContentType || item.identifier == .iTunesMetadataUserGenre || key.contains("genre") || key.contains("tcon") || key.contains("©gen") { genre = genre ?? value }
                if item.identifier == .iTunesMetadataReleaseDate || key.contains("year") || key.contains("release") || key.contains("tdrc") || key.contains("tyer") || key.contains("tdor") || key.contains("tory") || key.contains("©day") {
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
        let snapshot = songs.filter { $0.tagsInspected != true }
        for song in snapshot {
            guard !Task.isCancelled, let url = getURL(for: song) else { continue }
            let tags = await MusicTags.read(url)
            guard let index = songs.firstIndex(where: { $0.id == song.id }) else { continue }
            if songs[index].genre == nil, let genre = tags.genre { songs[index].genre = genre }
            if songs[index].releaseYear == nil, let year = tags.year { songs[index].releaseYear = year }
            if tags.readable { songs[index].tagsInspected = true }
        }
    }
}
