import SwiftUI

/// Every special bookmark, newest first: tap to read the ayah, hold to edit
/// or delete.
struct BookmarksListView: View {
    let onOpen: (VerseReference) -> Void

    @State private var bookmarks = VerseBookmarkStore.shared
    @State private var editing: VerseBookmark?

    var body: some View {
        ScrollView {
            if bookmarks.all.isEmpty {
                ContentUnavailableView("No bookmarks yet", systemImage: "bookmark",
                                       description: Text("Tap the bookmark on any ayah to keep it for a special occasion, with a note."))
                    .padding(.top, 60)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(bookmarks.all) { bookmark in
                        BookmarkListItem(bookmark: bookmark, onOpen: onOpen) { editing = bookmark }
                    }
                }
                .padding(16)
                .readableWidth()
            }
        }
        .niyatBackground()
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { BookmarkSheet(reference: $0.verse, editing: $0) }
    }
}

/// A bookmark in a list: opens its ayah; its menu edits or deletes it.
struct BookmarkListItem: View {
    let bookmark: VerseBookmark
    let onOpen: (VerseReference) -> Void
    let onEdit: () -> Void

    @State private var store = QuranStore.shared

    private var place: String {
        let name = store.surah(bookmark.verse.surah)?.transliteration ?? "Surah \(bookmark.verse.surah)"
        return "\(name) \(bookmark.verse.surah):\(bookmark.verse.verse)"
    }

    var body: some View {
        Button { onOpen(bookmark.verse) } label: {
            BookmarkRow(bookmark: bookmark, place: place)
        }
        .buttonStyle(.pressable)
        .contextMenu {
            Button("Edit", systemImage: "pencil") { onEdit() }
            Button("Delete", systemImage: "trash", role: .destructive) { VerseBookmarkStore.shared.remove(bookmark) }
        }
        .accessibilityHint("Opens the ayah. Hold for edit and delete.")
    }
}
