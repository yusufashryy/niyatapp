import SwiftUI
import UIKit

struct SurahReaderView: View {
    let surahID: Int
    let startVerse: Int?

    @State private var store = QuranStore.shared
    @AppStorage("quran.arabicSize") private var arabicSize = 30.0
    @AppStorage("quran.showTranslation") private var showTranslation = true
    @State private var didScroll = false

    var body: some View {
        let surah = store.surah(surahID)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let surah {
                        SurahHeader(surah: surah)
                            .padding(.bottom, 6)
                    }
                    ForEach(store.verses(for: surahID)) { verse in
                        VerseCard(verse: verse, arabicSize: arabicSize, showTranslation: showTranslation,
                                  isBookmarked: store.isBookmarked(verse)) {
                            store.toggleBookmark(verse)
                        }
                        .id(verse.number)
                        .onAppear { store.markRead(surah: surahID, verse: verse.number) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .onAppear {
                guard !didScroll, let startVerse, startVerse > 1 else { return }
                didScroll = true
                DispatchQueue.main.async { proxy.scrollTo(startVerse, anchor: .top) }
            }
        }
        .niyatBackground()
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
        VStack(spacing: 8) {
            Text(surah.name)
                .font(.quran(size: 44))
                .foregroundStyle(Palette.gold)
            Text(surah.transliteration)
                .font(.title2.weight(.bold))
            Text("\(surah.translation) · \(surah.revelationPlace) · \(surah.totalVerses) verses")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .glassPanel(cornerRadius: 30, tint: Palette.deepEmerald.opacity(0.35))
    }
}

private struct VerseCard: View {
    let verse: Verse
    let arabicSize: Double
    let showTranslation: Bool
    let isBookmarked: Bool
    let onToggleBookmark: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(verse.surah):\(verse.number)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Palette.emerald)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Palette.emerald.opacity(0.14), in: .capsule)
                Spacer()
                Button(action: onToggleBookmark) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(isBookmarked ? Palette.gold : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark")
            }

            Text(verse.arabic)
                .font(.quran(size: arabicSize))
                .foregroundStyle(.white)
                .lineSpacing(arabicSize * 0.35)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if showTranslation, !verse.translation.isEmpty {
                Text(verse.translation)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(18)
        .surface(cornerRadius: 22)
        .contextMenu {
            Button(isBookmarked ? "Remove bookmark" : "Bookmark",
                   systemImage: isBookmarked ? "bookmark.slash" : "bookmark") { onToggleBookmark() }
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = "\(verse.arabic)\n\n\(verse.translation)\n— Quran \(verse.surah):\(verse.number)"
            }
        }
    }
}
