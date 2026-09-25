import SwiftUI
import UIKit

struct SurahReaderView: View {
    let surahID: Int
    let startVerse: Int?

    @State private var store = QuranStore.shared
    @AppStorage("quran.arabicSize") private var arabicSize = 28.0
    @AppStorage("quran.showTranslation") private var showTranslation = true
    @State private var didScroll = false

    var body: some View {
        let surah = store.surah(surahID)
        ScrollViewReader { proxy in
            List {
                if let surah {
                    SurahHeader(surah: surah)
                        .listRowSeparator(.hidden)
                }
                ForEach(store.verses(for: surahID)) { verse in
                    VerseRow(verse: verse, arabicSize: arabicSize, showTranslation: showTranslation,
                             isBookmarked: store.isBookmarked(verse)) {
                        store.toggleBookmark(verse)
                    }
                    .id(verse.number)
                    .onAppear {
                        store.markRead(surah: surahID, verse: verse.number)
                    }
                }
            }
            .listStyle(.plain)
            .onAppear {
                guard !didScroll, let startVerse, startVerse > 1 else { return }
                didScroll = true
                DispatchQueue.main.async { proxy.scrollTo(startVerse, anchor: .top) }
            }
        }
        .navigationTitle(surah?.transliteration ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Show translation", isOn: $showTranslation)
                    Section("Arabic text size") {
                        Button("Larger", systemImage: "textformat.size.larger") { arabicSize = min(arabicSize + 2, 48) }
                        Button("Smaller", systemImage: "textformat.size.smaller") { arabicSize = max(arabicSize - 2, 18) }
                    }
                } label: {
                    Image(systemName: "textformat.size")
                }
            }
        }
    }
}

private struct SurahHeader: View {
    let surah: Surah

    var body: some View {
        VStack(spacing: 6) {
            Text(surah.name)
                .font(.quran(size: 36))
            Text("\(surah.transliteration) · \(surah.translation)")
                .font(.headline)
            Text("\(surah.revelationPlace) · \(surah.totalVerses) verses")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.niyatiBackground, in: .rect(cornerRadius: 18))
    }
}

private struct VerseRow: View {
    let verse: Verse
    let arabicSize: Double
    let showTranslation: Bool
    let isBookmarked: Bool
    let onToggleBookmark: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(verse.surah):\(verse.number)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.niyatiGreen.opacity(0.12), in: .capsule)
                    .foregroundStyle(Color.niyatiGreen)
                if isBookmarked {
                    Image(systemName: "bookmark.fill").foregroundStyle(Color.niyatiGold)
                }
                Spacer()
            }

            Text(verse.arabic)
                .font(.quran(size: arabicSize))
                .lineSpacing(arabicSize * 0.35)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)

            if showTranslation, !verse.translation.isEmpty {
                Text(verse.translation)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button(isBookmarked ? "Remove bookmark" : "Bookmark",
                   systemImage: isBookmarked ? "bookmark.slash" : "bookmark") { onToggleBookmark() }
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = "\(verse.arabic)\n\n\(verse.translation)\n— Quran \(verse.surah):\(verse.number)"
            }
        }
        .swipeActions(edge: .leading) {
            Button(isBookmarked ? "Unmark" : "Bookmark", systemImage: "bookmark") { onToggleBookmark() }
                .tint(.niyatiGold)
        }
    }
}
