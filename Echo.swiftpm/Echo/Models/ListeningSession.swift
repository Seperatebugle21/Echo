import Foundation

/// Measures consumed audio, not seek position. One qualified play per playback session.
struct ListeningSession {
    let songID: UUID
    let duration: TimeInterval
    private(set) var listened: TimeInterval = 0
    private(set) var didCount = false
    private var previousPosition: TimeInterval = 0

    init(songID: UUID, duration: TimeInterval) {
        self.songID = songID
        self.duration = duration
    }

    mutating func rebase(to position: TimeInterval) {
        previousPosition = max(0, position)
    }

    mutating func sample(position: TimeInterval) -> Bool {
        guard position.isFinite, duration.isFinite, duration > 0 else { return false }
        let bounded = min(duration, max(0, position))
        listened += max(0, bounded - previousPosition)
        previousPosition = bounded
        guard !didCount, listened >= min(duration / 2, 240) else { return false }
        didCount = true
        return true
    }
}
