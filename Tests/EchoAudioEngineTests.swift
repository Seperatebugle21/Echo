import AVFoundation
import XCTest

/// Live render-clock checks; run on an iOS Simulator or device.
@MainActor
final class EchoAudioEngineTests: XCTestCase {
    func testRepeatedPauseResumeKeepsPositionAndDoesNotRestartTheSong() async throws {
        let player = try EqualizedAudioPlayer(contentsOf: fixture(rate: 44100, channels: 1, seconds: 15))
        defer { player.stop() }
        var starts = 0
        player.onStarted = { _ in starts += 1 }
        player.play()
        try await until { player.isPlaying && player.currentTime > 0.4 }
        for _ in 0..<5 {
            player.pause()
            try await until { player.stateValue == .paused }
            let position = player.currentTime
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(player.currentTime, position, accuracy: 0.01)
            player.play()
            try await until { player.isPlaying && player.currentTime > position + 0.15 }
            XCTAssertNotEqual(player.stateValue, .failed)
            XCTAssertGreaterThanOrEqual(player.currentTime, position)
        }
        XCTAssertEqual(starts, 1)
    }
    func testStateCallbacksPublishLatestTransportCommandOnMainThread() async throws {
        let player = try EqualizedAudioPlayer(contentsOf: fixture(rate: 48000, channels: 2, seconds: 5))
        defer { player.stop() }
        var updates: [LocalPlaybackUpdate] = []
        player.onStateChanged = { update in
            XCTAssertTrue(Thread.isMainThread)
            updates.append(update)
        }
        _ = try await player.preparedDuration()
        player.play(intentRevision: 1)
        try await until { updates.contains { $0.intentRevision == 1 && $0.state == .playing } }
        player.pause(intentRevision: 2)
        player.play(intentRevision: 3)
        player.pause(intentRevision: 4)
        try await until { updates.last?.intentRevision == 4 && updates.last?.state == .paused }
        XCTAssertFalse(try XCTUnwrap(updates.last).wantsPlayback)
        let position = player.currentTime
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(player.currentTime, position, accuracy: 0.01)
        player.play(intentRevision: 5)
        try await until { updates.last?.intentRevision == 5 && updates.last?.state == .playing }
        try await until { player.currentTime > position + 0.01 }
        XCTAssertGreaterThan(player.currentTime, position)
    }
    func testQueuedPauseIsPreservedWhenImmediatelySeeking() async throws {
        let player = try EqualizedAudioPlayer(contentsOf: fixture(rate: 48000, channels: 2, seconds: 15))
        defer { player.stop() }
        // Measure pause/seek behavior after preparation. Fresh simulator audio
        // startup can take several seconds and must not exhaust the short file.
        _ = try await player.preparedDuration()
        player.play(intentRevision: 1)
        try await until({ player.isPlaying }, timeout: 10)
        player.pause(intentRevision: 2)
        player.currentTime = 2
        try await until { player.stateValue == .paused && abs(player.currentTime - 2) < 0.01 }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 2, accuracy: 0.01)
    }
    private final class FinishRecorder: EqualizedAudioPlayerDelegate {
        var finished = false
        @MainActor func audioPlayerDidFinishPlaying(_ player: EqualizedAudioPlayer, successfully flag: Bool) { finished = flag }
    }
    func testVeryShortFileHasOneRealStartAndCompletes() async throws {
        let player = try EqualizedAudioPlayer(contentsOf: fixture(rate: 48000, channels: 1, seconds: 0.02))
        defer { player.stop() }
        let recorder = FinishRecorder(); player.delegate = recorder
        var starts = 0; player.onStarted = { _ in starts += 1 }
        player.play(); try await until { recorder.finished }
        XCTAssertEqual(starts, 1); XCTAssertFalse(player.isPlaying)
    }
    private func fixture(rate: Double, channels: AVAudioChannelCount, seconds: Double = 2,
                         constant: Float? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * seconds)))
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(buffer.frameLength) {
                buffer.floatChannelData![channel][frame] = constant ?? (0.05 * sin(Float(frame) * 0.03))
            }
        }
        try file.write(from: buffer); addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    private func until(_ condition: () -> Bool, timeout: Double = 5,
                       file: StaticString = #filePath, line: UInt = #line) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "Timed out waiting for playback condition", file: file, line: line)
    }
    func testDurationPausedSeekAndReplacingDifferentFormats() async throws {
        let a = try fixture(rate: 44100, channels: 1), b = try fixture(rate: 48000, channels: 2)
        let player = try EqualizedAudioPlayer(contentsOf: a)
        defer { player.stop() }
        let first = try await player.preparedDuration(); XCTAssertEqual(first, 2, accuracy: 0.001)
        player.currentTime = 1
        try await until { abs(player.currentTime - 1) < 0.001 && player.stateValue == .paused }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(player.currentTime, 1, accuracy: 0.001); XCTAssertFalse(player.isPlaying)
        player.currentTime = -1; try await until { player.currentTime == 0 }
        try player.replace(with: b)
        let second = try await player.preparedDuration(); XCTAssertEqual(second, 2, accuracy: 0.001)
        XCTAssertFalse(player.isPlaying)
    }
    func testPreparedGaplessPromotesOnlyOnce() async throws {
        let a = try fixture(rate: 44100, channels: 1, seconds: 1), b = try fixture(rate: 48000, channels: 2, seconds: 1)
        let player = try EqualizedAudioPlayer(contentsOf: a), id = UUID()
        defer { player.stop() }
        var promotions = 0, starts = 0
        player.onStarted = { incoming in starts += 1; if incoming == nil { player.prepareNext(url: b, identifier: id, plan: AudioTransitionPlan()) } }
        player.onPromote = { incoming in XCTAssertEqual(incoming, id); promotions += 1 }
        player.play(); try await until { promotions == 1 }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(promotions, 1); XCTAssertEqual(starts, 2); XCTAssertNotEqual(player.stateValue, .failed)
    }
    func testPauseCompletionObservesStoppedPlayback() async throws {
        let player = try EqualizedAudioPlayer(contentsOf: fixture(rate: 48000, channels: 2, seconds: 5))
        defer { player.stop() }
        player.play()
        try await until { player.isPlaying && player.currentTime > 0.1 }
        var completed = false
        var pausedPosition = 0.0
        player.pause {
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(player.stateValue, .paused)
            XCTAssertFalse(player.isPlaying)
            pausedPosition = player.currentTime
            completed = true
        }
        try await until { completed }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(player.currentTime, pausedPosition, accuracy: 0.01)
        player.play()
        try await until { player.isPlaying && player.currentTime > pausedPosition + 0.1 }
    }
    func testRepeatedUpcomingChangesKeepTheCurrentRenderClockRunning() async throws {
        let current = try fixture(rate: 48000, channels: 2, seconds: 15)
        let next = try fixture(rate: 44100, channels: 1, seconds: 4)
        let player = try EqualizedAudioPlayer(contentsOf: current)
        defer { player.stop() }
        var starts = 0, promotions = 0
        player.onStarted = { _ in starts += 1 }
        player.onPromote = { _ in promotions += 1 }
        _ = try await player.preparedDuration()
        player.play()
        try await until({ player.isPlaying && starts == 1 }, timeout: 10)
        for _ in 0..<5 {
            player.prepareNext(url: next, identifier: UUID(), plan: AudioTransitionPlan(overlap: 1))
            try await until { player.stateValue == .transitioning }
            let position = player.currentTime
            var cancelled = false
            player.cancelPreparedNext { promoted in
                XCTAssertNil(promoted)
                XCTAssertEqual(player.stateValue, .playing)
                XCTAssertGreaterThanOrEqual(player.currentTime, position)
                cancelled = true
            }
            try await until { cancelled }
            try await until { player.currentTime > position + 0.1 }
        }
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(promotions, 0)
    }

    func testCancellingAfterPromotionKeepsTheAudibleIncomingSong() async throws {
        let current = try fixture(rate: 48000, channels: 2, seconds: 2)
        let next = try fixture(rate: 44100, channels: 1, seconds: 8)
        let player = try EqualizedAudioPlayer(contentsOf: current)
        defer { player.stop() }
        let id = UUID()
        var promoted = false
        player.onPromote = { _ in promoted = true }
        _ = try await player.preparedDuration()
        player.play()
        try await until({ player.isPlaying }, timeout: 10)
        player.prepareNext(url: next, identifier: id, plan: AudioTransitionPlan(overlap: 1))
        try await until { promoted }
        let position = player.currentTime
        var cancelled = false
        player.cancelPreparedNext { audible in
            XCTAssertEqual(audible, id)
            XCTAssertTrue(player.isPlaying)
            XCTAssertGreaterThanOrEqual(player.currentTime, position)
            cancelled = true
        }
        try await until { cancelled && player.currentTime > position + 0.1 }
        XCTAssertEqual(player.duration, 8, accuracy: 0.001)
    }

    func testCancellingTrimmedTransitionPreservesTheFullCurrentSongTail() async throws {
        let current = try fixture(rate: 48000, channels: 2, seconds: 6)
        let next = try fixture(rate: 44100, channels: 1, seconds: 8)
        let player = try EqualizedAudioPlayer(contentsOf: current)
        defer { player.stop() }
        let finished = FinishRecorder()
        player.delegate = finished
        _ = try await player.preparedDuration()
        player.play()
        try await until({ player.isPlaying }, timeout: 10)
        player.prepareNext(url: next, identifier: UUID(), plan: AudioTransitionPlan(outgoingTrim: 2))
        try await until { player.currentTime > 3.7 }
        player.cancelPreparedNext()
        try await until { finished.finished }
        XCTAssertEqual(player.duration, 6, accuracy: 0.001)
        XCTAssertEqual(player.currentTime, 6, accuracy: 0.001)
    }
    func testSeekWhilePlayingContinuesWithoutAnotherPlayCommand() async throws {
        let player = try EqualizedAudioPlayer(contentsOf: fixture(rate: 48000, channels: 2, seconds: 5))
        defer { player.stop() }
        var starts = 0
        player.onStarted = { _ in starts += 1 }
        player.play()
        try await until { player.isPlaying && starts == 1 }
        player.currentTime = 2
        try await until { player.isPlaying && player.currentTime > 2.1 }
        XCTAssertEqual(starts, 1)
    }
    func testVeryShortIncomingGaplessFileCompletesAfterPromotion() async throws {
        let a = try fixture(rate: 44100, channels: 1, seconds: 1), b = try fixture(rate: 48000, channels: 2, seconds: 0.02)
        let player = try EqualizedAudioPlayer(contentsOf: a), id = UUID()
        defer { player.stop() }
        let recorder = FinishRecorder(); player.delegate = recorder
        var promotions = 0, starts = 0
        player.onStarted = { incoming in starts += 1; if incoming == nil { player.prepareNext(url: b, identifier: id, plan: AudioTransitionPlan()) } }
        player.onPromote = { incoming in XCTAssertEqual(incoming, id); promotions += 1 }
        player.play(); try await until { recorder.finished }
        XCTAssertEqual(promotions, 1); XCTAssertEqual(starts, 2); XCTAssertFalse(player.isPlaying)
    }
    func testLatestReplacementAndSeekWinWithoutDuplicateStarts() async throws {
        let a = try fixture(rate: 44100, channels: 1, seconds: 3), b = try fixture(rate: 48000, channels: 2, seconds: 8)
        let player = try EqualizedAudioPlayer(contentsOf: a)
        defer { player.stop() }
        var starts = 0; player.onStarted = { _ in starts += 1 }
        for _ in 0..<20 { try player.replace(with: a); try player.replace(with: b) }
        player.play(); try await until { player.isPlaying && abs(player.duration - 8) < 0.01 && starts == 1 }
        player.pause(); try await until { player.stateValue == .paused }
        for offset in stride(from: 0.2, through: 2.2, by: 0.1) { player.currentTime = offset }
        try await until { abs(player.currentTime - 2.2) < 0.01 && player.stateValue == .paused }
        player.play(); try await until { player.isPlaying && player.currentTime > 2.3 }
        XCTAssertEqual(starts, 1)
    }
    func testCorruptFileDoesNotPreventNextSong() async throws {
        let corrupt = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        try Data("broken audio".utf8).write(to: corrupt); addTeardownBlock { try? FileManager.default.removeItem(at: corrupt) }
        let player = try EqualizedAudioPlayer(contentsOf: corrupt)
        defer { player.stop() }
        // Core Audio initializes decoder plugins on the first open on a fresh simulator.
        player.play(); try await until({ player.stateValue == .failed }, timeout: 30); XCTAssertFalse(player.isPlaying)
        try player.replace(with: fixture(rate: 44100, channels: 2)); player.play()
        try await until { player.isPlaying }
    }
    #if DEBUG
    private final class RenderedAudio: @unchecked Sendable {
        private let lock = NSLock()
        private var afterHostTime: UInt64 = 0
        private var beforeHostTime: UInt64 = .max
        private var values: [Float] = []
        func receive(_ samples: [Float], hostTime: UInt64) {
            lock.lock(); defer { lock.unlock() }
            guard hostTime >= afterHostTime, hostTime < beforeHostTime, values.count < 100_000 else { return }
            values.append(contentsOf: samples.filter { abs($0) > 0.001 })
        }
        func begin(windowSeconds: TimeInterval? = nil) {
            lock.lock(); defer { lock.unlock() }
            afterHostTime = AVAudioTime.hostTime(forSeconds: ProcessInfo.processInfo.systemUptime)
            beforeHostTime = windowSeconds.map { afterHostTime + AVAudioTime.hostTime(forSeconds: $0) } ?? .max
            values = []
        }
        var samples: [Float] { lock.lock(); defer { lock.unlock() }; return values }
    }

    func testResumeRendersNoOldAudioWhileWaitingForFreshBuffers() async throws {
        let player = try EqualizedAudioPlayer(contentsOf: fixture(rate: 48000, channels: 2, seconds: 15, constant: 0.08))
        defer { player.stop() }
        let audio = RenderedAudio()
        player.captureRenderedAudio { audio.receive($0, hostTime: $1) }
        _ = try await player.preparedDuration()
        player.play()
        try await until({ player.isPlaying && !audio.samples.isEmpty }, timeout: 10)
        player.pause()
        try await until { player.stateValue == .paused }
        audio.begin(windowSeconds: 0.3)
        player.injectDecodeDelay(afterBuffers: 1, seconds: 0.5)
        player.play()
        try await until({ player.isPlaying }, timeout: 10)
        XCTAssertTrue(audio.samples.isEmpty, "Old mixer audio was rendered before resume buffers were ready")
        audio.begin()
        try await until({ player.isPlaying && !audio.samples.isEmpty }, timeout: 10)
        XCTAssertGreaterThan(try XCTUnwrap(audio.samples.first), 0)
    }

    func testReplacingPausedSongRendersOnlyTheSelectedSongsAudio() async throws {
        let first = try fixture(rate: 48000, channels: 2, seconds: 15, constant: 0.08)
        let second = try fixture(rate: 48000, channels: 2, seconds: 15, constant: -0.08)
        let player = try EqualizedAudioPlayer(contentsOf: first)
        defer { player.stop() }
        let audio = RenderedAudio()
        player.captureRenderedAudio { audio.receive($0, hostTime: $1) }
        _ = try await player.preparedDuration()
        player.play()
        try await until({ player.isPlaying && !audio.samples.isEmpty }, timeout: 10)
        player.pause()
        try await until { player.stateValue == .paused }
        audio.begin()
        try player.replace(with: second)
        player.injectDecodeDelay(afterBuffers: 1, seconds: 0.5)
        player.play()
        try await until({ player.isPlaying && player.currentTime > 0.2 && !audio.samples.isEmpty }, timeout: 10)
        XCTAssertLessThan(try XCTUnwrap(audio.samples.max()), 0, "The previous song leaked into the selected song")
    }

    func testResumePrimesDelayedAudioBeforeStartingAtNormalSpeed() async throws {
        let player = try EqualizedAudioPlayer(contentsOf: fixture(rate: 48000, channels: 2, seconds: 15))
        defer { player.stop() }
        _ = try await player.preparedDuration()
        player.play()
        try await until({ player.isPlaying && player.currentTime > 0.2 }, timeout: 10)
        player.pause()
        try await until { player.stateValue == .paused }
        let pausedPosition = player.currentTime
        var resumeLatency: Double?
        player.onFirstRender = { resumeLatency = $0 }
        // A late second buffer must not produce a brief burst of audio followed
        // by an underrun. Resume starts after the initial queue is ready.
        player.injectDecodeDelay(afterBuffers: 1, seconds: 0.4)
        player.play()
        try await until({ player.isPlaying && resumeLatency != nil }, timeout: 10)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(resumeLatency), 0.35)
        XCTAssertGreaterThanOrEqual(player.currentTime, pausedPosition)
        let startPosition = player.currentTime
        let startTime = Date()
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(player.currentTime - startPosition, Date().timeIntervalSince(startTime), accuracy: 0.2)
        XCTAssertEqual(player.stateValue, .playing)
    }
    func testTemporaryConverterStarvationIsNotEndOfTrack() async throws {
        let player = try EqualizedAudioPlayer(contentsOf: fixture(rate: 22050, channels: 1, seconds: 4))
        defer { player.stop() }
        _ = try await player.preparedDuration(); player.injectTemporaryEmptyBuffers(8)
        var starts = 0; player.onStarted = { _ in starts += 1 }
        player.play(); try await until { player.isPlaying && player.currentTime > 0.2 }
        XCTAssertEqual(starts, 1); XCTAssertNotEqual(player.stateValue, .failed)
    }
    func testStallRecoversOnceThenFailsAndAcceptsNewSong() async throws {
        let url = try fixture(rate: 48000, channels: 2, seconds: 15)
        let player = try EqualizedAudioPlayer(contentsOf: url)
        defer { player.stop() }
        var starts = 0; player.onStarted = { _ in starts += 1 }
        player.play(); try await until { player.isPlaying && player.currentTime > 0.2 }
        let before = player.currentTime; player.injectEngineStall()
        try await until({ player.currentTime > before + 0.3 }, timeout: 8); XCTAssertEqual(starts, 1)
        player.injectEngineStall(); try await until({ player.stateValue == .failed }, timeout: 8)
        XCTAssertFalse(player.isPlaying)
        try player.replace(with: url); player.play(); try await until { player.isPlaying && starts == 2 }
    }
    #endif
}
