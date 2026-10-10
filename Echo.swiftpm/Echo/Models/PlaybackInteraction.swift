import Foundation

/// A finger drag changes preview state only; finishing consumes the seek once.
struct PlaybackScrubState {
    private(set) var songID: UUID?
    private(set) var position = 0.0
    private(set) var duration = 0.0
    var isActive: Bool { songID != nil }

    mutating func begin(songID: UUID?, position: Double, duration: Double) {
        guard let songID, duration.isFinite, duration > 0 else { return }
        self.songID = songID
        self.duration = duration
        update(position)
    }
    mutating func update(_ position: Double) {
        guard isActive, position.isFinite else { return }
        self.position = max(0, min(duration, position))
    }
    mutating func finish(songID: UUID?) -> Double? {
        defer { cancel() }
        guard isActive, self.songID == songID else { return nil }
        return position
    }
    mutating func cancel() { songID = nil }
}

/// Transport commands use the latest intention, not an asynchronously read engine flag.
struct PlaybackIntent {
    private(set) var wantsPlayback = false
    private(set) var revision: UInt64 = 0
    @discardableResult mutating func set(_ playing: Bool) -> UInt64 {
        revision &+= 1
        wantsPlayback = playing
        return revision
    }
    mutating func reconcile(_ playing: Bool, revision: UInt64) {
        guard revision == self.revision else { return }
        wantsPlayback = playing
    }
}

enum PlaybackRecommendations {
    /// Admission consumes the recommendation; rendering confirms playback later.
    @discardableResult
    static func consume(_ songID: UUID, from recommendations: inout [Song]) -> Bool {
        let count = recommendations.count
        recommendations.removeAll { $0.id == songID }
        return recommendations.count != count
    }

    static func refill(_ recommendations: inout [Song], from songs: [Song], queue: [Song],
                       currentSongID: UUID?, limit: Int = 10,
                       order: ([Song]) -> [Song] = { $0.shuffled() }) {
        var excluded = Set(queue.map(\.id) + recommendations.map(\.id))
        if let currentSongID { excluded.insert(currentSongID) }
        let candidates = songs.filter { excluded.insert($0.id).inserted }
        recommendations.append(contentsOf: order(candidates).prefix(max(0, limit - recommendations.count)))
    }
}
