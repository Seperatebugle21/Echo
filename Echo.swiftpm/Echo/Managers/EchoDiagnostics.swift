import Foundation
import UIKit
import MetricKit
import SwiftUI

/// A small on-device log for Settings > Developer: download steps, crashes (from
/// MetricKit, delivered by iOS after a relaunch), sessions that ended unexpectedly,
/// memory warnings and, when switched on, dropped frames.
final class EchoDiagnostics: NSObject, @unchecked Sendable, MXMetricManagerSubscriber {
    static let shared = EchoDiagnostics()

    enum Category: String, Codable, CaseIterable, Identifiable {
        case download, crash, app, memory, hitch
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .download: "arrow.down.circle"
            case .crash: "exclamationmark.octagon"
            case .app: "app"
            case .memory: "memorychip"
            case .hitch: "speedometer"
            }
        }
    }

    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        let date: Date
        let category: Category
        let message: String
    }

    private let queue = DispatchQueue(label: "com.echomusic.diagnostics", qos: .utility)
    private var entries: [Entry] = []
    private let limit = 600
    private let fileURL: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("EchoDiagnostics.json")
    }()
    private let defaults = UserDefaults.standard
    private static let sessionKey = "diagnostics.sessionActive"
    private static let downloadsKey = "diagnostics.downloadsActive"
    private var activeDownloads = Set<UUID>()
    private var started = false

    private override init() {
        super.init()
        queue.sync {
            if let data = try? Data(contentsOf: fileURL),
               let saved = try? JSONDecoder().decode([Entry].self, from: data) {
                entries = saved
            }
        }
    }

    // MARK: Starting

    @MainActor func start() {
        guard !started else { return }
        started = true
        if defaults.bool(forKey: Self.sessionKey) {
            log(.crash, "Echo stopte onverwacht terwijl het open was (crash of te weinig geheugen). Zie de regels hiervoor.")
        } else if defaults.bool(forKey: Self.downloadsKey) {
            log(.app, "Echo stopte terwijl er op de achtergrond werd gedownload (weggeveegd of door iOS gestopt).")
        }
        defaults.set(false, forKey: Self.downloadsKey)
        markActive(true)
        log(.app, "Gestart · \(Self.memoryDescription())")

        MXMetricManager.shared.add(self)
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.markActive(true)
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.markActive(false)
            self?.log(.app, "Naar de achtergrond · \(Self.memoryDescription())")
        }
        center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.markActive(false)
            self?.defaults.set(false, forKey: Self.downloadsKey)
        }
        center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.log(.memory, "Geheugenwaarschuwing van iOS · \(Self.memoryDescription())")
        }

        // Every download step, without the download code knowing about this log.
        FetchItem.statusObserver = { [weak self] item, old, new in
            self?.downloadChanged(item, from: old, to: new)
        }
    }

    private func markActive(_ active: Bool) {
        defaults.set(active, forKey: Self.sessionKey)
    }

    // MARK: Writing

    func log(_ category: Category, _ message: String) {
        let entry = Entry(date: Date(), category: category, message: message)
        queue.async { [self] in
            entries.append(entry)
            if entries.count > limit { entries.removeFirst(entries.count - limit) }
            if let data = try? JSONEncoder().encode(entries) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    func snapshot() -> [Entry] {
        queue.sync { entries }
    }

    func clear() {
        queue.async { [self] in
            entries.removeAll()
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// The whole log as plain text, for sharing.
    func text(_ entries: [Entry]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return entries.map { "\(formatter.string(from: $0.date)) [\($0.category.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }

    // MARK: Downloads

    private func downloadChanged(_ item: FetchItem, from old: FetchStatus, to new: FetchStatus) {
        let name = "\(item.artist) – \(item.title)"
        switch (old, new) {
        case (.queued, .queued): return
        case (.preparing, .preparing), (.downloading, .downloading), (.processing, .processing):
            // Progress within a step: only every quarter.
            if let before = old.progress, let after = new.progress, Int(before * 4) != Int(after * 4) {
                log(.download, "\(name): \(Int(after * 100))% (\(new.stepName))")
            }
            return
        default:
            break
        }
        switch new {
        case .queued:
            log(.download, "\(name): in wachtrij")
        case .preparing, .downloading, .processing:
            activeDownloads.insert(item.id)
            log(.download, "\(name): \(new.stepName) · \(Self.memoryDescription())")
        case .completed:
            activeDownloads.remove(item.id)
            log(.download, "\(name): klaar")
        case .failed(let message):
            activeDownloads.remove(item.id)
            log(.download, "\(name): MISLUKT – \(message) · \(Self.memoryDescription())")
        }
        defaults.set(!activeDownloads.isEmpty, forKey: Self.downloadsKey)
    }

    // MARK: MetricKit (crashes and hangs, delivered after a relaunch)

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                var parts: [String] = ["Crashrapport van iOS"]
                if let type = crash.exceptionType { parts.append("exception \(type)") }
                if let code = crash.exceptionCode { parts.append("code \(code)") }
                if let signal = crash.signal { parts.append("signaal \(signal)") }
                if let reason = crash.terminationReason { parts.append(reason) }
                if let region = crash.virtualMemoryRegionInfo { parts.append(region) }
                parts.append("versie \(crash.metaData.applicationBuildVersion)")
                let stack = String(data: crash.callStackTree.jsonRepresentation(), encoding: .utf8) ?? ""
                log(.crash, parts.joined(separator: " · ") + "\n" + String(stack.prefix(2500)))
            }
            for hang in payload.hangDiagnostics ?? [] {
                log(.hitch, "iOS meldt dat Echo \(hang.hangDuration.formatted()) niet reageerde")
            }
        }
    }

    // MARK: Memory

    static func memoryDescription() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "geheugen onbekend" }
        return "geheugen \(info.phys_footprint / 1_048_576) MB"
    }
}

