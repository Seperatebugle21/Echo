import Foundation
import Observation

/// Taste AI: a language model that reasons over aggregated listening insights to curate
/// recommendations and the queue. `RecommendationManager` stays the fast offline candidate
/// generator and the fallback whenever the model is unavailable, slow or returns invalid output.
@MainActor @Observable final class TasteAIManager {
    static let shared = TasteAIManager()
    static let enabledKey = "echo.taste.enabled.v1"

    enum Status: Equatable { case idle, analyzing, curating, failed(String) }

    private(set) var profile = TasteProfile()
    private(set) var status: Status = .idle
    /// Home "For you, now" picks with the model's personal reason per song.
    private(set) var homePicks: [Song] = []
    private(set) var reasons: [UUID: String] = [:]
    /// Songs in the upcoming queue that were placed there by the curator.
    private(set) var curatedQueueIDs: Set<UUID> = []
    private(set) var lastCurationUsedAI = false
    private(set) var homeGeneratedAt: Date?
    var storageError: String?

    @ObservationIgnored private var skipMonitor = TasteSkipMonitor()
    @ObservationIgnored private var queueIntent: String?
    @ObservationIgnored private var busy = false
    private let directory: URL

    var enabled: Bool = UserDefaults.standard.bool(forKey: TasteAIManager.enabledKey) {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if !enabled { stopCuratedQueue(); homePicks = []; homeGeneratedAt = nil }
        }
    }
    /// Taste AI needs Echo Intelligence itself to be enabled; it reuses its provider and privacy settings.
    var active: Bool { enabled && UserDefaults.standard.bool(forKey: AISettingsStore.enabledKey) }
    var queueIsCurated: Bool { !curatedQueueIDs.isEmpty }

    private var library: MusicLibraryManager { .shared }
    private var player: AudioPlayerManager { .shared }
    private var learning: RecommendationManager { .shared }
    private var language: String { UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en" }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Intelligence")
        load()
    }

    // MARK: - Profile

    func refreshProfileIfNeeded() async {
        guard active, profile.needsRefresh(now: Date()) else { return }
        await refreshProfile()
    }

    /// Builds aggregated signals locally, then lets the model formulate personal insights.
    func refreshProfile() async {
        guard active, !busy else { return }
        let signals = TasteSignals.build(events: learning.listeningEvents, songs: library.songs, favorites: Set(library.favoriteSongIDs))
        guard signals.hasEnoughData else { status = .failed(EchoLocalization.string("taste_not_enough_data")); return }
        busy = true; status = .analyzing
        defer { busy = false }
        do {
            let text = try await ask(instructions: TastePrompt.profileInstructions(language: language),
                                     prompt: TastePrompt.profilePrompt(signals: signals, corrections: profile.corrections, previousSummary: profile.summary),
                                     timeout: 60)
            guard let parsed = TasteResponseParser.profile(from: text) else { throw AIError.response }
            profile.apply(summary: parsed.summary, insights: parsed.insights, at: Date())
            persist(); status = .idle
        } catch is CancellationError { status = .idle }
        catch { status = .failed(error.localizedDescription) }
    }

    func forget(_ insight: TasteInsight) {
        guard profile.forget(insight.id) else { return }
        persist()
    }
    func clearProfile() {
        profile = TasteProfile(); homePicks = []; reasons = [:]; curatedQueueIDs = []; homeGeneratedAt = nil
        persist()
    }

    // MARK: - Curation

    struct Curation { var songs: [Song]; var reasons: [UUID: String]; var usedAI: Bool }

    /// Engine ranks candidates fast and offline; the model chooses and orders from them.
    /// Invalid, missing or late output falls back to the engine order, never to invented songs.
    func curate(intent: String? = nil, count: Int = 20, excluding: Set<UUID> = []) async -> Curation {
        let playable = library.songs.filter { song in
            guard song.podcastEpisodeID == nil, !excluding.contains(song.id), song.id != player.currentSong?.id,
                  let url = player.getURL(for: song) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
        guard !playable.isEmpty else { return Curation(songs: [], reasons: [:], usedAI: false) }
        let filtered = intent.map { term in playable.filter { AIDJSelection.admits($0, query: term, excluded: [], selectedIDs: []) } } ?? []
        // A free-form wish like "calmer" rarely matches metadata; then the model interprets it over the full pool.
        let pool = filtered.count >= max(5, count / 2) ? filtered : playable
        let providerID = try? AIProviderManager.resolve(AISettingsStore.shared.value).id
        let local = providerID == nil || providerID == .apple || providerID == .qwen
        let ranked = learning.recommendations(from: pool, favoriteSongIDs: library.favoriteSongIDs, limit: pool.count)
        // Small on-device models get a shorter list and fewer picks to stay inside their context.
        let candidateLimit = local ? 40 : 100
        let fresh = AIDJSelection.preferUnplayed(ranked, recent: recentlyStarted, current: player.currentSong?.id, limit: candidateLimit)
        let engineOrder = Array(fresh.prefix(count))
        guard active else { return Curation(songs: engineOrder, reasons: [:], usedAI: false) }

        let favorites = Set(library.favoriteSongIDs)
        let candidates = fresh.map { song in
            TasteCandidate(song: song, plays: learning.learningData[song.id]?.playCount ?? 0,
                           skips: learning.learningData[song.id]?.skipCount ?? 0, favorite: favorites.contains(song.id))
        }
        let picksWanted = min(count, local ? 12 : count)
        busy = true; status = .curating
        defer { busy = false }
        do {
            let text = try await ask(instructions: TastePrompt.curatorInstructions(language: language, count: picksWanted),
                                     prompt: TastePrompt.curatorPrompt(profile: profile, context: momentContext(request: intent), candidates: candidates),
                                     timeout: local ? 25 : 20)
            let picks = TasteResponseParser.picks(from: text, candidates: Set(fresh.map(\.id)), limit: picksWanted)
            guard !picks.isEmpty else { throw AIError.response }
            let indexed = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })
            let ids = TasteQueueBuilder.merge(picks: picks.map(\.id), engine: engineOrder.map(\.id), current: player.currentSong?.id, limit: count)
            status = .idle
            return Curation(songs: ids.compactMap { indexed[$0] },
                            reasons: Dictionary(picks.filter { !$0.reason.isEmpty }.map { ($0.id, $0.reason) }, uniquingKeysWith: { first, _ in first }),
                            usedAI: true)
        } catch is CancellationError {
            status = .idle
        } catch {
            status = .failed(error.localizedDescription)
        }
        return Curation(songs: engineOrder, reasons: [:], usedAI: false)
    }

    /// Home section: refreshed at most every 45 minutes, or when the daypart changes.
    func refreshHomeIfNeeded(force: Bool = false) async {
        guard active, !busy else { return }
        let now = Date()
        if !force, let generated = homeGeneratedAt, now.timeIntervalSince(generated) < 45 * 60,
           TasteDaypart(hour: Calendar.current.component(.hour, from: generated)) == TasteDaypart(hour: Calendar.current.component(.hour, from: now)),
           !homePicks.isEmpty { return }
        await refreshProfileIfNeeded()
        let result = await curate(count: 12)
        homePicks = result.songs; reasons.merge(result.reasons) { _, new in new }
        lastCurationUsedAI = result.usedAI; homeGeneratedAt = now
    }

    /// Replaces upcoming songs with a curated arc without restarting the current song.
    @discardableResult func curateQueue(intent: String? = nil, startNow: Bool = false) async -> Curation {
        queueIntent = intent.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let result = await curate(intent: queueIntent, count: 25)
        guard !result.songs.isEmpty else { return result }
        reasons.merge(result.reasons) { _, new in new }
        lastCurationUsedAI = result.usedAI
        player.stopEchoFlow()
        if startNow || player.currentSong == nil, let first = result.songs.first, let url = player.getURL(for: first) {
            player.setShuffle(false)
            player.play(song: first, url: url, queue: result.songs)
        } else {
            player.replaceIntelligenceUpcoming(result.songs)
        }
        curatedQueueIDs = Set(result.songs.map(\.id))
        skipMonitor.curated()
        return result
    }
    func stopCuratedQueue() { curatedQueueIDs = []; queueIntent = nil; skipMonitor.curated() }

    func reason(for id: UUID) -> String? { reasons[id] }

    // MARK: - Session awareness

    /// Called for every finished music track. Repeated skips or a nearly empty curated queue trigger re-curation.
    func playbackEnded(_ reason: ListeningEndReason) {
        guard active, queueIsCurated else { return }
        // The user replaced the queue elsewhere: stop managing it.
        let upcoming = player.queue.dropFirst(max(0, player.currentIndex + 1))
        if !upcoming.isEmpty && !upcoming.contains(where: { curatedQueueIDs.contains($0.id) }) { stopCuratedQueue(); return }
        let moodChanged = skipMonitor.record(reason)
        let runningLow = upcoming.count < 4
        guard (moodChanged || runningLow), !busy else { return }
        Task { await self.curateQueue(intent: self.queueIntent) }
    }

    // MARK: - Tool support

    func explain(_ song: Song) -> [String: Any] {
        var result: [String: Any] = ["songID": song.id.uuidString, "title": song.title, "artist": song.artist,
                                     "plays": learning.learningData[song.id]?.playCount ?? 0,
                                     "skips": learning.learningData[song.id]?.skipCount ?? 0,
                                     "favorite": library.isFavorite(song)]
        if let reason = reasons[song.id] { result["curatorReason"] = reason }
        return result
    }
    var profileJSON: [String: Any] {
        ["enabled": active, "summary": profile.summary, "updatedAt": profile.updatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
         "insights": profile.insights.map { ["id": $0.id.uuidString, "text": $0.text, "evidence": $0.evidence] as [String: Any] },
         "queueCurated": queueIsCurated]
    }

    // MARK: - Private

    private var recentlyStarted: Set<UUID> {
        Set(learning.learningData.filter { ($0.value.lastStartedAt ?? .distantPast) > Date().addingTimeInterval(-3 * 3600) }.map(\.key))
    }
    private func momentContext(request: String?) -> TasteContext {
        let events = learning.listeningEvents.suffix(12)
        let describe: (ListeningEvent) -> String = { $0.title + " — " + $0.artist }
        return TasteContext(current: player.currentSong.map { $0.title + " — " + $0.artist },
                            recentlySkipped: events.filter { $0.reason == .skipped }.suffix(6).map(describe),
                            recentlyCompleted: events.filter { $0.reason == .completed }.suffix(6).map(describe),
                            request: request)
    }
    /// One text-only provider round with no tools: the model can only return data, never act.
    private func ask(instructions: String, prompt: String, timeout: Double) async throws -> String {
        let provider = try AIProviderManager.resolve(AISettingsStore.shared.value)
        let message = AIMessage(role: .user, text: prompt)
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { @MainActor in
                try await provider.respond(messages: [message], instructions: instructions, tools: [],
                                           update: { _ in }, execute: { _ in throw AIError.permission }).text
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw AIError.limit
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw AIError.response }
            return first
        }
    }
    private var file: URL { directory.appendingPathComponent("taste.json") }
    private func load() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { profile = try JSONDecoder().decode(TasteProfile.self, from: Data(contentsOf: file)) }
        catch { storageError = AIError.storage.localizedDescription }
    }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var url = directory, values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            try JSONEncoder().encode(profile).write(to: file, options: [.atomic, .completeFileProtection])
        } catch { storageError = AIError.storage.localizedDescription }
    }
}
