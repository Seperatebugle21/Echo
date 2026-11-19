import ActivityKit
import Foundation
import OSLog
import UIKit

/// Shows the download queue on the Lock Screen and in the Dynamic Island.
///
/// - Starts with the queue while Echo is on screen (an iOS requirement); updates keep
///   working on the Home Screen because the continued-processing task keeps Echo running.
/// - Sends an update only when the Lock Screen would change visibly.
/// - If the person dismisses it, it stays away until the next download run.
@MainActor final class FetchLiveActivity {
    static let shared = FetchLiveActivity()

    typealias State = EchoDownloadActivityAttributes.ContentState
    private var activity: Activity<EchoDownloadActivityAttributes>?
    private var last: State?
    private var dismissed = false
    private var cleanedUp = false
    private let logger = Logger(subsystem: "com.echomusic.app", category: "LiveActivity")

    private init() {}

    func update(_ state: State) {
        endLeftoversOnce()
        if let current = activity, current.activityState != .active {
            if current.activityState == .dismissed { dismissed = true }
            activity = nil
            last = nil
        }
        guard !dismissed else { return }
        guard let activity else { start(state); return }
        if let last, !state.differsVisibly(from: last) { return }
        last = state
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Shows the result for a few minutes, then removes the activity.
    func finish(_ state: State) {
        defer { activity = nil; last = nil; dismissed = false }
        guard let activity else { return }
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil),
                               dismissalPolicy: .after(Date().addingTimeInterval(5 * 60)))
        }
    }

    private func start(_ state: State) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              UIApplication.shared.applicationState == .active else { return }
        do {
            activity = try Activity.request(
                attributes: EchoDownloadActivityAttributes(language: EchoLanguage.current.rawValue),
                content: ActivityContent(state: state, staleDate: nil))
            last = state
        } catch {
            logger.error("Download Live Activity not started: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// An activity from a run that ended with the app (crash, swipe away) would otherwise stay forever.
    private func endLeftoversOnce() {
        guard !cleanedUp else { return }
        cleanedUp = true
        for leftover in Activity<EchoDownloadActivityAttributes>.activities {
            Task { await leftover.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
