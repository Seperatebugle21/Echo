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
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { task in
            Task { @MainActor in
                let work = Task { await self.refresh(force: true) }
                task.expirationHandler = { work.cancel() }
                await work.value
                task.setTaskCompleted(success: !work.isCancelled)
                self.schedule()
            }
        }
        schedule()
    }
    func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskID)
        guard !follows.isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        request.earliestBeginDate = Date().addingTimeInterval(3600)
        try? BGTaskScheduler.shared.submit(request)
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
        for follow in Array(follows.values).sorted(by: { $0.lastChecked < $1.lastChecked }) {
            guard !Task.isCancelled else { break }
            guard !busy.contains(follow.show.id), force || Date().timeIntervalSince(follow.lastChecked) >= 3600 else { continue }
            busy.insert(follow.show.id)
            do {
                let feed = try await PodcastCatalog.shared.feed(for: follow.show)
                try Task.checkCancellation()
                try await ingest(feed.episodes, show: follow.show)
            } catch { /* Keep the successful baseline; retry on the next refresh. */ }
            busy.remove(follow.show.id)
        }
    }
    func ingest(_ episodes: [PodcastEpisode], show: PodcastShow) async throws {
        guard !ingesting.contains(show.id), var follow = follows[show.id] else { return }
        ingesting.insert(show.id)
        defer { ingesting.remove(show.id) }
        let now = Date(), fresh = PodcastReleaseDetection.fresh(episodes, follow: follow, now: Date())
        if let newest = fresh.first {
            let content = UNMutableNotificationContent()
            let locale = Locale(identifier: UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en")
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
