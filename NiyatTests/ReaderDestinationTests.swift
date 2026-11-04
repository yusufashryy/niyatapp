import XCTest
@testable import Niyat

/// The open surah is kept in scene storage as text, so it survives folding
/// and unfolding an iPhone Duo (and the app being closed in the background).
final class ReaderDestinationTests: XCTestCase {
    func testSurahAndVerseRoundTrip() {
        let open = ReaderDestination(surah: 18, verse: 16)
        XCTAssertEqual(open.storageKey, "18:16")
        XCTAssertEqual(ReaderDestination(storageKey: "18:16"), open)
    }

    func testSurahFromTheStart() {
        let open = ReaderDestination(surah: 2, verse: nil)
        XCTAssertEqual(open.storageKey, "2")
        XCTAssertEqual(ReaderDestination(storageKey: "2"), open)
    }

    func testNothingOpen() {
        XCTAssertNil(ReaderDestination(storageKey: ""))
    }

    func testBadValuesAreIgnored() {
        XCTAssertNil(ReaderDestination(storageKey: "abc"))
        XCTAssertNil(ReaderDestination(storageKey: "115"))
        XCTAssertNil(ReaderDestination(storageKey: "0:3"))
    }
}
