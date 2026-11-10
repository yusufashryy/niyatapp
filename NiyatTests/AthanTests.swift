import AVFoundation
import XCTest
@testable import Niyat

final class AthanTests: XCTestCase {

    // MARK: The recordings

    func testSixMuezzins() {
        XCTAssertEqual(Muezzin.allCases.count, 6)
        XCTAssertEqual(Set(Muezzin.allCases.map(\.alertSoundName)).count, 6)
    }

    func testEveryAlertSoundIsBundledAndUnderThirtySeconds() throws {
        // iOS plays the default sound instead of one longer than 30 seconds.
        for muezzin in Muezzin.allCases {
            let name = (muezzin.alertSoundName as NSString).deletingPathExtension
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "caf"), "\(muezzin) is missing")
            let file = try AVAudioFile(forReading: url)
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            XCTAssertLessThan(seconds, 30, "\(muezzin)")
            XCTAssertGreaterThan(seconds, 8, "\(muezzin)")
        }
    }

    func testFullAthansSkipTheirIntros() {
        XCTAssertEqual(Muezzin.nafees.startOffset, 9.05, accuracy: 0.01)
        XCTAssertEqual(Muezzin.zahrani.startOffset, 0)
        for muezzin in Muezzin.allCases {
            XCTAssertEqual(muezzin.recordingURL.host, "cdn.aladhan.com")
        }
    }

    // MARK: Which alert plays which athan

    func testTheAthanPlaysWhenThePrayerBegins() {
        let settings = AthanSettings()
        XCTAssertEqual(settings.muezzin(for: .dhuhr, timing: .atTime), .alafasy)
    }

    func testRemindersBeforeAndAfterKeepTheStandardSound() {
        let settings = AthanSettings()
        XCTAssertNil(settings.muezzin(for: .dhuhr, timing: .before10))
        XCTAssertNil(settings.muezzin(for: .dhuhr, timing: .after30))
    }

    func testNoAthanAtSunrise() {
        XCTAssertNil(AthanSettings().muezzin(for: .sunrise, timing: .atTime))
    }

    func testFajrCanHaveItsOwnMuezzin() {
        var settings = AthanSettings()
        settings.fajrMuezzin = .nafees
        XCTAssertEqual(settings.muezzin(for: .fajr, timing: .atTime), .nafees)
        XCTAssertEqual(settings.muezzin(for: .isha, timing: .atTime), .alafasy)
    }

    func testStandardSoundTurnsTheAthanOff() {
        var settings = AthanSettings()
        settings.muezzin = nil
        settings.fajrMuezzin = .nafees
        XCTAssertNil(settings.muezzin(for: .maghrib, timing: .atTime))
        XCTAssertEqual(settings.muezzin(for: .fajr, timing: .atTime), .nafees, "Fajr's own choice still applies")
    }

    func testChoosingTheStandardSoundIsRemembered() throws {
        var settings = AthanSettings()
        settings.muezzin = nil
        let saved = try JSONEncoder().encode(settings)
        XCTAssertNil(try JSONDecoder().decode(AthanSettings.self, from: saved).muezzin)
    }

    func testOlderSettingsStillDecode() throws {
        let decoded = try JSONDecoder().decode(AthanSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, AthanSettings())
    }
}

final class AthanSegmentsTests: XCTestCase {
    /// Loud throughout, with a pause (quiet frames) at each given second.
    private func levels(seconds: Int, pausesAt: [Int]) -> [Float] {
        var levels = [Float](repeating: 0.5, count: seconds * 10)
        for pause in pausesAt { for i in (pause * 10)..<(pause * 10 + 6) where i < levels.count { levels[i] = 0.001 } }
        return levels
    }

    func testAShortAthanIsOnePart() {
        XCTAssertEqual(AthanSegments.parts(levels: levels(seconds: 20, pausesAt: [])), [20])
    }

    func testPartsAddUpAndStayUnderTheLimit() {
        let parts = AthanSegments.parts(levels: levels(seconds: 200, pausesAt: [22, 47, 70, 95, 120, 144, 170]))
        XCTAssertEqual(parts.reduce(0, +), 200, accuracy: 0.01)
        XCTAssertTrue(parts.allSatisfy { $0 <= AthanSegments.longestPart + 0.01 })
        XCTAssertTrue(parts.dropLast().allSatisfy { $0 >= AthanSegments.shortestPart - 0.01 })
    }

    func testCutsFallInThePauses() {
        let parts = AthanSegments.parts(levels: levels(seconds: 60, pausesAt: [22, 45]))
        XCTAssertEqual(parts[0], 22.3, accuracy: 0.31)
        XCTAssertEqual(parts[0] + parts[1], 45.3, accuracy: 0.31)
    }

    func testFollowUpsStartWhereThePartBeforeEnds() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let followUps = AthanSegments.followUps(start: start, parts: [22, 25, 18])
        XCTAssertEqual(followUps.map(\.index), [1, 2])
        XCTAssertEqual(followUps[0].date, start.addingTimeInterval(22))
        XCTAssertEqual(followUps[1].date, start.addingTimeInterval(47))
    }

    func testOldSettingsLoadWithTheWholeAthanOff() throws {
        let settings = try JSONDecoder().decode(AthanSettings.self, from: Data(#"{"muezzin":"alafasy"}"#.utf8))
        XCTAssertFalse(settings.fullAthanFromAlert)
    }

    func testEveryPartOfOnePrayerSharesItsPrefix() {
        let prefix = AthanSegments.followUpPrefix(prayer: .fajr, dayKey: "2026-11-09")
        for part in [1, 9, 10, 15, 16, 30] {
            XCTAssertTrue(AthanSegments.followUpIdentifier(prayer: .fajr, dayKey: "2026-11-09", part: part).hasPrefix(prefix))
        }
        XCTAssertFalse(AthanSegments.followUpIdentifier(prayer: .dhuhr, dayKey: "2026-11-09", part: 1).hasPrefix(prefix))
        XCTAssertFalse(AthanSegments.followUpIdentifier(prayer: .fajr, dayKey: "2026-11-10", part: 1).hasPrefix(prefix))
    }
}
