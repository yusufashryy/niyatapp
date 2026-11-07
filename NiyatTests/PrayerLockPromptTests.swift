import XCTest
@testable import Niyat

final class PrayerLockPromptTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAsksDuringALock() {
        XCTAssertTrue(PrayerLockPrompt.shouldShow(lockedUntil: now.addingTimeInterval(600), snoozedUntil: nil, now: now))
    }

    func testDoesntAskWithoutALock() {
        XCTAssertFalse(PrayerLockPrompt.shouldShow(lockedUntil: nil, snoozedUntil: nil, now: now))
        XCTAssertFalse(PrayerLockPrompt.shouldShow(lockedUntil: now.addingTimeInterval(-1), snoozedUntil: nil, now: now))
    }

    func testNotYetWaitsAFewMinutes() {
        let until = now.addingTimeInterval(1200)
        XCTAssertFalse(PrayerLockPrompt.shouldShow(lockedUntil: until, snoozedUntil: now.addingTimeInterval(60), now: now))
        XCTAssertTrue(PrayerLockPrompt.shouldShow(lockedUntil: until, snoozedUntil: now.addingTimeInterval(-1), now: now))
    }
}
