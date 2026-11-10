import SwiftUI

/// What the bookmark button opens: put your Continue reading ribbon on this
/// ayah, or keep a bookmark with a name, your own note and a colour.
struct BookmarkSheet: View {
    let reference: VerseReference
    /// Opened to edit this bookmark (from the bookmarks list).
    var editing: VerseBookmark?

    @Environment(\.dismiss) private var dismiss
    @State private var store = QuranStore.shared
    @State private var bookmarks = VerseBookmarkStore.shared
    // The bookmark being written or edited.
    @State private var editingID: UUID?
    @State private var color = BookmarkColor.gold
    @State private var title = ""
    @State private var note = ""
    @State private var saved = 0
    @FocusState private var focused: Bool

    private var verse: Verse? { store.verse(reference) }
    private var onThisAyah: [VerseBookmark] { VerseBookmarks.on(reference, in: bookmarks.all) }
    private var surahName: String { store.surah(reference.surah)?.transliteration ?? "Surah \(reference.surah)" }

    var body: some View {
        // A navigation stack only so the keyboard can show a Done button.
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focused = false }.fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .haptic(.success, trigger: saved)
        .onAppear { if let editing { edit(editing) } }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if let verse { continueCard(verse) }
                if !onThisAyah.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("On this ayah").sectionLabelStyle()
                        ForEach(onThisAyah) { bookmark in
                            Button { edit(bookmark) } label: {
                                BookmarkRow(bookmark: bookmark, isEditing: bookmark.id == editingID)
                            }
                            .buttonStyle(.pressable)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(bookmark) }
                            }
                        }
                    }
                }
                composer
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 24)
            .readableWidth(560)
            .animation(.smooth, value: onThisAyah)
            .animation(.smooth, value: editingID)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(.white)
        .niyatBackground()
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                EightPointStar().fill(Palette.highlight.opacity(0.16))
                EightPointStar().stroke(Palette.highlight.opacity(0.55), lineWidth: 1.5)
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Palette.highlight)
            }
            .frame(width: 80, height: 80)
            .accessibilityHidden(true)
            Text("Bookmark").font(.title2.weight(.bold))
            Text("\(surahName) · \(reference.surah):\(reference.verse)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// Your one Continue reading ribbon: here, or moved here.
    private func continueCard(_ verse: Verse) -> some View {
        let here = store.hasRibbon(verse)
        return Button {
            withAnimation(.smooth) { store.toggleRibbon(verse) }
            dismiss()
        } label: {
            HStack(spacing: 14) {
                RibbonMark(color: Color(QuranTextStyle.ribbonRed), starColor: .white)
                    .frame(width: 20, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue reading").font(.headline)
                    Text(here ? "Your ribbon is here. Tap to take it out." : "Put your ribbon here, to pick up where you left off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: here ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(here ? Color(QuranTextStyle.ribbonRed) : .secondary)
            }
            .padding(16)
            .background(Color(QuranTextStyle.ribbonRed).opacity(here ? 0.14 : 0), in: .rect(cornerRadius: 20))
            .surface(cornerRadius: 20)
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color(QuranTextStyle.ribbonRed).opacity(here ? 0.6 : 0), lineWidth: 1.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityHint(here ? "Removes your Continue reading ribbon" : "Moves your Continue reading ribbon to this ayah")
    }

    /// A new bookmark, or the one being edited: name (required), note, colour.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(editingID == nil ? "New bookmark" : "Edit bookmark").font(.headline)
                Spacer()
                if editingID != nil {
                    Button("New") { clear() }.font(.subheadline.weight(.semibold))
                }
            }
            TextField("Name", text: $title, prompt: Text("Name, e.g. Laylat al-Qadr").foregroundStyle(.secondary))
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($focused)
                .padding(12)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(color.color.opacity(0.6), lineWidth: 1.5)
                }
            TextField("Note", text: $note, prompt: Text("Note (optional): why this ayah, or who it's for").foregroundStyle(.secondary),
                      axis: .vertical)
                .lineLimit(3...8)
                .focused($focused)
                .padding(12)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
            colorPicker
            Button { save() } label: {
                Label(editingID == nil ? "Add bookmark" : "Save changes", systemImage: "bookmark.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.control)
            .disabled(!VerseBookmarks.canSave(name: title))
            if let editingID, let existing = bookmarks.all.first(where: { $0.id == editingID }) {
                Button("Delete bookmark", role: .destructive) { delete(existing) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .surface(cornerRadius: 22)
    }

    /// The colours as circles sharing one row, each as wide as the card
    /// allows, so they never run past its edge.
    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colour").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(BookmarkColor.allCases) { option in
                    Button { color = option } label: {
                        Circle()
                            .fill(option.color)
                            .overlay {
                                if color == option {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .heavy))
                                        .foregroundStyle(.black.opacity(0.75))
                                }
                            }
                            .padding(3)
                            .overlay {
                                Circle().strokeBorder(.white.opacity(color == option ? 0.9 : 0), lineWidth: 2)
                            }
                            .frame(maxWidth: 44)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(option.name)
                    .accessibilityAddTraits(color == option ? .isSelected : [])
                }
            }
            .animation(.smooth(duration: 0.2), value: color)
            .haptic(.selection, trigger: color)
        }
    }

    // MARK: Actions

    private func edit(_ bookmark: VerseBookmark) {
        editingID = bookmark.id
        color = bookmark.color
        title = bookmark.title
        note = bookmark.note
    }

    private func clear() {
        editingID = nil
        color = .gold
        title = ""
        note = ""
        focused = false
    }

    private func save() {
        guard VerseBookmarks.canSave(name: title) else { return }
        let existing = bookmarks.all.first { $0.id == editingID }
        bookmarks.save(VerseBookmark(id: editingID ?? UUID(), verse: reference,
                                     title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                     note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                     color: color, created: existing?.created ?? .now))
        saved += 1
        clear()
    }

    private func delete(_ bookmark: VerseBookmark) {
        bookmarks.remove(bookmark)
        if bookmark.id == editingID { clear() }
    }
}

/// One bookmark: its colour, name and note.
struct BookmarkRow: View {
    let bookmark: VerseBookmark
    var place: String?
    var isEditing = false

    var body: some View {
        // Centred when there's no note; with one, the icon stays by the name.
        HStack(alignment: bookmark.note.isEmpty ? .center : .top, spacing: 12) {
            Image(systemName: "bookmark.fill")
                .font(.body.weight(.bold))
                .foregroundStyle(bookmark.color.color)
                .frame(width: 38, height: 38)
                .background(bookmark.color.color.opacity(0.16), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(bookmark.title).font(.headline).lineLimit(1)
                    if let place {
                        Text(place)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if !bookmark.note.isEmpty {
                    Text(bookmark.note)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .surface(cornerRadius: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(bookmark.color.color.opacity(isEditing ? 0.7 : 0), lineWidth: 1.5)
        }
        .contentShape(.rect)
    }
}
