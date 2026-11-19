import BackgroundTasks
import Foundation
import os
import UIKit
import UserNotifications

/// Whether Fetch may work at full speed: the app is on screen, or iOS granted a
/// continued-processing task after the user left it. Readable from any thread,
/// including URLSession delegate queues.
enum FetchBackgroundState {
    private struct Flags { var appActive = false; var continuedTask = false }
    private static let flags = OSAllocatedUnfairLock(initialState: Flags())
    @MainActor private static var observers: [NSObjectProtocol] = []

    static var allowsFullSpeedWork: Bool { flags.withLock { $0.appActive || $0.continuedTask } }
    static var continuedTaskRunning: Bool { flags.withLock { $0.continuedTask } }
    static func setContinuedTask(_ running: Bool) { flags.withLock { $0.continuedTask = running } }

    @MainActor static func startObserving() {
        guard observers.isEmpty else { return }
        flags.withLock { $0.appActive = UIApplication.shared.applicationState == .active }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                flags.withLock { $0.appActive = true }
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
    private lazy var identifier: String? = {
        let candidates = [Bundle.main.bundleIdentifier.map { "\($0).\(Self.suffix)" }, "com.echomusic.app.\(Self.suffix)"]
        return candidates.compactMap { $0 }.first(where: Self.isPermitted)
    }()
    private var registered = false
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
        startTicker()
        guard !submitted, task == nil, UIApplication.shared.applicationState == .active,
              let identifier, register(identifier) else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            submitted = true
        } catch {
            Logger(subsystem: "com.echomusic.app", category: "Fetch")
                .error("Continued processing unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Call when the queue has no more work.
    func finish() {
        let items = FetchManager.shared.items.filter { batch.contains($0.id) }
        let added = items.filter { $0.status == .completed }.count
        let failed = items.filter { if case .failed = $0.status { true } else { false } }.count
        if UIApplication.shared.applicationState != .active, added + failed > 0 {
            notify(added: added, failed: failed)
        }
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
        if registered { return true }
        // iOS raises an uncatchable exception for an identifier it does not accept. If a previous
        // attempt never returned, skip continued processing instead of crashing on every download.
        let guardKey = "fetch.continuedProcessing.registering"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: guardKey) else { return false }
        defaults.set(true, forKey: guardKey)
        defaults.synchronize()
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                self?.launched(task)
            }
        }
        defaults.set(false, forKey: guardKey)
        return registered
    }

    private func launched(_ task: BGContinuedProcessingTask) {
        guard submitted else { task.setTaskCompleted(success: true); return }
        self.task = task
        FetchBackgroundState.setContinuedTask(true)
        task.expirationHandler = { [weak self] in
            // The user stopped it from the system UI, or iOS needs the resources back.
            Task { @MainActor in
                FetchBackgroundState.setContinuedTask(false)
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
                self?.updateProgress()
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
        let units = items.reduce(0.0) { sum, item in
            switch item.status {
            case .completed, .failed: sum + 1
            default: sum + (item.status.progress ?? 0)
            }
        }
        task.progress.totalUnitCount = Int64(max(items.count, 1) * 100)
        task.progress.completedUnitCount = Int64(units * 100)
        task.updateTitle(title, subtitle: subtitle)
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
            Task { @MainActor in self?.endGrace() }
        }
    }

    private func endGrace() {
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
