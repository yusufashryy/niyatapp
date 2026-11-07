import XCTest
import UIKit
@testable import Niyat

final class ReadingSignsTests: XCTestCase {
    @MainActor
    func testEveryHafsSignBelongsToAnExistingWord() async {
        let store = QuranStore.shared
        await store.load()
        let original = store.edition
        for edition in [QuranEdition.uthmani, .uthmaniMinimal, .imlaei] {
            await store.setEdition(edition)
            var counts: [String: Int] = [:]
            var checked = 0
            for surah in store.surahs {
                for verse in store.verses(for: surah.id) {
                    let words = QuranWords.shared.words(for: verse, edition: edition)
                    XCTAssertEqual(words.text, verse.arabic)
                    for (index, signs) in words.readingSigns {
                        XCTAssertTrue(words.words.indices.contains(index), "\(edition) \(surah.id):\(verse.number) word \(index)")
                        for sign in signs.unicodeScalars { counts[String(sign), default: 0] += 1 }
                    }
                    checked += 1
                }
            }
            XCTAssertEqual(checked, 6236)
            XCTAssertEqual(counts, ["ۖ": 1682, "ۗ": 603, "ۘ": 22, "ۙ": 68, "ۚ": 1972, "ۛ": 12, "ۜ": 5, "۩": 15])
        }
        await store.setEdition(original)
    }

    @MainActor
    func testReadingSignsAreDrawn() {
        let text = "لَا رَيْبَ فِيهِ"
        let plain = VerseWords(surah: 2, verse: 2, text: text)
        let marked = VerseWords(surah: 2, verse: 2, text: text, readingSigns: [1: "ۛ", 2: "ۛ۩"])
        func render(_ words: VerseWords) -> UIImage {
            let canvas = QuranTextCanvas(frame: CGRect(x: 0, y: 0, width: 380, height: 60))
            var style = QuranTextStyle()
            style.fontSize = 40
            style.ink = .black
            canvas.configure(pieces: [QuranTextPiece(verse: words)], style: style, layout: .centredLine)
            return UIGraphicsImageRenderer(size: canvas.bounds.size).image { context in
                UIColor.white.setFill()
                context.fill(canvas.bounds)
                canvas.draw(canvas.bounds)
            }
        }
        let image = render(marked)
        XCTAssertNotEqual(render(plain).pngData(), image.pngData())
        let attachment = XCTAttachment(image: image)
        attachment.name = "Waqf and sajdah rendering"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPairedPauseAndSajdahLocations() {
        XCTAssertEqual(QuranReadingSigns.signs(surah: 2, verse: 2, edition: .uthmani), [3: "ۛ", 4: "ۛ"])
        XCTAssertEqual(QuranReadingSigns.signs(surah: 96, verse: 19, edition: .uthmani)[4], "۩")
        XCTAssertTrue(QuranReadingSigns.signs(surah: 2, verse: 2, edition: .warsh).isEmpty)
        XCTAssertTrue(QuranReadingSigns.signs(surah: 2, verse: 2, edition: .qalun).isEmpty)
    }
}
