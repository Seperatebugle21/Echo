import BackgroundTasks
import Foundation
import os
import UIKit
import UserNotifications

/// Whether Fetch may work at full speed: the app is on screen, or iOS granted a
/// continued-processing task after the user left it. Readable from any thread,
/// including URLSession delegate queues.
enum FetchBackgroundState {
    private struct Flags { var appActive = false; var continuedTask = false; var graceTime = false }
    private static let flags = OSAllocatedUnfairLock(initialState: Flags())
    @MainActor private static var observers: [NSObjectProtocol] = []

    static var allowsFullSpeedWork: Bool { flags.withLock { $0.appActive || $0.continuedTask || $0.graceTime } }
    static var continuedTaskRunning: Bool { flags.withLock { $0.continuedTask } }
    static func setContinuedTask(_ running: Bool) { flags.withLock { $0.continuedTask = running } }
    /// The ~30 seconds iOS gives every app after it leaves the screen: long enough for a
    /// fast download of a few seconds, so a song does not drop to the slow background session.
    static func setGraceTime(_ available: Bool) { flags.withLock { $0.graceTime = available } }

    @MainActor static func startObserving() {
        guard observers.isEmpty else { return }
        flags.withLock { $0.appActive = UIApplication.shared.applicationState == .active }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                flags.withLock { $0.appActive = true }
                // Downloads that fell back to the slow background session continue at full speed.
                MainActor.assumeIsolated { FetchDownloadEngine.shared.accelerateBackgroundTransfers() }
            },
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
                flags.withLock { $0.appActive = false }
            },
        ]
    }
}

/// Keeps the download queue (resolving, downloading, MP3 encoding, importing) running
/// when the user goes to the Home Screen, and posts a notification when it is done.
/// iOS shows its own progress for the task and lets the user stop it. Swiping Echo
/// away in the app switcher still ends all work; iOS allows nothing after that.
@MainActor final class FetchContinuedProcessing {
    static let shared = FetchContinuedProcessing()

    private static let suffix = "fetch-downloads"
    /// The bundle ID changes when SideStore re-signs Echo, so both forms are allowed in Info.plist.
    private lazy var identifiers: [String] = {
        let candidates = [Bundle.main.bundleIdentifier.map { "\($0).\(Self.suffix)" }, "com.echomusic.app.\(Self.suffix)"]
        var unique: [String] = []
        for candidate in candidates.compactMap({ $0 }) where Self.isPermitted(candidate) && !unique.contains(candidate) {
            unique.append(candidate)
        }
        return unique
    }()
    private var registered: Set<String> = []
    /// What iOS answered last time, shown under Settings > Developer to diagnose background downloads.
    private(set) var status = "Not requested yet"
    private var task: BGContinuedProcessingTask?
    private var submitted = false
    private var graceTask: UIBackgroundTaskIdentifier = .invalid
    private var ticker: Task<Void, Never>?
    /// Items that belong to the current run, for progress and the final notification.
    private var batch: Set<UUID> = []

    private init() {}

    /// Call when the queue starts, while Echo is on screen (iOS only accepts the request then).
    func begin() {
        FetchBackgroundState.startObserving()
        requestNotificationPermissionIfNeeded()
        trackPendingItems()
        beginGrace()
        startTicker()
        FetchLiveActivity.shared.update(liveState())
        guard !submitted, task == nil, UIApplication.shared.applicationState == .active else { return }
        guard !identifiers.isEmpty else { status = "No permitted task identifier for \(Bundle.main.bundleIdentifier ?? "?")"; return }
        var problems: [String] = []
        // SideStore changes the bundle ID, so try each permitted form until iOS accepts one.
        for identifier in identifiers {
            guard register(identifier) else { problems.append("\(identifier): could not register"); continue }
            let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
            request.strategy = .fail
            do {
                try BGTaskScheduler.shared.submit(request)
                submitted = true
                status = "Requested as \(identifier); waiting for iOS"
                return
            } catch {
                problems.append("\(identifier): \(error.localizedDescription)")
            }
        }
        status = "iOS refused background downloads. " + problems.joined(separator: " / ")
        Logger(subsystem: "com.echomusic.app", category: "Fetch").error("\(self.status, privacy: .public)")
    }

    /// Call when the queue has no more work.
    func finish() {
        let items = FetchManager.shared.items.filter { batch.contains($0.id) }
        let added = items.filter { $0.status == .completed }.count
        let failed = items.filter { $0.queueState == .failed }.count
        if UIApplication.shared.applicationState != .active, added + failed > 0 {
            notify(added: added, failed: failed)
        }
        FetchLiveActivity.shared.finish(liveState(finished: true))
        batch = []
        ticker?.cancel(); ticker = nil
        task?.progress.completedUnitCount = task?.progress.totalUnitCount ?? 0
        task?.setTaskCompleted(success: failed == 0)
        task = nil
        submitted = false
        FetchBackgroundState.setContinuedTask(false)
        endGrace()
    }

    // MARK: - Task

