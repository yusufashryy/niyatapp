import Foundation
import Observation

struct Surah: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let transliteration: String
    let translation: String
    let type: String
    let totalVerses: Int

    enum CodingKeys: String, CodingKey {
        case id, name, transliteration, translation, type
        case totalVerses = "total_verses"
    }

    var revelationPlace: String { type == "meccan" ? "Meccan" : "Medinan" }
}

struct Verse: Identifiable, Hashable {
    let surah: Int
    let number: Int
    let arabic: String
    let translation: String

    var id: Int { surah * 1000 + number }
}

struct VerseReference: Codable, Hashable, Identifiable {
    let surah: Int
    let verse: Int

    var id: Int { surah * 1000 + verse }
}

/// Loads the bundled Quran text (Tanzil Uthmani) and English translation
/// (ClearQuran). Everything is offline.
@MainActor
@Observable
final class QuranStore {
    static let shared = QuranStore()

    private(set) var surahs: [Surah] = []
    private(set) var isLoaded = false
    private(set) var loadError: String?
    private var versesBySurah: [Int: [Verse]] = [:]

    private(set) var lastRead: VerseReference?
    private(set) var bookmarks: [VerseReference]

    private init() {
        lastRead = UserDefaults.standard.decoded(VerseReference.self, forKey: "quran.lastRead")
        bookmarks = UserDefaults.standard.decoded([VerseReference].self, forKey: "quran.bookmarks") ?? []
    }

    func verses(for surah: Int) -> [Verse] { versesBySurah[surah] ?? [] }

    func surah(_ id: Int) -> Surah? { surahs.first { $0.id == id } }

    func verse(_ reference: VerseReference) -> Verse? {
        let verses = verses(for: reference.surah)
        let index = reference.verse - 1
        return verses.indices.contains(index) ? verses[index] : nil
    }

    func isBookmarked(_ verse: Verse) -> Bool {
        bookmarks.contains(VerseReference(surah: verse.surah, verse: verse.number))
    }

    func toggleBookmark(_ verse: Verse) {
        let reference = VerseReference(surah: verse.surah, verse: verse.number)
        if let index = bookmarks.firstIndex(of: reference) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.append(reference)
        }
        saveBookmarks()
    }

    func removeBookmarks(atOffsets offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        saveBookmarks()
    }

    func markRead(surah: Int, verse: Int) {
        let reference = VerseReference(surah: surah, verse: verse)
        guard reference != lastRead else { return }
        lastRead = reference
        UserDefaults.standard.setEncoded(reference, forKey: "quran.lastRead")
    }

    private func saveBookmarks() {
        UserDefaults.standard.setEncoded(bookmarks, forKey: "quran.bookmarks")
    }

    func load() async {
        guard !isLoaded else { return }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try Self.readBundle() }.value
            surahs = loaded.surahs
            versesBySurah = loaded.verses
            isLoaded = true
        } catch {
            loadError = "Couldn't load the Quran text: \(error.localizedDescription)"
        }
    }

    private struct RawVerse: Decodable {
        let chapter: Int
        let verse: Int
        let text: String
    }

    private struct ChapterFile: Decodable {
        let chapters: [Surah]
    }

    private enum BundleError: Error { case missing(String) }

    private nonisolated static func readBundle() throws -> (surahs: [Surah], verses: [Int: [Verse]]) {
        func data(_ name: String) throws -> Data {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                throw BundleError.missing(name)
            }
            return try Data(contentsOf: url)
        }
        let decoder = JSONDecoder()
        let chapters = try decoder.decode(ChapterFile.self, from: data("chapters")).chapters
        let arabic = try decoder.decode([String: [RawVerse]].self, from: data("quran-uthmani"))
        let english = try decoder.decode([String: [RawVerse]].self, from: data("translation-en-clearquran"))

        var verses: [Int: [Verse]] = [:]
        for chapter in chapters {
            let arabicVerses = arabic[String(chapter.id)] ?? []
            let englishVerses = english[String(chapter.id)] ?? []
            verses[chapter.id] = arabicVerses.enumerated().map { index, verse in
                Verse(surah: chapter.id, number: verse.verse, arabic: verse.text,
                      translation: englishVerses.indices.contains(index) ? englishVerses[index].text : "")
            }
        }
        return (chapters, verses)
    }
}
