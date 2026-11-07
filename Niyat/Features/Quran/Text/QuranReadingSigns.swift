import Foundation

/// Tanzil's pause and sajdah marks, verified against every Hafs verse by
/// scripts/generate_reading_signs.py. Original Quran text stays unchanged.
/// Warsh and Qalun already carry the signs of their own printed editions.
enum QuranReadingSigns {
    private static let data: [String: [String: [String: String]]] = {
        guard let url = Bundle.main.url(forResource: "reading-signs", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: [String: String]]].self, from: bytes) else {
            return [:]
        }
        return decoded
    }()

    static func signs(surah: Int, verse: Int, edition: QuranEdition) -> [Int: String] {
        guard let signs = data[edition.rawValue]?["\(surah):\(verse)"] else { return [:] }
        return Dictionary(uniqueKeysWithValues: signs.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
    }
}
