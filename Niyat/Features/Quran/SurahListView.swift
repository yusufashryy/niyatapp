import SwiftUI

struct SurahListView: View {
    @State private var store = QuranStore.shared
    @State private var searchText = ""
    @State private var path: [ReaderDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let error = store.loadError {
                    ContentUnavailableView("Quran unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if !store.isLoaded {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .niyatBackground()
            .navigationTitle("Quran")
            .navigationDestination(for: ReaderDestination.self) { destination in
                SurahReaderView(surahID: destination.surah, startVerse: destination.verse)
            }
            .searchable(text: $searchText, prompt: "Surah name or number")
            .task { await store.load() }
        }
    }

    private var filteredSurahs: [Surah] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.surahs }
        if let number = Int(query) { return store.surahs.filter { $0.id == number } }
        return store.surahs.filter {
            $0.transliteration.localizedCaseInsensitiveContains(query)
                || $0.translation.localizedCaseInsensitiveContains(query)
                || $0.name.contains(query)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if searchText.isEmpty, let lastRead = store.lastRead, let surah = store.surah(lastRead.surah) {
                    NavigationLink(value: ReaderDestination(surah: surah.id, verse: lastRead.verse)) {
                        ContinueReadingCard(surah: surah, verse: lastRead.verse)
                    }
                    .buttonStyle(.pressable)
                    .appearAnimation(0)
                }

                if searchText.isEmpty, !store.bookmarks.isEmpty {
                    Text("Bookmarks").sectionLabelStyle().padding(.top, 8)
                    ScrollView(.horizontal, showsIndicators: false) {
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(store.bookmarks) { bookmark in
                                    if let surah = store.surah(bookmark.surah) {
                                        NavigationLink(value: ReaderDestination(surah: surah.id, verse: bookmark.verse)) {
                                            Label("\(surah.transliteration) \(bookmark.surah):\(bookmark.verse)", systemImage: "bookmark.fill")
                                                .font(.subheadline.weight(.semibold))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 10)
                                                .glassEffect(.regular.interactive(), in: .capsule)
                                        }
                                        .buttonStyle(.pressable)
                                        .contextMenu {
                                            Button("Remove bookmark", systemImage: "bookmark.slash", role: .destructive) {
                                                if let index = store.bookmarks.firstIndex(of: bookmark) {
                                                    store.removeBookmarks(atOffsets: IndexSet(integer: index))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .scrollClipDisabled()
                }

                Text("Surahs").sectionLabelStyle().padding(.top, 8)

                ForEach(Array(filteredSurahs.enumerated()), id: \.element.id) { index, surah in
                    NavigationLink(value: ReaderDestination(surah: surah.id, verse: nil)) {
                        SurahRow(surah: surah)
                    }
                    .buttonStyle(.pressable)
                    .scrollFade()
                    // Only the first screenful animates in, so scrolling stays calm.
                    .appearAnimation(index, enabled: index < 12 && searchText.isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}

struct ReaderDestination: Hashable {
    let surah: Int
    let verse: Int?
}

private struct ContinueReadingCard: View {
    let surah: Surah
    let verse: Int

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "book.pages.fill")
                .font(.title2)
                .foregroundStyle(Palette.highlight)
            VStack(alignment: .leading, spacing: 2) {
                Text("Continue reading")
                    .sectionLabelStyle()
                    .foregroundStyle(Palette.accent)
                Text(surah.transliteration)
                    .font(.title3.weight(.bold))
                Text("Verse \(verse) of \(surah.totalVerses)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(surah.name)
                .font(.quran(size: 28))
                .foregroundStyle(Palette.highlight)
        }
        .padding(18)
        .background(alignment: .trailing) {
            Rosette(color: Palette.highlight.opacity(0.15))
                .frame(width: 150, height: 150)
                .offset(x: 50)
        }
        .clipShape(.rect(cornerRadius: 26))
        .glassPanel(cornerRadius: 26, tint: Palette.glow.opacity(0.4), interactive: true)
    }
}

private struct SurahRow: View {
    let surah: Surah

    var body: some View {
        HStack(spacing: 14) {
            Text("\(surah.id)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(Palette.accent)
                .frame(width: 42, height: 42)
                .background {
                    EightPointStar()
                        .stroke(Palette.accent.opacity(0.6), lineWidth: 1.5)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(surah.transliteration)
                    .font(.headline)
                Text("\(surah.translation) · \(surah.totalVerses) verses · \(surah.revelationPlace)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(surah.name)
                .font(.quran(size: 22))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .surface(cornerRadius: 20)
        .contentShape(.rect)
    }
}
