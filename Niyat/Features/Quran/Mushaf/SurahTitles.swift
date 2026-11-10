import Foundation

/// The surahs' titles with full harakat («سُورَةُ البَقَرَةِ»), as the printed
/// mushaf heads them. From AlQuran Cloud's surah list, unchanged (docs/SOURCES.md).
enum SurahTitles {
    private static let all: [String] = {
        guard let url = Bundle.main.url(forResource: "surah-titles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let titles = try? JSONDecoder().decode([String].self, from: data),
              titles.count == 114 else { return [] }
        return titles
    }()

    /// The title for surah 1–114; the plain «سورة» and name if the list is missing.
    static func title(for surah: Surah?) -> String {
        guard let surah else { return "" }
        let index = surah.id - 1
        return all.indices.contains(index) ? all[index] : "سورة " + surah.name
    }
}
