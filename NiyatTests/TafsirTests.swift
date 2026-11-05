import XCTest
@testable import Niyat

final class TafsirTests: XCTestCase {
    private func load(_ book: TafsirBook) throws -> TafsirIndex {
        let url = try XCTUnwrap(Bundle.main.url(forResource: book.rawValue, withExtension: "tafsir"), "\(book) is bundled")
        return TafsirIndex(try TafsirFile.decode(compressed: Data(contentsOf: url)))
    }

    /// Verses per surah, from the bundled chapters.json.
    private static let verseCounts: [Int] = {
        guard let url = Bundle.main.url(forResource: "chapters", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(Chapters.self, from: data) else { return [] }
        return file.chapters.sorted { $0.id < $1.id }.map(\.totalVerses)
    }()

    private struct Chapters: Decodable { let chapters: [Surah] }

    func testVerseCountsLoaded() {
        XCTAssertEqual(Self.verseCounts.count, 114)
        XCTAssertEqual(Self.verseCounts.reduce(0, +), 6236)
    }

    private func covered(_ index: TafsirIndex) -> (covered: Int, missing: [String]) {
        var count = 0, missing: [String] = []
        for (i, verses) in Self.verseCounts.enumerated() {
            for ayah in 1...verses {
                if index.entry(surah: i + 1, ayah: ayah) != nil { count += 1 } else { missing.append("\(i + 1):\(ayah)") }
            }
        }
        return (count, missing)
    }

    func testJalalaynCoversEveryAyahButTheFatihasBasmala() throws {
        let index = try load(.jalalayn)
        XCTAssertEqual(index.file.id, "jalalayn")
        let result = covered(index)
        XCTAssertEqual(result.covered, 6235)
        XCTAssertEqual(result.missing, ["1:1"])
        XCTAssertNotNil(index.entry(surah: 114, ayah: 6))
    }

    func testIbnKathirCoversEveryAyah() throws {
        let index = try load(.ibnKathir)
        XCTAssertEqual(index.file.id, "ibn-kathir")
        XCTAssertEqual(covered(index).covered, 6236)
    }

    func testEntriesDontOverlapAndStayInTheirSurah() throws {
        for book in TafsirBook.allCases {
            let entries = try load(book).file.entries
            for (a, b) in zip(entries, entries.dropFirst()) where a.surah == b.surah {
                XCTAssertLessThan(a.to, b.from, "\(book) \(a.surah):\(a.from)")
            }
            for entry in entries {
                XCTAssertLessThanOrEqual(entry.from, entry.to)
                XCTAssertLessThanOrEqual(entry.to, Self.verseCounts[entry.surah - 1])
                XCTAssertFalse(entry.text.isEmpty)
            }
        }
    }

    /// The modern editor's footnotes, their markers and his introduction are left out.
    func testIbnKathirHasNoEditorMaterial() throws {
        let entries = try load(.ibnKathir).file.entries
        let marker = try NSRegularExpression(pattern: "\\(\\s*[٠-٩]+\\s*\\)")
        for entry in entries {
            let range = NSRange(entry.text.startIndex..., in: entry.text)
            XCTAssertNil(marker.firstMatch(in: entry.text, range: range), "footnote marker in \(entry.surah):\(entry.from)")
            XCTAssertFalse(entry.text.contains("مقدمة التحقيق"))
            XCTAssertFalse(entry.text.contains("<"), "markup left in \(entry.surah):\(entry.from)")
        }
    }

    func testLookupFindsTheEntryThatCoversARange() {
        let file = TafsirIndexFixture.file(entries: [(2, 1, 5), (2, 6, 7), (2, 8, 8)])
        let index = TafsirIndex(file)
        XCTAssertEqual(index.entry(surah: 2, ayah: 3)?.from, 1)
        XCTAssertEqual(index.entry(surah: 2, ayah: 7)?.from, 6)
        XCTAssertEqual(index.entry(surah: 2, ayah: 8)?.from, 8)
        XCTAssertNil(index.entry(surah: 2, ayah: 9))
        XCTAssertNil(index.entry(surah: 3, ayah: 1))
        XCTAssertTrue(index.entry(surah: 2, ayah: 3)?.isRange == true)
    }
}

private enum TafsirIndexFixture {
    static func file(entries: [(Int, Int, Int)]) -> TafsirFile {
        let rows = entries.map { "[\($0.0),\($0.1),\($0.2),\"text\"]" }.joined(separator: ",")
        let json = "{\"id\":\"t\",\"name\":\"n\",\"nameEnglish\":\"n\",\"author\":\"a\",\"edition\":\"e\",\"version\":\"v\",\"entries\":[\(rows)]}"
        return try! JSONDecoder().decode(TafsirFile.self, from: Data(json.utf8))
    }
}
