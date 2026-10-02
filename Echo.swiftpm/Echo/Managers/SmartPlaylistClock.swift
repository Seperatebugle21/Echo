import Foundation
import Observation
import UIKit

@MainActor @Observable final class SmartPlaylistClock {
    static let shared = SmartPlaylistClock()
    private(set) var now = Date()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        for name in [Notification.Name.NSCalendarDayChanged, UIApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.now = Date() }
            })
        }
    }
}
