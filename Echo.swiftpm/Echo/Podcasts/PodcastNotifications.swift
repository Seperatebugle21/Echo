import Foundation
import Observation
import UserNotifications
import BackgroundTasks
import UIKit
import CryptoKit

extension Notification.Name { static let echoOpenPodcast = Notification.Name("EchoOpenPodcast") }

@MainActor @Observable final class PodcastNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PodcastNotifications()
    static let taskID = "com.echomusic.app.podcast-refresh"
    /// Longer runs that iOS usually grants while charging; a second chance besides app refresh.
    static let processingTaskID = "com.echomusic.app.podcast-processing"
    private(set) var follows: [Int: PodcastFollow] = [:]
    private(set) var busy: Set<Int> = []
    var errorKey: String?
    var permissionDenied = false
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var ingesting: Set<Int> = []
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    private var stateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Podcasts/notifications.json")
    }
    override init() {
        super.init()
        if let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode([Int: PodcastFollow].self, from: data) { follows = saved }
        center.delegate = self
    }
    /// No server is involved: iOS wakes Echo now and then (app refresh, and processing time while
    /// charging), and Echo checks the followed feeds itself. While Echo plays in the background it
    /// also checks every 20 minutes. iOS decides the exact timing and skips apps swiped away.
    func registerBackgroundTask() {
        for (identifier, budget) in [(Self.taskID, 25.0), (Self.processingTaskID, 120.0)] {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
                Task { @MainActor in
                    let work = Task { await self.refresh(force: true) }
                    // App refresh gets about 30 seconds; finish cleanly before iOS stops the app.
                    let deadline = Task { try await Task.sleep(for: .seconds(budget)); work.cancel() }
                    task.expirationHandler = { work.cancel() }
                    await work.value
                    deadline.cancel()
                    task.setTaskCompleted(success: !work.isCancelled)
                    self.schedule()
                }
            }
        }
        schedule()
        checkWhileRunningInBackground()
    }
    func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskID)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.processingTaskID)
        guard !follows.isEmpty else { return }
        let refresh = BGAppRefreshTaskRequest(identifier: Self.taskID)
        refresh.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(refresh)
        let processing = BGProcessingTaskRequest(identifier: Self.processingTaskID)
        processing.requiresNetworkConnectivity = true
        processing.earliestBeginDate = Date().addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(processing)
    }
    /// Background audio keeps Echo running; use that time instead of waiting for iOS to wake it.
    private func checkWhileRunningInBackground() {
        Task { @MainActor in
            while true {
                do { try await Task.sleep(for: .seconds(20 * 60)) } catch { return }
                if UIApplication.shared.applicationState == .background { await refresh() }
            }
        }
    }
    func toggle(_ show: PodcastShow) async {
        guard !busy.contains(show.id) else { return }
        if follows[show.id] != nil {
            follows.removeValue(forKey: show.id)
            persist()
            center.removePendingNotificationRequests(withIdentifiers: [requestID(show.id)])
            center.removeDeliveredNotifications(withIdentifiers: [requestID(show.id)])
            schedule()
            return
        }
        busy.insert(show.id)
        defer { busy.remove(show.id) }
        do {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .denied { permissionDenied = true; return }
            if settings.authorizationStatus == .notDetermined {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { permissionDenied = true; return }
            }
            let feed = try await PodcastCatalog.shared.feed(for: show)
            try Task.checkCancellation()
            let now = Date()
            follows[show.id] = PodcastFollow(show: show, enabledAt: now,
                knownIDs: Set(feed.episodes.filter { ($0.published ?? now) <= now }.map(\.id)), lastChecked: now)
            persist()
            schedule()
        } catch { if !Task.isCancelled { errorKey = "podcast_notifications_error" } }
    }
    func refresh(force: Bool = false) async {
        guard !refreshing, !follows.isEmpty else { return }
        refreshing = true
        defer { refreshing = false; schedule() }
        let permission = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(permission.authorizationStatus) else { return }
        let due = Array(follows.values).sorted(by: { $0.lastChecked < $1.lastChecked }).filter {
            !busy.contains($0.show.id) && (force || Date().timeIntervalSince($0.lastChecked) >= 3600)
        }
        busy.formUnion(due.map(\.show.id))
        defer { busy.subtract(due.map(\.show.id)) }
        // Fetch feeds side by side so many follows fit in iOS's short background window.
        await withTaskGroup(of: (PodcastShow, PodcastFeed?).self) { group in
            var waiting = due.makeIterator()
            for _ in 0..<6 { // at most six requests at once
                guard let follow = waiting.next() else { break }
                group.addTask { (follow.show, try? await PodcastCatalog.shared.feed(for: follow.show)) }
            }
            while let result = await group.next() {
                if let follow = waiting.next() {
                    group.addTask { (follow.show, try? await PodcastCatalog.shared.feed(for: follow.show)) }
                }
                // A failed feed keeps its baseline and is retried on the next refresh.
                guard let feed = result.1, !Task.isCancelled else { continue }
                try? await ingest(feed.episodes, show: result.0)
            }
        }
    }
    func ingest(_ episodes: [PodcastEpisode], show: PodcastShow) async throws {
        guard !ingesting.contains(show.id), var follow = follows[show.id] else { return }
        ingesting.insert(show.id)
        defer { ingesting.remove(show.id) }
        let now = Date(), fresh = PodcastReleaseDetection.fresh(episodes, follow: follow, now: Date())
        if let newest = fresh.first {
            let content = UNMutableNotificationContent()
            let locale = EchoLanguage.current.locale
            content.title = String(localized: "podcast_notification_title", locale: locale)
            let format = String(localized: fresh.count > 1 ? "podcast_notification_multiple" : "podcast_notification_body", locale: locale)
            content.body = fresh.count > 1 ? String(format: format, show.title, newest.title, fresh.count) : String(format: format, show.title, newest.title)
            content.sound = .default
            content.threadIdentifier = "podcast-\(show.id)"
            content.userInfo = ["echoPodcastShow": try JSONEncoder().encode(show).base64EncodedString()]
            try Task.checkCancellation()
            try await center.add(UNNotificationRequest(identifier: requestID(show.id), content: content, trigger: nil))
        }
        guard follows[show.id] != nil else { return }
        follow.knownIDs = PodcastReleaseDetection.knownIDs(after: episodes, follow: follow, now: now)
        follow.lastChecked = now
        follows[show.id] = follow
        persist()
    }
    private func requestID(_ id: Int) -> String { "echo.podcast.\(id)" }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(follows).write(to: stateURL, options: .atomic)
        } catch { errorKey = "podcasts_storage_error" }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let encoded = response.notification.request.content.userInfo["echoPodcastShow"] as? String
        Task { @MainActor in
            if let encoded, let data = Data(base64Encoded: encoded), let show = try? JSONDecoder().decode(PodcastShow.self, from: data) {
                AppRouter.shared.open(.podcast(show))
            }
            completionHandler()
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
