import ActivityKit
import Foundation
import OSLog
import UIKit

/// Starts, updates and ends the now-playing Live Activity from the player state.
///
/// - Starts only while something plays and the app is in the foreground
///   (an iOS requirement); later updates also work in the background.
/// - Skips updates the Lock Screen would not show differently.
/// - If the person dismisses it, it stays away until the next song.
@MainActor final class EchoLiveActivityController {
    static let shared = EchoLiveActivityController()

    private typealias State = EchoLiveActivityAttributes.ContentState
    private var activity: Activity<EchoLiveActivityAttributes>?
    private var lastState: State?
    private var dismissedSongID: UUID?
    private var adoptedExisting = false
    private let logger = Logger(subsystem: "com.echomusic.app", category: "LiveActivity")

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            // A start that failed in the background can succeed now.
            Task { @MainActor in AudioPlayerManager.shared.syncLiveActivity() }
        }
    }

    func update(song: Song, isPlaying: Bool, elapsed: Double, duration: Double, rate: Double, force: Bool = false) {
        let now = Date()
        let state = State(songID: song.id, title: song.title, artist: song.artist,
                          isPodcast: song.podcastEpisodeID != nil, isPlaying: isPlaying,
                          elapsed: elapsed.isFinite ? max(0, elapsed) : 0,
                          duration: duration.isFinite ? max(0, duration) : 0,
                          rate: rate.isFinite && rate > 0 ? rate : 1, updatedAt: now)

        adoptExistingIfNeeded()
        if let current = activity, current.activityState != .active {
            // Dismissed from the Lock Screen, or ended by the system.
            if current.activityState == .dismissed { dismissedSongID = lastState?.songID }
            activity = nil
            lastState = nil
        }
        if dismissedSongID != nil, dismissedSongID != song.id { dismissedSongID = nil }
        guard dismissedSongID == nil else { return }

        if !force, let lastState, lastState.matches(state, at: now) { return }
        let content = ActivityContent(state: state, staleDate: nil)

        if let activity {
            lastState = state
            Task { await activity.update(content) }
            return
        }
        guard isPlaying, ActivityAuthorizationInfo().areActivitiesEnabled,
              UIApplication.shared.applicationState == .active else { return }
        do {
            activity = try Activity.request(attributes: EchoLiveActivityAttributes(), content: content)
            lastState = state
        } catch {
            logger.error("Live Activity not started: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Redraws with the current state, e.g. once new artwork is in the App Group.
    func refresh() {
        guard let activity, let lastState else { return }
        var state = lastState
        let now = Date()
        state.elapsed = lastState.expectedElapsed(at: now)
        state.updatedAt = now
        self.lastState = state
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        adoptExistingIfNeeded()
        let ending = Activity<EchoLiveActivityAttributes>.activities
        activity = nil
        lastState = nil
        dismissedSongID = nil
        for item in ending {
            Task { await item.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// After a relaunch, keep one activity from the previous run and end any extras.
    private func adoptExistingIfNeeded() {
        guard !adoptedExisting else { return }
        adoptedExisting = true
        let existing = Activity<EchoLiveActivityAttributes>.activities
        activity = existing.first { $0.activityState == .active }
        for item in existing where item.id != activity?.id {
            Task { await item.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
