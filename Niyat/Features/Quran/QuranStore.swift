import CryptoKit
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

    /// Every surah opens with the Bismillah as a header, except Al-Fatiha (where it
    /// is verse 1) and At-Tawbah (which has none).
    var hasBismillahHeader: Bool { id != 1 && id != 9 }
}

struct Verse: Identifiable, Hashable {
    let surah: Int
    let number: Int
    /// The verse as shown in a mushaf. For verse 1 of most surahs the bundled
    /// Tanzil text starts with the Bismillah; we show that as a header instead.
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
    /// The Bismillah exactly as written in the bundled text (Al-Fatiha 1:1).
    private(set) var bismillah = ""
    /// nil while checking; true if the bundled files match the published checksums.
    private(set) var isVerified: Bool?
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
            bismillah = loaded.bismillah
            isLoaded = true
            isVerified = await Task.detached(priority: .utility) { Self.verifyChecksums() }.value
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

    /// SHA-256 of the bundled files, as published with the source data
    /// (risan/quran-json, from Tanzil and ClearQuran). If a file is changed or
    /// corrupted in any way, the hash won't match.
    static let expectedChecksums: [String: String] = [
        "quran-uthmani": "adaebb377c60eba1bab6ef652959c7a0b4ccb4d0ca42145945c14ecdbeb4b761",
        "translation-en-clearquran": "2e5d4d9fc7ee9cad5ed3fc0691d8e398c6f943a9ab7fe49ac515961abf5250ed",
        "chapters": "5b18adae945fcb6f9fbb865dd7dc596f89a63607a4e6617ca9e37f7f10d3386b",
    ]

    nonisolated static func verifyChecksums() -> Bool {
        expectedChecksums.allSatisfy { name, expected in
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return false }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return digest == expected
        }
    }

    /// Returns verse 1 without the leading Bismillah (its 4 words), or nil if it
    /// doesn't start with one. Two surahs spell the first word with a shadda,
    /// so shaddas are ignored when comparing.
    nonisolated static func removingBismillah(from text: String, bismillah: String) -> String? {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        let bismillahWords = bismillah.split(separator: " ")
        guard words.count > bismillahWords.count else { return nil }
        func normalized(_ word: Substring) -> String {
            String(String.UnicodeScalarView(word.unicodeScalars.filter { $0.value != 0x0651 }))
        }
        for (word, expected) in zip(words, bismillahWords) where normalized(word) != normalized(expected) {
            return nil
        }
        return words.dropFirst(bismillahWords.count).joined(separator: " ")
    }

    private nonisolated static func readBundle() throws -> (surahs: [Surah], verses: [Int: [Verse]], bismillah: String) {
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

        let bismillah = arabic["1"]?.first?.text ?? ""
        var verses: [Int: [Verse]] = [:]
        for chapter in chapters {
            let arabicVerses = arabic[String(chapter.id)] ?? []
            let englishVerses = english[String(chapter.id)] ?? []
            verses[chapter.id] = arabicVerses.enumerated().map { index, verse in
                var text = verse.text
                if chapter.hasBismillahHeader, verse.verse == 1,
                   let stripped = removingBismillah(from: text, bismillah: bismillah) {
                    text = stripped
                }
                return Verse(surah: chapter.id, number: verse.verse, arabic: text,
                             translation: englishVerses.indices.contains(index) ? englishVerses[index].text : "")
            }
        }
        return (chapters, verses, bismillah)
    }
}
