import Foundation
import Observation
import SwiftUI

/// What a bookmark is for: its icon and colour.
enum BookmarkOccasion: String, Codable, CaseIterable, Identifiable {
    case general, ramadan, jumuah, eid, hajj, dua, family, memorise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Bookmark"
        case .ramadan: "Ramadan"
        case .jumuah: "Jumu'ah"
        case .eid: "Eid"
        case .hajj: "Hajj"
        case .dua: "Dua"
        case .family: "Family"
        case .memorise: "To memorise"
        }
    }

    var icon: String {
        switch self {
        case .general: "bookmark.fill"
        case .ramadan: "moon.stars.fill"
        case .jumuah: "building.columns.fill"
        case .eid: "sparkles"
        case .hajj: "figure.walk.motion"
        case .dua: "hands.and.sparkles.fill"
        case .family: "heart.fill"
        case .memorise: "brain.head.profile"
        }
    }

    /// Each occasion's own colour (like the hadith situations), so a list of
    /// bookmarks reads at a glance.
    var tint: Color {
        switch self {
        case .general: Palette.highlight
        case .ramadan: .indigo
        case .jumuah: .teal
        case .eid: .pink
        case .hajj: .orange
        case .dua: .purple
        case .family: .red
        case .memorise: .blue
        }
    }
}

/// A bookmark you keep for a special occasion, with your own note.
struct VerseBookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var verse: VerseReference
    var title: String
    var note: String
    var occasion: BookmarkOccasion
    var created: Date

    init(id: UUID = UUID(), verse: VerseReference, title: String, note: String,
         occasion: BookmarkOccasion, created: Date = .now) {
        self.id = id
        self.verse = verse
        self.title = title
        self.note = note
        self.occasion = occasion
        self.created = created
    }

    /// Its title, or the occasion's name when it has none.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? occasion.title : trimmed
    }

    private enum CodingKeys: String, CodingKey { case id, verse, title, note, occasion, created }

    // Tolerant, so fields added later don't lose saved bookmarks.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        verse = try c.decode(VerseReference.self, forKey: .verse)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        occasion = (try? c.decodeIfPresent(BookmarkOccasion.self, forKey: .occasion)) ?? .general
        created = (try? c.decodeIfPresent(Date.self, forKey: .created)) ?? .now
    }
}

/// The rules for the list of bookmarks. Pure, so they're tested.
enum VerseBookmarks {
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

/// Your bookmarks for special occasions, kept on this iPhone.
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
