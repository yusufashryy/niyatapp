import Foundation
import Observation

/// The 604 pages of the Madinah mushaf (Hafs): what sits on each of its 15
/// lines. Built by scripts/generate_mushaf_layout.py from a published layout
/// and checked against Niyat's own Tanzil text (page starts, every word once
/// and in order, headers before every surah). Only positions are stored; the
/// words themselves always come from the verified Tanzil text.
@MainActor
@Observable
final class MushafLayout {
    static let shared = MushafLayout()

    enum Row: Equatable {
        /// A surah title.
        case header(surah: Int)
        /// The Bismillah before a surah.
        case basmala
        /// Words from `from` to `to`, inclusive. Word indices are into the
        /// displayed Uthmani verse (verse 1 without its Bismillah).
        case text(from: WordID, to: WordID)
    }

    private(set) var pages: [[Row]] = []
    /// The first word on each page, in page order.
    @ObservationIgnored private var firstWords: [WordID] = []
    var isLoaded: Bool { !pages.isEmpty }
    static let pageCount = 604

    private init() {}

    func load() async {
        guard pages.isEmpty else { return }
        let loaded = await Task.detached(priority: .userInitiated) { Self.read() }.value
        firstWords = loaded.map { rows in
            rows.lazy.compactMap { row -> WordID? in
                if case .text(let from, _) = row { return from }
                return nil
            }.first ?? WordID(surah: 0, verse: 0, index: 0)
        }
        pages = loaded
    }

    func rows(page: Int) -> [Row] {
        pages.indices.contains(page - 1) ? pages[page - 1] : []
    }

    /// The page a word is on (1...604).
    func page(containing word: WordID) -> Int {
        var low = 0, high = firstWords.count - 1, found = 0
        while low <= high {
            let mid = (low + high) / 2
            if firstWords[mid] <= word {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found + 1
    }

    /// The first word on a page.
    func firstWord(onPage page: Int) -> WordID? {
        firstWords.indices.contains(page - 1) ? firstWords[page - 1] : nil
    }

    private nonisolated static func read() -> [[Row]] {
        guard let url = Bundle.main.url(forResource: "mushaf-lines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = root["pages"] as? [[[Any]]] else { return [] }
        return pages.map { rows in
            rows.compactMap { row -> Row? in
                if let kind = row.first as? String {
                    if kind == "h", row.count == 2, let surah = row[1] as? Int { return .header(surah: surah) }
                    if kind == "b" { return .basmala }
                    return nil
                }
                let numbers = row.compactMap { $0 as? Int }
                guard numbers.count == 6 else { return nil }
                return .text(from: WordID(surah: numbers[0], verse: numbers[1], index: numbers[2]),
                             to: WordID(surah: numbers[3], verse: numbers[4], index: numbers[5]))
            }
        }
    }
}
