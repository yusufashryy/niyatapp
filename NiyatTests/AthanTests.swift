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
