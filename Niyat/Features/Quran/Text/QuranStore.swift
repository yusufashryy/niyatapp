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
    /// The verse number in the selected reading's own count.
    let number: Int
    /// The verse as shown in a mushaf. For verse 1 of most surahs the bundled
    /// Tanzil text starts with the Bismillah; we show that as a header instead.
    let arabic: String
    /// English translation (ClearQuran, keyed to Hafs numbering and lined up
    /// through `hafsNumbers` for other readings).
    let translation: String
    /// The Hafs verse number(s) this verse corresponds to. For Hafs it's just
    /// `[number]`; Warsh and Qalun sometimes split or join verses.
    let hafsNumbers: [Int]

    var id: Int { surah * 1000 + number }
    /// Hafs reference used for saved verses, the ribbon and progress, so they
    /// survive switching script or reading.
    var hafsReference: VerseReference { VerseReference(surah: surah, verse: hafsNumbers.first ?? number) }
    /// Letters in the displayed Arabic, for the recitation-reward estimate.
    var letterCount: Int { ArabicLetters.count(in: arabic) }
}

struct VerseReference: Codable, Hashable, Identifiable {
    let surah: Int
    let verse: Int

    var id: Int { surah * 1000 + verse }
}

/// Loads the bundled, verified Qur'an texts and the English translation.
/// Everything is offline.
@MainActor
@Observable
final class QuranStore {
    static let shared = QuranStore()

    private(set) var surahs: [Surah] = []
    private(set) var isLoaded = false
    private(set) var loadError: String?
    /// The text being shown. Changing it never touches saved verses, the ribbon or progress.
    private(set) var edition: QuranEdition
    /// The Bismillah exactly as written in the selected Hafs text (Al-Fatiha 1:1).
    private(set) var bismillah = ""
    /// nil while checking; true if every bundled file matches its published checksum.
    private(set) var isVerified: Bool?
    private var versesBySurah: [Int: [Verse]] = [:]

    /// Where you are: the reading ribbon (see `ReadingRibbon`).
    private(set) var ribbon: VerseReference?
    /// The reader placed the ribbon themselves (see `ReadingRibbon.follows`).
    private(set) var ribbonPinned = UserDefaults.standard.bool(forKey: ReadingRibbon.pinnedKey)
    /// The reader just took the ribbon out: reading on doesn't put it back
    /// until they close this surah or mushaf (see `resumeRibbon`).
    @ObservationIgnored private var ribbonPaused = false
    /// Saved verses: a list you keep, apart from the ribbon.
    private(set) var bookmarks: [VerseReference]

    private init() {
        edition = UserDefaults.standard.string(forKey: "quran.edition").flatMap(QuranEdition.init(rawValue:)) ?? .default
        ribbon = Self.savedRibbon()
        bookmarks = UserDefaults.standard.decoded([VerseReference].self, forKey: "quran.bookmarks") ?? []
    }

    private static func savedRibbon() -> VerseReference? {
        ReadingRibbon.initial(saved: UserDefaults.standard.decoded(VerseReference.self, forKey: ReadingRibbon.storageKey),
                              legacy: UserDefaults.standard.decoded(VerseReference.self, forKey: ReadingRibbon.legacyKey))
    }

    func verses(for surah: Int) -> [Verse] { versesBySurah[surah] ?? [] }

    /// Surahs are stored in order, so number N is at N - 1 (checked, in case a file ever isn't).
    func surah(_ id: Int) -> Surah? {
        if surahs.indices.contains(id - 1), surahs[id - 1].id == id { return surahs[id - 1] }
        return surahs.first { $0.id == id }
    }

    /// Verse count in the selected reading (differs from Hafs for Warsh/Qalun).
    func verseCount(for surah: Int) -> Int { versesBySurah[surah]?.count ?? self.surah(surah)?.totalVerses ?? 0 }

    /// Hafs verse counts per surah, used for recitation audio numbering.
    var hafsVerseCounts: [Int] { surahs.map(\.totalVerses) }

    /// Whether to show the Bismillah above a surah. Only for Hafs texts, where
    /// the verified text contains it; the Warsh/Qalun sources don't include it.
    func showsBismillahHeader(for surah: Surah) -> Bool {
        edition.riwayah == .hafs && surah.hasBismillahHeader && !bismillah.isEmpty
    }

    /// The verse in the current reading that contains a Hafs verse.
    func verse(_ reference: VerseReference) -> Verse? {
        verses(for: reference.surah).first { $0.hafsNumbers.contains(reference.verse) }
    }

    func isBookmarked(_ verse: Verse) -> Bool {
        verse.hafsNumbers.contains { bookmarks.contains(VerseReference(surah: verse.surah, verse: $0)) }
    }

    func toggleBookmark(_ verse: Verse) {
        let matching = bookmarks.filter { $0.surah == verse.surah && verse.hafsNumbers.contains($0.verse) }
        if matching.isEmpty {
            bookmarks.append(verse.hafsReference)
        } else {
            bookmarks.removeAll { matching.contains($0) }
        }
        saveBookmarks()
    }