private extension FetchStatus {
    var stepName: String {
        switch self {
        case .queued: "wachtrij"
        case .preparing: "voorbereiden"
        case .downloading: "downloaden"
        case .processing: "omzetten"
        case .completed: "klaar"
        case .failed: "mislukt"
        }
    }
}

// MARK: - Dropped frames

/// Counts frames that took clearly longer than the display allows, while switched on
/// in Settings > Developer. A small badge shows the count; longer hitches are logged.
@MainActor @Observable
final class EchoHitchMonitor: NSObject {
    static let shared = EchoHitchMonitor()
    static let enabledKey = "developerHitchMonitor"

    private(set) var recentHitches = 0
    private(set) var totalHitches = 0
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval = 0
    @ObservationIgnored private var recent: [CFTimeInterval] = []

    func setEnabled(_ enabled: Bool) {
        if enabled, link == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
            lastTimestamp = 0
        } else if !enabled {
            link?.invalidate()
            link = nil
            recent.removeAll()
            recentHitches = 0
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTimestamp = now }
        guard lastTimestamp > 0 else { return }
        let expected = max(1.0 / 120.0, link.targetTimestamp - link.timestamp)
        let actual = now - lastTimestamp
        recent.removeAll { now - $0 > 5 }
        if actual > expected * 2.5 {
            recent.append(now)
            totalHitches += 1
            if actual > 0.05 {
                EchoDiagnostics.shared.log(.hitch, "Hapering van \(Int(actual * 1000)) ms")
            }
        }
        if recent.count != recentHitches { recentHitches = recent.count }
    }
}

/// The badge shown in a corner while the hitch monitor is on.
struct EchoHitchBadge: View {
    @AppStorage(EchoHitchMonitor.enabledKey) private var enabled = false
    private let monitor = EchoHitchMonitor.shared

    var body: some View {
        Group {
            if enabled {
                Text(verbatim: "⚡︎ \(monitor.recentHitches) · \(monitor.totalHitches)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(monitor.recentHitches > 0 ? Color.red.opacity(0.85) : Color.green.opacity(0.7), in: .capsule)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: enabled, initial: true) { _, on in monitor.setEnabled(on) }
    }
}

// MARK: - Log screen

struct EchoDiagnosticsView: View {
    @State private var entries: [EchoDiagnostics.Entry] = []
    @State private var filter: EchoDiagnostics.Category?

    private var shown: [EchoDiagnostics.Entry] {
        let list = filter.map { category in entries.filter { $0.category == category } } ?? entries
        return list.reversed()
    }

    var body: some View {
        List {
            Section {
                Picker("diagnostics_filter", selection: $filter) {
                    Text("diagnostics_all").tag(EchoDiagnostics.Category?.none)
                    Text("diagnostics_downloads").tag(EchoDiagnostics.Category?.some(.download))
                    Text("diagnostics_crashes").tag(EchoDiagnostics.Category?.some(.crash))
                    Text("diagnostics_hitches").tag(EchoDiagnostics.Category?.some(.hitch))
                }
                .pickerStyle(.segmented)
            }
            if shown.isEmpty {
                Text("diagnostics_empty").foregroundStyle(.secondary)
            }
            ForEach(shown) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: entry.category.symbol)
                            .foregroundStyle(entry.category == .crash ? Color.red : .secondary)
                        Text(entry.date, format: .dateTime.day().month().hour().minute().second())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: entry.message)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(entry.category == .crash ? 12 : 4)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("developer_diagnostics_log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: EchoDiagnostics.shared.text(entries)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("diagnostics_share")
                Button(role: .destructive) {
                    EchoDiagnostics.shared.clear()
                    entries = []
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("diagnostics_clear")
            }
        }
        .refreshable { entries = EchoDiagnostics.shared.snapshot() }
        .onAppear { entries = EchoDiagnostics.shared.snapshot() }
    }
}
