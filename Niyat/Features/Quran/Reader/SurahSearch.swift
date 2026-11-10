import Foundation

/// Finding a surah by what you type: its number, its name however it's
/// spelt ("baqarah", "al kahf"), its meaning, or its Arabic name; and an
/// ayah typed as "2:255". Pure, so it's tested.
enum SurahSearch {
    /// What a surah is found by.
    struct Entry: Equatable {
        let id: Int
        let name: String
        let transliteration: String
        let translation: String
    }

    static func matches(_ surahs: [Entry], query: String) -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return surahs }
        if let number = Int(trimmed) { return surahs.filter { $0.id == number } }
        let wanted = folded(trimmed)
        let loose = wanted.hasSuffix("h") ? String(wanted.dropLast()) : wanted
        return surahs.filter { surah in
            let name = folded(surah.transliteration)
            let byName = !loose.isEmpty
                && (name.contains(wanted) || name.contains(loose) || loosened(name).contains(loosened(loose)))
            return byName
                || surah.translation.localizedCaseInsensitiveContains(trimmed)
                || surah.name.contains(trimmed)
        }
    }

    /// An ayah typed as "2:255" (or "2 255", "2.255"), if it exists.
    /// `verseCounts[i]` is the number of ayat in surah i + 1.
    static func place(in query: String, verseCounts: [Int]) -> DailyPlace? {
        let parts = query.split(whereSeparator: { $0 == ":" || $0 == " " || $0 == "." }).compactMap { Int($0) }
        guard parts.count == 2, verseCounts.indices.contains(parts[0] - 1),
              (1...max(verseCounts[parts[0] - 1], 1)).contains(parts[1]) else { return nil }
        return DailyPlace(surah: parts[0], verse: parts[1])
    }

    /// Lower case letters only, without accents: "Al-Faatiha" → "alfaatiha".
    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .filter(\.isLetter)
    }

    /// Doubled vowels as one ("ikhlaas" → "ikhlas"), as names are spelt either way.
    private static func loosened(_ text: String) -> String {
        var result = ""
        for character in text where !(result.last == character && "aeiou".contains(character)) {
            result.append(character)
        }
        return result
    }
}

extension SurahSearch.Entry {
    init(_ surah: Surah) {
        self.init(id: surah.id, name: surah.name, transliteration: surah.transliteration, translation: surah.translation)
    }
}