    func removeBookmarks(atOffsets offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        saveBookmarks()
    }

    /// The reader puts the ribbon on a verse: it stays there until they read on past it.
    func moveRibbon(to verse: Verse) {
        setRibbon(verse.hafsReference, pinned: true)
    }

    /// The reader settled on a verse while reading: the ribbon follows,
    /// unless they placed it further on themselves.
    func followRibbon(to verse: Verse) {
        let reference = verse.hafsReference
        guard !ribbonPaused, ReadingRibbon.follows(to: reference, from: ribbon, pinned: ribbonPinned) else { return }
        setRibbon(reference, pinned: false)
    }

    /// Takes the ribbon out. If it follows you, it comes back next time you read.
    func removeRibbon() {
        ribbonPaused = true
        ribbon = nil
        ribbonPinned = false
        UserDefaults.standard.removeObject(forKey: ReadingRibbon.storageKey)
        UserDefaults.standard.removeObject(forKey: ReadingRibbon.legacyKey)
        UserDefaults.standard.set(false, forKey: ReadingRibbon.pinnedKey)
    }

    /// Puts the ribbon on a verse, or takes it out if it's already there.
    func toggleRibbon(_ verse: Verse) {
        if hasRibbon(verse) { removeRibbon() } else { moveRibbon(to: verse) }
    }

    /// The surah or mushaf closed: the ribbon may follow again.
    func resumeRibbon() {
        ribbonPaused = false
    }

    private func setRibbon(_ reference: VerseReference, pinned: Bool) {
        if pinned { ribbonPaused = false }
        if reference != ribbon {
            ribbon = reference
            UserDefaults.standard.setEncoded(reference, forKey: ReadingRibbon.storageKey)
        }
        ribbonPinned = pinned
        UserDefaults.standard.set(pinned, forKey: ReadingRibbon.pinnedKey)
    }

    func hasRibbon(_ verse: Verse) -> Bool {
        guard let ribbon, ribbon.surah == verse.surah else { return false }
        return verse.hafsNumbers.contains(ribbon.verse)
    }

    /// The mushaf page the ribbon lies in, once the page index is loaded.
    var ribbonPage: Int? {
        guard let ribbon, !pageStarts.isEmpty else { return nil }
        return page(containing: ribbon)
    }

    /// Re-reads saved verses and the ribbon (after "Erase all data").
    func reloadUserData() {
        ribbon = Self.savedRibbon()
        ribbonPinned = UserDefaults.standard.bool(forKey: ReadingRibbon.pinnedKey)
        bookmarks = UserDefaults.standard.decoded([VerseReference].self, forKey: "quran.bookmarks") ?? []
    }

    private func saveBookmarks() {
        UserDefaults.standard.setEncoded(bookmarks, forKey: "quran.bookmarks")
    }

    func load() async {
        guard !isLoaded else { return }
        await load(edition: edition)
        isVerified = await Task.detached(priority: .utility) { Self.verifyChecksums() }.value
    }

    /// Switches to another verified text. Saved verses, the ribbon and
    /// progress are stored by Hafs reference, so they carry over.
    func setEdition(_ newEdition: QuranEdition) async {
        guard newEdition != edition || !isLoaded else { return }
        UserDefaults.standard.set(newEdition.rawValue, forKey: "quran.edition")
        let switching = isLoaded && newEdition != edition
        await load(edition: newEdition)
        // The other reading's split words and pages won't be shown again soon.
        if switching, edition == newEdition { QuranMemory.releaseCaches() }
    }

