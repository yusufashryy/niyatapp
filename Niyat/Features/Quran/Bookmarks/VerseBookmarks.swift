import Foundation
import Observation
import SwiftUI

/// A bookmark's colour, chosen by you. Few enough to sit in one row.
/// Never red: red is the Continue reading ribbon's own colour.
enum BookmarkColor: String, Codable, CaseIterable, Identifiable {
    case gold, orange, green, teal, blue, purple, pink, silver

    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .gold: Color(red: 0.86, green: 0.70, blue: 0.24)
        case .orange: Color(red: 0.95, green: 0.55, blue: 0.20)
        case .green: Color(red: 0.25, green: 0.72, blue: 0.42)
        case .teal: Color(red: 0.20, green: 0.70, blue: 0.72)
        case .blue: Color(red: 0.27, green: 0.52, blue: 0.95)
        case .purple: Color(red: 0.62, green: 0.40, blue: 0.92)
        case .pink: Color(red: 0.93, green: 0.40, blue: 0.65)
        case .silver: Color(red: 0.76, green: 0.78, blue: 0.82)
        }
    }
}

/// A bookmark you keep, with a name, your own note and a colour.
struct VerseBookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var verse: VerseReference
    var title: String
    var note: String
    var color: BookmarkColor
    var created: Date

    init(id: UUID = UUID(), verse: VerseReference, title: String, note: String,
         color: BookmarkColor, created: Date = .now) {
        self.id = id
        self.verse = verse
        self.title = title
        self.note = note
        self.color = color
        self.created = created
    }

    private enum CodingKeys: String, CodingKey { case id, verse, title, note, color, created }

    // Tolerant, so fields added later don't lose saved bookmarks.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        verse = try c.decode(VerseReference.self, forKey: .verse)
        // A name is required now; one saved without lands as "Bookmark".
        let saved = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        title = VerseBookmarks.canSave(name: saved) ? saved : "Bookmark"
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        color = (try? c.decodeIfPresent(BookmarkColor.self, forKey: .color)) ?? .gold
        created = (try? c.decodeIfPresent(Date.self, forKey: .created)) ?? .now
    }
}

/// The rules for the list of bookmarks. Pure, so they're tested.
enum VerseBookmarks {
    /// A bookmark needs a name.
    static func canSave(name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Adds the bookmark, or replaces the one with its id; newest first.
    static func saving(_ bookmark: VerseBookmark, in list: [VerseBookmark]) -> [VerseBookmark] {
        (list.filter { $0.id != bookmark.id } + [bookmark]).sorted { $0.created > $1.created }
    }

    static func removing(_ id: UUID, from list: [VerseBookmark]) -> [VerseBookmark] {
        list.filter { $0.id != id }
    }

    /// The bookmarks on one verse, newest first.
    static func on(_ verse: VerseReference, in list: [VerseBookmark]) -> [VerseBookmark] {
        list.filter { $0.verse == verse }
    }
}

/// Your bookmarks, kept on this iPhone.
@MainActor @Observable
final class VerseBookmarkStore {
    static let shared = VerseBookmarkStore()
    private static let key = "quran.verseBookmarks"

    /// Newest first.
    private(set) var all: [VerseBookmark] = []

    private init() { reload() }

    /// Reads them again (after "Erase all data").
    func reload() {
        all = UserDefaults.standard.decoded([VerseBookmark].self, forKey: Self.key) ?? []
    }

    func save(_ bookmark: VerseBookmark) {
        all = VerseBookmarks.saving(bookmark, in: all)
        persist()
    }

    func remove(_ bookmark: VerseBookmark) {
        all = VerseBookmarks.removing(bookmark.id, from: all)
        persist()
    }

    /// The bookmarks on a verse (any reading's numbering, kept as Hafs).
    func on(_ verse: Verse) -> [VerseBookmark] {
        VerseBookmarks.on(verse.hafsReference, in: all)
    }

    private func persist() {
        UserDefaults.standard.setEncoded(all, forKey: Self.key)
    }
}
