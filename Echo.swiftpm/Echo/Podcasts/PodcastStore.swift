import Foundation
import Observation
import CryptoKit

// All mutations are performed on the main queue, including URLSession delegates.
// Matches the app's existing observable manager ownership.
@Observable final class PodcastStore: NSObject, URLSessionDownloadDelegate {
    static let shared = PodcastStore()
    static let sessionIdentifier = "com.echomusic.app.podcast-downloads"
    private(set) var state = PodcastLibraryState()
    private(set) var progress: [String: Double] = [:]
    var errorKey: String?
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var backgroundCompletion: (() -> Void)?
    @ObservationIgnored private var prepared = false
    @ObservationIgnored private var restored = false
    @ObservationIgnored private var flushWork: DispatchWorkItem?
    @ObservationIgnored private var artworkTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Podcasts", isDirectory: true)
    }
    private var stateURL: URL { directory.appendingPathComponent("library.json") }

    override init() {
        super.init()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                state = try JSONDecoder().decode(PodcastLibraryState.self, from: Data(contentsOf: stateURL))
            }
            state.downloads = state.downloads.filter {
                FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.value).path)
            }
        } catch { errorKey = "podcasts_storage_error" }
    }

    var savedShows: [PodcastShow] { state.shows.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    var savedEpisodes: [PodcastEpisode] { sorted(state.savedEpisodeIDs.compactMap { state.episodes[$0] }) }
    var downloadedEpisodes: [PodcastEpisode] {
        sorted(Set(state.downloads.keys).union(state.pendingDownloads).compactMap { state.episodes[$0] })
    }
    var continueListening: [PodcastEpisode] {
        state.listening.filter { !$0.value.played && $0.value.position > 0 }
            .sorted { $0.value.updatedAt > $1.value.updatedAt }.compactMap { state.episodes[$0.key] }
    }
    var downloadBytes: Int64 {
        state.downloads.values.reduce(0) { total, file in
            let values = try? directory.appendingPathComponent(file).resourceValues(forKeys: [.fileSizeKey])
            return total + Int64(values?.fileSize ?? 0)
        }
    }
    private func sorted(_ episodes: [PodcastEpisode]) -> [PodcastEpisode] {
        episodes.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
    }
    func remember(_ episode: PodcastEpisode) {
        state.episodes[episode.id] = episode
        cacheArtworkIfNeeded(episode)
    }
    func cache(_ episodes: [PodcastEpisode], description: String, for show: PodcastShow) {
        state.cachedFeeds[show.id] = episodes
        state.showDescriptions[show.id] = description
        // Refresh metadata for items already saved, played or downloaded.
        for episode in episodes where state.episodes[episode.id] != nil { remember(episode) }
        persist()
    }
    func toggleShow(_ show: PodcastShow) {
        if state.shows.removeValue(forKey: show.id) == nil { state.shows[show.id] = show }
        cacheArtworkIfNeeded(show.artworkURL)
        persist()
    }
    func toggleSaved(_ episode: PodcastEpisode) {
        remember(episode)
        if !state.savedEpisodeIDs.insert(episode.id).inserted { state.savedEpisodeIDs.remove(episode.id) }
        EchoWidgetSnapshotPublisher.requestUpdate()
        persist()
    }
    func togglePlayed(_ episode: PodcastEpisode) {
        remember(episode)
        var status = state.listening[episode.id] ?? PodcastListeningState()
        status.played.toggle()
        status.position = 0
        status.updatedAt = Date()
        state.listening[episode.id] = status
        persist()
    }
    func record(_ id: String, position: Double, completed: Bool = false) {
        guard position.isFinite, position >= 0 else { return }
        var status = state.listening[id] ?? PodcastListeningState()
        status.position = completed ? 0 : position
        status.played = completed || status.played
        status.updatedAt = Date()
        state.listening[id] = status
        persist()
    }
    func beginListening(_ id: String) {
        if state.listening[id]?.played == true {
            state.listening[id] = PodcastListeningState()
        }
    }
    func localURL(_ id: String) -> URL? {
        guard let file = state.downloads[id] else { return nil }
        let url = directory.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func playbackURL(_ episode: PodcastEpisode) -> URL { localURL(episode.id) ?? episode.audioURL }
    func artwork(_ episode: PodcastEpisode) -> Data? {
        artwork(for: episode.artworkURL)
    }
    private func artworkURL(_ url: URL) -> URL {
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key + ".jpg")
    }
    func artwork(for url: URL?) -> Data? {
        guard let url else { return nil }
        return try? Data(contentsOf: artworkURL(url))
    }
    func cacheArtwork(_ data: Data, episode: PodcastEpisode) {
        guard let url = episode.artworkURL else { return }
        try? data.write(to: artworkURL(url), options: .atomic)
    }
    private func cacheArtworkIfNeeded(_ episode: PodcastEpisode) {
        cacheArtworkIfNeeded(episode.artworkURL)
    }
    private func cacheArtworkIfNeeded(_ url: URL?) {
        guard let url, artworkTasks[url.absoluteString] == nil, artwork(for: url) == nil else { return }
        artworkTasks[url.absoluteString] = Task { @MainActor [weak self] in
            defer { self?.artworkTasks.removeValue(forKey: url.absoluteString) }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      data.count < 5_000_000 else { return }
                if let self { try? data.write(to: self.artworkURL(url), options: .atomic) }
            } catch { /* Cached metadata remains usable without artwork. */ }
        }
    }

    func prepare() {
        guard !prepared else { return }
        prepared = true
        session.getAllTasks { [weak self] allTasks in
            DispatchQueue.main.async {
                guard let self else { return }
                for task in allTasks {
                    guard task.state != .completed, task.state != .canceling else { continue }
                    guard let id = task.taskDescription, self.state.pendingDownloads.contains(id),
                          let download = task as? URLSessionDownloadTask else { task.cancel(); continue }
                    self.tasks[id] = download
                    self.progress[id] = 0
                    if task.state == .suspended { task.resume() }
                }
                self.restored = true
                for id in self.state.pendingDownloads where self.tasks[id] == nil {
                    if let episode = self.state.episodes[id] { self.startDownload(episode) }
                }
            }
        }
    }
    func download(_ episode: PodcastEpisode) {
        guard localURL(episode.id) == nil, !state.pendingDownloads.contains(episode.id) else { return }
        remember(episode)
        state.pendingDownloads.insert(episode.id)
        progress[episode.id] = 0
        flush()
        prepare()
        if restored { startDownload(episode) }
    }
    private func startDownload(_ episode: PodcastEpisode) {
        guard tasks[episode.id] == nil else { return }
        let task = session.downloadTask(with: episode.audioURL)
        task.taskDescription = episode.id
        tasks[episode.id] = task
        task.resume()
    }
    func cancelDownload(_ episode: PodcastEpisode) {
        state.pendingDownloads.remove(episode.id)
        tasks.removeValue(forKey: episode.id)?.cancel()
        progress.removeValue(forKey: episode.id)
        flush()
    }
    func removeDownload(_ episode: PodcastEpisode) {
        guard let url = localURL(episode.id) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            state.downloads.removeValue(forKey: episode.id)
            persist()
        } catch { errorKey = "podcasts_storage_error" }
    }
    func handleBackgroundEvents(completion: @escaping () -> Void) {
        backgroundCompletion = completion
        prepare()
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription, tasks[id]?.taskIdentifier == downloadTask.taskIdentifier else { return }
        progress[id] = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription, state.pendingDownloads.contains(id),
              tasks[id] == nil || tasks[id]?.taskIdentifier == downloadTask.taskIdentifier,
              let episode = state.episodes[id] else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200...299).contains(response.statusCode),
                  response.mimeType?.hasPrefix("text/") != true,
                  ((try location.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0) > 0 else {
                throw PodcastNetworkError.invalidResponse
            }
            let ext = episode.audioURL.pathExtension.lowercased()
            let file = episode.fileKey + "." + (["mp3", "m4a", "aac", "mp4", "wav"].contains(ext) ? ext : "mp3")
            let destination = directory.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: location, to: destination)
            var excluded = destination
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? excluded.setResourceValues(values)
            state.downloads[id] = file
        } catch { errorKey = "podcasts_download_error" }
        state.pendingDownloads.remove(id)
        progress.removeValue(forKey: id)
        flush()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription,
              tasks[id] == nil || tasks[id]?.taskIdentifier == task.taskIdentifier else { return }
        tasks.removeValue(forKey: id)
        progress.removeValue(forKey: id)
        if let error, (error as NSError).code != NSURLErrorCancelled { errorKey = "podcasts_download_error" }
        state.pendingDownloads.remove(id)
        flush()
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        flush()
        let completion = backgroundCompletion
        backgroundCompletion = nil
        completion?()
    }
    private func persist() {
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    func flush() {
        flushWork?.cancel()
        do { try JSONEncoder().encode(state).write(to: stateURL, options: .atomic) }
        catch { errorKey = "podcasts_storage_error" }
    }
}