    private func load(edition newEdition: QuranEdition) async {
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try Self.readBundle(edition: newEdition) }.value
            surahs = loaded.surahs
            versesBySurah = loaded.verses
            if let indexes = loaded.indexes {
                pageStarts = indexes.pages.map { VerseReference(surah: $0.sura, verse: $0.aya) }
                juzStarts = indexes.juzs.map { VerseReference(surah: $0.sura, verse: $0.aya) }
                hizbStarts = indexes.hizbs.map { VerseReference(surah: $0.sura, verse: $0.aya) }
                sajdahVerses = Set(indexes.sajdas.map { VerseReference(surah: $0.sura, verse: $0.aya) })
            }
            bismillah = loaded.bismillah
            edition = newEdition
            isLoaded = true
            loadError = nil
        } catch {
            loadError = "Couldn't load the Qur'an text: \(error.localizedDescription)"
        }
    }

    private struct RawVerse: Decodable {
        let chapter: Int
        let verse: Int
        let text: String
        let number_in_hafs: [Int]?
    }

    private struct ChapterFile: Decodable {
        let chapters: [Surah]
        let indexes: Indexes?

        struct Indexes: Decodable {
            let juzs: [Marker]
            let hizbs: [Marker]
            let pages: [Marker]
            let sajdas: [Marker]
        }

        struct Marker: Decodable {
            let index: Int
            let sura: Int
            let aya: Int
        }
    }

    /// Where each Madinah-mushaf page, juz and hizb quarter starts (Tanzil
    /// metadata, Hafs numbering), plus the sajdah verses.
    private(set) var pageStarts: [VerseReference] = []
    private(set) var juzStarts: [VerseReference] = []
    private(set) var hizbStarts: [VerseReference] = []
    private(set) var sajdahVerses: Set<VerseReference> = []

    /// The 1-based mushaf page containing a Hafs verse.
    func page(containing reference: VerseReference) -> Int {
        let key = reference.surah * 1000 + reference.verse
        var low = 0, high = pageStarts.count - 1, found = 0
        while low <= high {
            let mid = (low + high) / 2
            if pageStarts[mid].surah * 1000 + pageStarts[mid].verse <= key { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found + 1
    }

    /// Juz (1...30) containing a Hafs verse.
    func juz(containing reference: VerseReference) -> Int {
        let key = reference.surah * 1000 + reference.verse
        return (juzStarts.lastIndex { $0.surah * 1000 + $0.verse <= key } ?? 0) + 1
    }

    /// Hafs verses on a mushaf page, in order.
    func verses(onPage page: Int) -> [Verse] {
        guard page >= 1, page <= pageStarts.count else { return [] }
        let start = pageStarts[page - 1]
        let end = page < pageStarts.count ? pageStarts[page] : nil
        var result: [Verse] = []
        for surah in start.surah...(end?.surah ?? 114) {
            for verse in verses(for: surah) {
                let key = verse.hafsReference.id
                if key < start.surah * 1000 + start.verse { continue }
                if let end, key >= end.surah * 1000 + end.verse { break }
                result.append(verse)
            }
        }
        return result
    }

    private enum BundleError: Error { case missing(String) }

    /// SHA-256 of every bundled Qur'an file, as published with its source dataset.
    /// If a file is changed or corrupted in any way, the hash won't match.
    nonisolated static let expectedChecksums: [String: String] = {
        var sums = [
            "reading-signs": "d916800d4a978c0b19bc8db49276d5e82c0dd7b6fc018640d8d34c31ec1665dd",
            "translation-en-clearquran": "2e5d4d9fc7ee9cad5ed3fc0691d8e398c6f943a9ab7fe49ac515961abf5250ed",
            "chapters": "5b18adae945fcb6f9fbb865dd7dc596f89a63607a4e6617ca9e37f7f10d3386b",
        ]
        for edition in QuranEdition.allCases { sums[edition.fileName] = edition.sha256 }
        return sums
    }()

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
        guard !bismillahWords.isEmpty, words.count > bismillahWords.count else { return nil }
        func normalized(_ word: Substring) -> String {
            String(String.UnicodeScalarView(word.unicodeScalars.filter { $0.value != 0x0651 }))
        }
        for (word, expected) in zip(words, bismillahWords) where normalized(word) != normalized(expected) {
            return nil
        }
        return words.dropFirst(bismillahWords.count).joined(separator: " ")
    }

    private nonisolated static func readBundle(edition: QuranEdition) throws
        -> (surahs: [Surah], verses: [Int: [Verse]], bismillah: String, indexes: ChapterFile.Indexes?) {
        func data(_ name: String) throws -> Data {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                throw BundleError.missing(name)
            }
            return try Data(contentsOf: url)
        }
        let decoder = JSONDecoder()
        let chapterFile = try decoder.decode(ChapterFile.self, from: data("chapters"))
        let chapters = chapterFile.chapters
        let arabic = try decoder.decode([String: [RawVerse]].self, from: data(edition.fileName))
        let english = try decoder.decode([String: [RawVerse]].self, from: data("translation-en-clearquran"))

        // Hafs texts carry the Bismillah as 1:1 and prefix it to verse 1 elsewhere.
        let bismillah = edition.riwayah == .hafs ? (arabic["1"]?.first?.text ?? "") : ""
        var verses: [Int: [Verse]] = [:]
        for chapter in chapters {
            let arabicVerses = arabic[String(chapter.id)] ?? []
            let englishByHafs = Dictionary((english[String(chapter.id)] ?? []).map { ($0.verse, $0.text) },
                                           uniquingKeysWith: { first, _ in first })
            var translated = Set<Int>()
            verses[chapter.id] = arabicVerses.map { raw in
                var text = raw.text
                if edition.riwayah == .hafs, chapter.hasBismillahHeader, raw.verse == 1,
                   let stripped = removingBismillah(from: text, bismillah: bismillah) {
                    text = stripped
                }
                let hafsNumbers = raw.number_in_hafs ?? [raw.verse]
                // Each Hafs translation is shown once, on the first verse that
                // covers it; a verse that continues one says so.
                let newNumbers = hafsNumbers.filter { !translated.contains($0) }
                translated.formUnion(newNumbers)
                let translation = newNumbers.isEmpty
                    ? "(Continues the previous verse.)"
                    : newNumbers.compactMap { englishByHafs[$0] }.joined(separator: " ")
                return Verse(surah: chapter.id, number: raw.verse, arabic: text,
                             translation: translation, hafsNumbers: hafsNumbers)
            }
        }
        return (chapters, verses, bismillah, chapterFile.indexes)
    }
}
