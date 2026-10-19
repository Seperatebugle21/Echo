import Foundation
import XCTest

final class EchoSleepTimerTests: XCTestCase {
    func testDeadlineExpiresWhilePlaybackIsPaused() {
        let now = Date(timeIntervalSince1970: 1_000)
        var timer = SleepTimerState()
        timer.start(minutes: 15, now: now)
        XCTAssertFalse(timer.isExpired(at: now.addingTimeInterval(899)))
        XCTAssertTrue(timer.isExpired(at: now.addingTimeInterval(900)))
        XCTAssertTrue(timer.isExpired(at: now.addingTimeInterval(3_600)))
    }

    func testChangingSelectionCancelsOnlyEndOfItem() {
        let first = UUID(), second = UUID()
        var timer = SleepTimerState()
        timer.endOfItem(first)
        timer.selectionChanged(to: first)
        XCTAssertTrue(timer.isActive)
        timer.selectionChanged(to: second)
        XCTAssertFalse(timer.isActive)
        timer.start(minutes: 30)
        let deadline = timer.deadline
        timer.selectionChanged(to: second)
        XCTAssertEqual(timer.deadline, deadline)
    }

    func testCompletionIsConsumedExactlyOnceBeforeRepeatOrAutoNext() {
        let song = UUID()
        var timer = SleepTimerState()
        timer.endOfItem(song)
        XCTAssertFalse(timer.consumeCompletion(of: UUID()))
        XCTAssertTrue(timer.consumeCompletion(of: song))
        XCTAssertFalse(timer.consumeCompletion(of: song))
        XCTAssertFalse(timer.isActive)
    }

    func testReplaceCancelAndClamp() {
        let now = Date(timeIntervalSince1970: 1_000)
        var timer = SleepTimerState()
        timer.start(minutes: 0, now: now)
        XCTAssertEqual(timer.deadline, now.addingTimeInterval(60))
        timer.start(minutes: Int.max, now: now)
        XCTAssertEqual(timer.deadline, now.addingTimeInterval(720 * 60))
        timer.endOfItem(UUID())
        XCTAssertNil(timer.deadline)
        timer.start(minutes: 20, now: now)
        XCTAssertNil(timer.songID)
        XCTAssertEqual(timer.deadline, now.addingTimeInterval(1_200))
        timer.cancel()
        XCTAssertFalse(timer.isActive)
        XCTAssertFalse(timer.isExpired(at: now.addingTimeInterval(86_400)))
    }
}
