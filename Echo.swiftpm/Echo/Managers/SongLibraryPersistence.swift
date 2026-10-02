import Foundation

/// Coalesces snapshots and keeps JSON encoding and atomic file writes off the UI thread.
final class SongLibraryPersistence: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "com.echomusic.library-storage", qos: .utility)
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var completions: [() -> Void] = []

    init(url: URL) { self.url = url }

    func submit(_ songs: [Song], immediately: Bool = false, completion: (() -> Void)? = nil) {
        lock.lock()
        revision &+= 1
        let token = revision
        if let completion { completions.append(completion) }
        lock.unlock()
        queue.asyncAfter(deadline: .now() + (immediately ? 0 : 0.4)) { [self] in
            guard isCurrent(token) else { return }
            do {
                let data = try JSONEncoder().encode(songs)
                guard isCurrent(token) else { return }
                try data.write(to: url, options: .atomic)
            } catch {
                print("Songs opslaan mislukt:", error.localizedDescription)
            }
            complete(token)
        }
    }

    private func isCurrent(_ token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return revision == token
    }

    private func complete(_ token: UInt64) {
        lock.lock()
        let callbacks = revision == token ? completions : []
        if revision == token { completions.removeAll() }
        lock.unlock()
        callbacks.forEach { $0() }
    }
}
