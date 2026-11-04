import XCTest
@testable import Niyat

final class ReadingRibbonTests: XCTestCase {
    private let baqarah = VerseReference(surah: 2, verse: 255)
    private let kahf = VerseReference(surah: 18, verse: 1)

    // MARK: Where the ribbon starts

    func testSavedRibbonWins() {
        XCTAssertEqual(ReadingRibbon.initial(saved: kahf, legacy: baqarah), kahf)
    }

    func testOldReadingPositionBecomesTheRibbon() {
        XCTAssertEqual(ReadingRibbon.initial(saved: nil, legacy: baqarah), baqarah)
    }

    func testNoRibbonOnAFreshInstall() {
        XCTAssertNil(ReadingRibbon.initial(saved: nil, legacy: nil))
    }

    // MARK: When it moves

    func testMovesWhenYouStayOnAPlaceYouScrolledTo() {
        XCTAssertTrue(ReadingRibbon.shouldMove(follows: true, movedByReader: true))
    }

    func testJumpsDoNotMoveIt() {
        // Search, the juz list, duas and following a recitation are jumps.
        XCTAssertFalse(ReadingRibbon.shouldMove(follows: true, movedByReader: false))
    }

    func testNeverMovesByItselfWhenTheSettingIsOff() {
        XCTAssertFalse(ReadingRibbon.shouldMove(follows: false, movedByReader: true))
    }

    // MARK: Closing the mushaf with the setting off

    func testOffersToMoveItWhenYouCloseOnAnotherPage() {
        XCTAssertEqual(ReadingRibbon.pageToOffer(follows: false, ribbonPage: 12, currentPage: 245), 245)
    }

    func testNothingToAskWhenTheRibbonIsAlreadyOnThisPage() {
        XCTAssertNil(ReadingRibbon.pageToOffer(follows: false, ribbonPage: 245, currentPage: 245))
    }

    func testNothingToAskWhenTheRibbonMovesByItself() {
        XCTAssertNil(ReadingRibbon.pageToOffer(follows: true, ribbonPage: 12, currentPage: 245))
    }

    func testOffersAFirstRibbon() {
        XCTAssertEqual(ReadingRibbon.pageToOffer(follows: false, ribbonPage: nil, currentPage: 3), 3)
    }

    // MARK: How long a mushaf page must stay open

    func testShortPagesWaitAtLeastFourSeconds() {
        XCTAssertEqual(ReadingRibbon.pageDwell(verseCount: 1), 4)
    }

    func testDwellGrowsWithTheVerses() {
        XCTAssertEqual(ReadingRibbon.pageDwell(verseCount: 8), 12)
    }

    func testLongPagesWaitAtMostTwentySeconds() {
        XCTAssertEqual(ReadingRibbon.pageDwell(verseCount: 40), 20)
    }

    // MARK: A ribbon placed by hand

    private let here = VerseReference(surah: 2, verse: 50)

    func testFollowsAnywhereWhenNotPlacedByHand() {
        XCTAssertTrue(ReadingRibbon.follows(to: VerseReference(surah: 2, verse: 10), from: here, pinned: false))
        XCTAssertTrue(ReadingRibbon.follows(to: VerseReference(surah: 2, verse: 90), from: here, pinned: false))
    }

    func testPlacedByHandStaysWhileLookingBack() {
        XCTAssertFalse(ReadingRibbon.follows(to: VerseReference(surah: 2, verse: 10), from: here, pinned: true))
        XCTAssertFalse(ReadingRibbon.follows(to: VerseReference(surah: 1, verse: 7), from: here, pinned: true))
    }

    func testPlacedByHandFollowsOnceYouReadPastIt() {
        XCTAssertTrue(ReadingRibbon.follows(to: VerseReference(surah: 2, verse: 51), from: here, pinned: true))
        XCTAssertTrue(ReadingRibbon.follows(to: VerseReference(surah: 3, verse: 1), from: here, pinned: true))
    }

    func testNoRibbonYetFollows() {
        XCTAssertTrue(ReadingRibbon.follows(to: here, from: nil, pinned: false))
        XCTAssertFalse(ReadingRibbon.follows(to: here, from: here, pinned: false))
    }
}
