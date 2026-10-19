import Foundation

/// Wall-clock deadlines survive pauses and suspension; end-of-item targets one selection.
struct SleepTimerState: Equatable {
    private(set) var deadline: Date?
    private(set) var songID: UUID?
    var isActive: Bool { deadline != nil || songID != nil }

    mutating func start(minutes: Int, now: Date = Date()) {
        songID = nil
        deadline = now.addingTimeInterval(Double(min(720, max(1, minutes))) * 60)
    }
    mutating func endOfItem(_ id: UUID) { deadline = nil; songID = id }
    mutating func cancel() { deadline = nil; songID = nil }
    func isExpired(at now: Date = Date()) -> Bool { deadline.map { now >= $0 } ?? false }
    mutating func selectionChanged(to id: UUID?) {
        if let songID, songID != id { cancel() }
    }
    mutating func consumeCompletion(of id: UUID?) -> Bool {
        guard let songID, songID == id else { return false }
        cancel()
        return true
    }
}
