import Foundation
import CryptoKit

struct PodcastShow: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
    let author: String
    let artworkURL: URL?
    let feedURL: URL

    func matches(_ query: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || title.localizedStandardContains(term) || author.localizedStandardContains(term)
    }
}

struct PodcastEpisode: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let show: PodcastShow
    let title: String
    let description: String
    let published: Date?
    let duration: Double?
    let audioURL: URL
    let artworkURL: URL?
    var transcripts: [PodcastTranscriptReference]? = nil

    static func identifier(showID: Int, guid: String?, audioURL: URL) -> String {
        let guid = guid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(showID):\(guid.isEmpty ? audioURL.absoluteString : guid)"
    }

    func matches(_ query: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || title.localizedStandardContains(term)
            || description.localizedStandardContains(term) || show.matches(term)
    }

    // Stable across refreshes, including GUIDs that are not UUIDs.
    var fileKey: String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var playbackID: UUID {
        let hex = fileKey
        let parts = [8, 4, 4, 4, 12]
        var offset = hex.startIndex
        let value = parts.map { length -> String in
            let end = hex.index(offset, offsetBy: length)
            defer { offset = end }
            return String(hex[offset..<end])
        }.joined(separator: "-")
        return UUID(uuidString: value)!
    }
}

struct PodcastTranscriptReference: Codable, Hashable, Sendable {
    let url: URL
    let type: String
    var language: String? = nil
}

struct PodcastListeningState: Codable {
    var position: Double = 0
    var played = false
    var updatedAt = Date()
}

struct PodcastFeed: Sendable {
    let description: String
    let episodes: [PodcastEpisode]
}

struct PodcastLibraryState: Codable {
    var shows: [Int: PodcastShow] = [:]
    var episodes: [String: PodcastEpisode] = [:]
    var savedEpisodeIDs: Set<String> = []
    var listening: [String: PodcastListeningState] = [:]
    var downloads: [String: String] = [:]
    var pendingDownloads: Set<String> = []
    var cachedFeeds: [Int: [PodcastEpisode]] = [:]
    var showDescriptions: [Int: String] = [:]
}
