import ActivityKit
import Foundation

/// Download-queue Live Activity, shared by the app (which starts and updates it) and the
/// widget extension (which draws it on the Lock Screen and in the Dynamic Island).
struct EchoDownloadActivityAttributes: ActivityAttributes {
    /// Echo's in-app language (an `.lproj` name), so the Lock Screen matches the app.
    var language: String

    struct ContentState: Codable, Hashable {
        /// Songs that are finished, successfully or not.
        var done: Int
        var total: Int
        var failed: Int
        var currentTitle: String?
        var currentArtist: String?
        /// Progress of the whole run, 0...1.
        var progress: Double
        /// Estimated end; the Lock Screen counts down to it without further updates.
        var finishesAt: Date?
        var finished: Bool

        var added: Int { max(0, done - failed) }

        /// True when the Lock Screen would look noticeably different, so an update is worth sending.
        func differsVisibly(from other: ContentState) -> Bool {
            if done != other.done || total != other.total || failed != other.failed || finished != other.finished
                || currentTitle != other.currentTitle || abs(progress - other.progress) >= 0.01 { return true }
            switch (finishesAt, other.finishesAt) {
            case (nil, nil): return false
            case let (lhs?, rhs?): return abs(lhs.timeIntervalSince(rhs)) >= 20
            default: return true
            }
        }
    }
}
