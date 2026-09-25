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
                } else {
                    list
                }
            }
            .navigationTitle("Quran")
            .navigationDestination(for: ReaderDestination.self) { destination in
                SurahReaderView(surahID: destination.surah, startVerse: destination.verse)
            }
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
        List {
            if searchText.isEmpty, let lastRead = store.lastRead, let surah = store.surah(lastRead.surah) {
                Section {
                    NavigationLink(value: ReaderDestination(surah: surah.id, verse: lastRead.verse)) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Continue reading").font(.headline)
                                Text("\(surah.transliteration), verse \(lastRead.verse)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "book.pages.fill").foregroundStyle(Color.salahGreen)
                        }
                    }
                }
            }

            if searchText.isEmpty, !store.bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(store.bookmarks) { bookmark in
                        if let surah = store.surah(bookmark.surah) {
                            NavigationLink(value: ReaderDestination(surah: surah.id, verse: bookmark.verse)) {
                                Label("\(surah.transliteration) \(bookmark.surah):\(bookmark.verse)",
                                      systemImage: "bookmark.fill")
                            }
                        }
                    }
                    .onDelete { store.removeBookmarks(atOffsets: $0) }
                }
            }

            Section("Surahs") {
                ForEach(filteredSurahs) { surah in
                    NavigationLink(value: ReaderDestination(surah: surah.id, verse: nil)) {
                        SurahRow(surah: surah)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Name or number")
    }
}

struct ReaderDestination: Hashable {
    let surah: Int
    let verse: Int?
}

private struct SurahRow: View {
    let surah: Surah

    var body: some View {
        HStack(spacing: 14) {
            Text("\(surah.id)")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .frame(width: 36, height: 36)
                .background(Color.salahGreen.opacity(0.12), in: .rect(cornerRadius: 10))
                .foregroundStyle(Color.salahGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text(surah.transliteration).font(.headline)
                Text("\(surah.translation) · \(surah.totalVerses) verses · \(surah.revelationPlace)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(surah.name)
                .font(.quran(size: 22))
                .foregroundStyle(Color.salahGreen)
        }
        .padding(.vertical, 2)
    }
}
