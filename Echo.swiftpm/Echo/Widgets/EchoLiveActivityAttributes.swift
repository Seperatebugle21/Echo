import ActivityKit
import Foundation

/// Now-playing Live Activity, shared by the app (which starts and updates it)
/// and the widget extension (which draws it on the Lock Screen and in the Dynamic Island).
///
/// Artwork is not part of the state (Live Activity updates are limited to 4 KB);
/// the extension reads it from the widget snapshot in the App Group.
struct EchoLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var songID: UUID
        var title: String
        var artist: String
        var isPodcast: Bool
        var isPlaying: Bool
        /// Position in seconds at `updatedAt`.
        var elapsed: Double
        var duration: Double
        /// Playback rate while playing (podcast speed, Mix tempo); 1 is normal speed.
        var rate: Double
        var updatedAt: Date

        /// Wall-clock interval over which the progress bar runs from 0 to the end,
        /// so the system can animate it without further updates.
        var progressInterval: ClosedRange<Date>? {
            guard isPlaying, duration > 0, rate > 0 else { return nil }
            let start = updatedAt.addingTimeInterval(-elapsed / rate)
            return start...start.addingTimeInterval(duration / rate)
        }

        var progress: Double {
            guard duration > 0 else { return 0 }
            return min(1, max(0, elapsed / duration))
        }

        /// Position this state predicts for `date`.
        func expectedElapsed(at date: Date) -> Double {
            guard isPlaying else { return elapsed }
            return elapsed + date.timeIntervalSince(updatedAt) * rate
        }

        /// True when `other` would look the same on screen, so no update is needed.
        func matches(_ other: ContentState, at date: Date = Date()) -> Bool {
            songID == other.songID && title == other.title && artist == other.artist
                && isPlaying == other.isPlaying && abs(duration - other.duration) < 0.5
                && abs(rate - other.rate) < 0.01
                && abs(expectedElapsed(at: date) - other.elapsed) < 1.5
        }
    }
}
