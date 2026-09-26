import SwiftUI

/// What one mushaf page shows: its 15 lines (8 on the first two pages),
/// built from the Madinah line layout and the verified text. Lines only point
/// at words of the bundled Tanzil text; nothing is retyped.
@MainActor
struct MushafPageText {
    enum Row {
        case header(surah: Int)
        case basmala(QuranTextPiece)
        case text([QuranTextPiece])
        /// Kept so the page keeps its shape if a line can't be built.
        case empty
    }

    let number: Int
    let rows: [Row]
    /// Natural width of each row's text at font size 1 (0 for other rows).
    let widths: [CGFloat]
    /// The surah most of the page belongs to.
    let surah: Int
    /// The juz (part) the page starts in.
    let juz: Int
    /// Every verse with words on the page, in order.
    let verses: [VerseKey]

    /// The opening pages (Al-Fatiha, the start of Al-Baqarah) have short,
    /// centred lines.
    var isOpening: Bool { number <= 2 }

    private static var cache: [String: MushafPageText] = [:]

    /// The page in the current reading, or nil until the text and layout are loaded.
    static func page(_ number: Int) -> MushafPageText? {
        let store = QuranStore.shared
        let layout = MushafLayout.shared
        let edition = store.edition
        let key = "\(edition.rawValue):\(number)"
        if let cached = cache[key] { return cached }
        let layoutRows = layout.rows(page: number)
        guard store.isLoaded, !layoutRows.isEmpty else { return nil }

        var rows: [Row] = []
        var wordsBySurah: [Int: Int] = [:]
        var verses: [VerseKey] = []
        for row in layoutRows {
            switch row {
            case .header(let surah):
                rows.append(.header(surah: surah))
            case .basmala:
                // The Bismillah is verse 1:1 of the verified text.
                guard let opening = store.verses(for: 1).first else {
                    rows.append(.empty)
                    continue
                }
                let words = QuranWords.shared.words(for: opening, edition: edition)
                rows.append(.basmala(QuranTextPiece(words: words, range: 0...max(words.words.count - 1, 0),
                                                    showsVerseEnd: false)))
            case .text(let from, let to):
                let pieces = self.pieces(from: from, to: to, store: store, edition: edition)
                for piece in pieces {
                    wordsBySurah[piece.words.key.surah, default: 0] += piece.range.count
                    if verses.last != piece.words.key { verses.append(piece.words.key) }
                }
                rows.append(pieces.isEmpty ? .empty : .text(pieces))
            }
        }
        let widths = rows.map { row -> CGFloat in
            guard case .text(let pieces) = row else { return 0 }
            return QuranTextCanvas.naturalWidth(of: pieces, fontSize: 100) / 100
        }
        let surah = wordsBySurah.max { $0.value < $1.value }?.key ?? layout.firstWord(onPage: number)?.surah ?? 1
        let start = verses.first ?? VerseKey(surah: surah, verse: 1)
        let page = MushafPageText(number: number, rows: rows, widths: widths, surah: surah,
                                  juz: store.juz(containing: VerseReference(surah: start.surah, verse: start.verse)),
                                  verses: verses)
        cache[key] = page
        return page
    }

    /// The words from `from` to `to` (inclusive), one piece per verse.
    private static func pieces(from: WordID, to: WordID, store: QuranStore, edition: QuranEdition) -> [QuranTextPiece] {
        var pieces: [QuranTextPiece] = []
        var key = from.verseKey
        while key <= to.verseKey {
            let surahVerses = store.verses(for: key.surah)
            guard surahVerses.indices.contains(key.verse - 1) else { break }
            let words = QuranWords.shared.words(for: surahVerses[key.verse - 1], edition: edition)
            let last = words.words.count - 1
            let lower = key == from.verseKey ? from.index : 0
            let upper = key == to.verseKey ? min(to.index, last) : last
            if lower <= upper {
                pieces.append(QuranTextPiece(words: words, range: lower...upper, showsVerseEnd: upper == last))
            }
            key = key.verse < surahVerses.count
                ? VerseKey(surah: key.surah, verse: key.verse + 1)
                : VerseKey(surah: key.surah + 1, verse: 1)
        }
        return pieces
    }
}

/// Sizes for a mushaf page on this screen.
enum MushafMetrics {
    /// Surah and part labels above the lines.
    static let headerHeight: CGFloat = 30
    /// Page number below the lines.
    static let footerHeight: CGFloat = 26
    /// The widest line of a typical page, in multiples of the font size (the
    /// 90th percentile of all 8,807 lines, measured with the bundled Amiri
    /// Quran font). Keeps the text the same size on most pages.
    static let typicalLineWidth: CGFloat = 19.5
    /// How much a line's words may be squeezed or stretched to fill it.
    static let stretch: ClosedRange<CGFloat> = 0.9...1.1
    /// Lines on a full page.
    static let lineCount = 15

    static func margin(for width: CGFloat) -> CGFloat {
        max(12, (width * 0.04).rounded())
    }

    /// One text size for the whole page: its widest line just fits (squeezed
    /// at most to the stretch limit), no bigger than a typical page, and small
    /// enough for the line height.
    @MainActor
    static func fontSize(for page: MushafPageText, width: CGFloat, rowHeight: CGFloat) -> CGFloat {
        let cap = width / (typicalLineWidth * stretch.lowerBound)
        let widest = page.widths.max() ?? 0
        let fit = widest > 0 ? width / (widest * stretch.lowerBound) : cap
        return max(8, min(cap, fit, rowHeight / 1.45))
    }
}
