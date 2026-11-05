import Foundation
import Observation

/// The tafsirs bundled with Niyat, from Quranpedia (scripts/build_tafsir.py, docs/SOURCES.md).
enum TafsirBook: String, CaseIterable, Identifiable {
    case jalalayn
    case ibnKathir = "ibn-kathir"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jalalayn: "Al-Jalalayn"
        case .ibnKathir: "Ibn Kathir"
        }
    }

    /// One line on what it's like, for choosing between them.
    var summary: String {
        switch self {
        case .jalalayn: "Short notes, word by word"
        case .ibnKathir: "Full commentary with hadith"
        }
    }
}

/// One stretch of commentary: the ayat `from...to` of a surah, explained together.
struct TafsirEntry: Equatable {
    let surah: Int
    let from: Int
    let to: Int
    let text: String

    var isRange: Bool { from != to }
}

/// A tafsir file as `scripts/build_tafsir.py` writes it.
struct TafsirFile: Decodable {
    let id: String
    let name: String
    let nameEnglish: String
    let author: String
    let edition: String
    let version: String
    let entries: [TafsirEntry]

    private enum CodingKeys: String, CodingKey { case id, name, nameEnglish, author, edition, version, entries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        nameEnglish = try c.decode(String.self, forKey: .nameEnglish)
        author = try c.decode(String.self, forKey: .author)
        edition = try c.decode(String.self, forKey: .edition)
        version = try c.decode(String.self, forKey: .version)
        var list = try c.nestedUnkeyedContainer(forKey: .entries)
        var entries: [TafsirEntry] = []
        while !list.isAtEnd {
            var row = try list.nestedUnkeyedContainer()
            entries.append(TafsirEntry(surah: try row.decode(Int.self), from: try row.decode(Int.self),
                                       to: try row.decode(Int.self), text: try row.decode(String.self)))
        }
        self.entries = entries
    }

    /// Reads a `.tafsir` file: raw-DEFLATE-compressed JSON.
    static func decode(compressed data: Data) throws -> TafsirFile {
        let json = try (data as NSData).decompressed(using: .zlib) as Data
        return try JSONDecoder().decode(TafsirFile.self, from: json)
    }
}

/// Finds the commentary for an ayah. Pure, so it's tested.
struct TafsirIndex {
    let file: TafsirFile
    private let bySurah: [Int: [TafsirEntry]]

    init(_ file: TafsirFile) {
        self.file = file
        bySurah = Dictionary(grouping: file.entries, by: \.surah).mapValues { $0.sorted { $0.from < $1.from } }
    }

    /// The entry that covers this ayah, or nil if the tafsir says nothing on it.
    func entry(surah: Int, ayah: Int) -> TafsirEntry? {
        guard let entries = bySurah[surah] else { return nil }
        var low = 0, high = entries.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let entry = entries[mid]
            if ayah < entry.from { high = mid - 1 } else if ayah > entry.to { low = mid + 1 } else { return entry }
        }
        return nil
    }
}

/// Loads each tafsir once, off the main thread, and keeps it.
@MainActor @Observable
final class TafsirStore {
    static let shared = TafsirStore()

    enum LoadError: LocalizedError {
        case missing(TafsirBook)
        var errorDescription: String? { "This tafsir isn't in the app. Try reinstalling Niyat." }
    }

    private var loaded: [TafsirBook: TafsirIndex] = [:]

    func index(_ book: TafsirBook) async throws -> TafsirIndex {
        if let index = loaded[book] { return index }
        guard let url = Bundle.main.url(forResource: book.rawValue, withExtension: "tafsir") else { throw LoadError.missing(book) }
        let index = try await Task.detached(priority: .userInitiated) {
            TafsirIndex(try TafsirFile.decode(compressed: try Data(contentsOf: url)))
        }.value
        loaded[book] = index
        return index
    }
}
