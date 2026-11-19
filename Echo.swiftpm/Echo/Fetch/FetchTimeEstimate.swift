import Foundation
import Observation
import SwiftUI

/// Estimates how long the remaining downloads take, from how long recent songs took on this device.
@MainActor @Observable final class FetchTimeEstimate {
    static let shared = FetchTimeEstimate()

    private static let storageKey = "fetch.recentItemDurations"
    private static let fallbackSeconds: TimeInterval = 45
    private static let sampleLimit = 20

    @ObservationIgnored private var startedAt: [UUID: Date] = [:]
    private var recent: [TimeInterval]

    private init() {
        recent = (UserDefaults.standard.array(forKey: Self.storageKey) as? [Double]) ?? []
    }

    func started(_ id: UUID, at date: Date) { startedAt[id] = date }

    func ended(_ id: UUID, success: Bool) {
        guard let start = startedAt.removeValue(forKey: id), success else { return }
        let duration = Date().timeIntervalSince(start)
        // Ignore outliers such as a song that waited on a lost connection.
        guard duration > 1, duration < 30 * 60 else { return }
        recent = Array((recent + [duration]).suffix(Self.sampleLimit))
        UserDefaults.standard.set(recent, forKey: Self.storageKey)
    }

    /// Typical time for one song: the median of recent songs, which is robust to one slow download.
    var typicalSeconds: TimeInterval {
        guard !recent.isEmpty else { return Self.fallbackSeconds }
        let sorted = recent.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Seconds until every queued and active song is done, or nil when nothing is pending.
    func remaining(for items: [FetchItem], now: Date = Date()) -> TimeInterval? {
        let pending = items.filter { $0.queueState == .pending }
        guard !pending.isEmpty else { return nil }
        let typical = typicalSeconds
        return pending.reduce(0.0) { (total: TimeInterval, item: FetchItem) -> TimeInterval in
            guard let progress = item.status.progress, let start = startedAt[item.id] else { return total + typical }
            let elapsed = now.timeIntervalSince(start)
            return total + max(typical - elapsed, typical * (1 - progress) * 0.5, 3)
        }
    }

    /// "About 4 min left", rounded up to whole minutes so the label does not flicker every second.
    static func text(for seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return EchoLocalization.string("fetch_eta_under_minute") }
        let minutes = Int((seconds / 60).rounded(.up))
        let duration = Duration.seconds(minutes * 60)
        let units: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 60 ? [.hours, .minutes] : [.minutes]
        let formatted = duration.formatted(
            .units(allowed: units, width: .abbreviated)
                .locale(EchoLanguage.current.locale)
        )
        return String(format: EchoLocalization.string("fetch_eta"), formatted)
    }
}

/// A small clock with the estimated time left; hidden when nothing is downloading.
struct FetchTimeRemainingLabel: View {
    let items: [FetchItem]
    var font: Font = .caption.weight(.semibold)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { context in
            if let seconds = FetchTimeEstimate.shared.remaining(for: items, now: context.date) {
                Label(FetchTimeEstimate.text(for: seconds), systemImage: "clock")
                    .font(font)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityElement(children: .combine)
            }
        }
    }
}