    private func register(_ identifier: String) -> Bool {
        if registered.contains(identifier) { return true }
        // iOS raises an uncatchable exception for an identifier it does not accept. If a previous
        // attempt never returned, skip continued processing instead of crashing on every download.
        let guardKey = "fetch.continuedProcessing.registering.\(identifier)"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: guardKey) else {
            status = "Skipped: registering crashed Echo once before"
            return false
        }
        defaults.set(true, forKey: guardKey)
        defaults.synchronize()
        let accepted = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                self?.launched(task)
            }
        }
        defaults.set(false, forKey: guardKey)
        if accepted { registered.insert(identifier) }
        return accepted
    }

    private func launched(_ task: BGContinuedProcessingTask) {
        guard submitted else { task.setTaskCompleted(success: true); return }
        self.task = task
        status = "Running: iOS keeps downloads going in the background"
        FetchBackgroundState.setContinuedTask(true)
        FetchDownloadEngine.shared.accelerateBackgroundTransfers()
        task.expirationHandler = { [weak self] in
            // The user stopped it from the system UI, or iOS needs the resources back.
            Task { @MainActor in
                FetchBackgroundState.setContinuedTask(false)
                self?.status = "Stopped early by iOS or from the Lock Screen"
                self?.task = nil
                self?.submitted = false
                self?.beginGrace()
            }
        }
        updateProgress()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.trackPendingItems()
                self?.refreshGrace()
                self?.updateProgress()
                if let self { FetchLiveActivity.shared.update(self.liveState()) }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func trackPendingItems() {
        for item in FetchManager.shared.items where item.queueState == .pending { batch.insert(item.id) }
    }

    /// iOS expires a continued-processing task that stops reporting progress.
    private func updateProgress() {
        guard let task else { return }
        let items = FetchManager.shared.items.filter { batch.contains($0.id) }
        let units = items.reduce(0.0) { (sum: Double, item: FetchItem) -> Double in
            item.queueState == .pending ? sum + (item.status.progress ?? 0) : sum + 1
        }
        task.progress.totalUnitCount = Int64(max(items.count, 1) * 100)
        task.progress.completedUnitCount = Int64(units * 100)
        task.updateTitle(title, subtitle: subtitle)
    }

    private func liveState(finished: Bool = false) -> FetchLiveActivity.State {
        let items = FetchManager.shared.items.filter { batch.contains($0.id) }
        let current = items.first { $0.status.progress != nil }
        let units = items.reduce(0.0) { (sum: Double, item: FetchItem) -> Double in
            item.queueState == .pending ? sum + (item.status.progress ?? 0) : sum + 1
        }
        return FetchLiveActivity.State(
            done: items.filter { $0.queueState != .pending }.count,
            total: max(items.count, 1),
            failed: items.filter { $0.queueState == .failed }.count,
            currentTitle: finished ? nil : current?.title,
            currentArtist: finished ? nil : current?.artist,
            progress: finished ? 1 : units / Double(max(items.count, 1)),
            finishesAt: finished ? nil : FetchTimeEstimate.shared.remaining(for: items).map { Date().addingTimeInterval($0) },
            finished: finished)
    }

    private var title: String { EchoLocalization.string("fetch_background_title") }
    private var subtitle: String {
        let items = FetchManager.shared.items.filter { batch.contains($0.id) }
        let done = items.filter { $0.queueState != .pending }.count
        return String(format: EchoLocalization.string("fetch_background_subtitle"), done, max(items.count, 1))
    }

    // Without a continued task, iOS still gives a short grace period after leaving the app.
    private func beginGrace() {
        guard graceTask == .invalid else { return }
        graceTask = UIApplication.shared.beginBackgroundTask(withName: "Echo downloads") { [weak self] in
            // Must end before this handler returns, or iOS terminates Echo.
            MainActor.assumeIsolated { self?.endGrace() }
        }
    }

    /// Renews the grace period after each return to Echo and stops starting fast downloads
    /// when too little of it is left to finish one.
    private func refreshGrace() {
        let application = UIApplication.shared
        if graceTask == .invalid, application.applicationState == .active, !batch.isEmpty { beginGrace() }
        FetchBackgroundState.setGraceTime(graceTask != .invalid && application.backgroundTimeRemaining > 15)
    }

    private func endGrace() {
        FetchBackgroundState.setGraceTime(false)
        guard graceTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(graceTask)
        graceTask = .invalid
    }

    // MARK: - Notifications

    private func requestNotificationPermissionIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    private func notify(added: Int, failed: Int) {
        let content = UNMutableNotificationContent()
        content.title = EchoLocalization.string("fetch_notification_done_title")
        content.body = failed == 0
            ? String(format: EchoLocalization.string("fetch_notification_done_body"), added)
            : String(format: EchoLocalization.string("fetch_notification_partial_body"), added, failed)
        content.sound = .default
        content.threadIdentifier = "echo-fetch"
        let request = UNNotificationRequest(identifier: "echo.fetch.done.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Info.plist

    /// Registering an identifier that Info.plist does not permit crashes, so check first.
    /// A trailing ".*" entry permits any identifier with that prefix.
    private static func isPermitted(_ identifier: String) -> Bool {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        return permitted.contains { entry in
            entry.hasSuffix(".*") ? identifier.hasPrefix(String(entry.dropLast())) && identifier.count > entry.count - 1
                                  : entry == identifier
        }
    }
}
