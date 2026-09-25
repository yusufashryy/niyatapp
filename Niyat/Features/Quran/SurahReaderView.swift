import SwiftUI
import UIKit

struct SurahReaderView: View {
    let surahID: Int
    let startVerse: Int?

    @State private var store = QuranStore.shared
    @State private var player = RecitationPlayer.shared
    @State private var showReciters = false
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
                        if surah.hasBismillahHeader, !store.bismillah.isEmpty {
                            let reciting = player.current == .bismillah(surah: surah.id)
                            Text(store.bismillah)
                                .font(.quran(size: 28))
                                .foregroundStyle(Palette.highlight)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background {
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(Palette.accent.opacity(reciting ? 0.15 : 0))
                                }
                                .id("bismillah")
                                .appearAnimation(1)
                        }
                    }
                    ForEach(store.verses(for: surahID)) { verse in
                        VerseCard(verse: verse, arabicSize: arabicSize, showTranslation: showTranslation,
                                  isBookmarked: store.isBookmarked(verse),
                                  isReciting: player.current == .verse(surah: surahID, verse: verse.number),
                                  onPlay: { play(from: verse.number) }) {
                            store.toggleBookmark(verse)
                        }
                        .id(verse.number)
                        .scrollFade()
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
            // Follow along: keep the verse being recited on screen.
            .onChange(of: player.current) { _, current in
                guard let current, current.surah == surahID else { return }
                withAnimation(.smooth(duration: 0.5)) {
                    if let verse = current.verse {
                        proxy.scrollTo(verse, anchor: .center)
                    } else {
                        proxy.scrollTo("bismillah", anchor: .center)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            RecitationMiniPlayer()
                .padding(.bottom, 6)
                .animation(.smooth, value: player.current)
        }
        .overlay(alignment: .top) {
            if let error = player.errorMessage {
                Text(error)
                    .font(.footnote.weight(.semibold))
                    .padding(12)
                    .glassEffect(.regular.tint(.red.opacity(0.3)), in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .niyatBackground()
        .sheet(isPresented: $showReciters) { ReciterPicker() }
        .navigationTitle(surah?.transliteration ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if player.current?.surah == surahID {
                        player.togglePlayPause()
                    } else {
                        play(from: 1)
                    }
                } label: {
                    Image(systemName: player.current?.surah == surahID && player.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel("Play recitation")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Reciter: \(player.reciter.name)", systemImage: "person.wave.2.fill") { showReciters = true }
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

extension SurahReaderView {
    fileprivate func play(from verse: Int) {
        player.play(surah: surahID, from: verse, verseCounts: store.surahs.map(\.totalVerses))
    }
}

private struct SurahHeader: View {
    let surah: Surah

    var body: some View {
        VStack(spacing: 8) {
            Text(surah.name)
                .font(.quran(size: 44))
                .foregroundStyle(Palette.highlight)
                .background {
                    Rosette(color: Palette.highlight.opacity(0.18))
                        .frame(width: 170, height: 170)
                }
            Text(surah.transliteration)
                .font(.title2.weight(.bold))
            Text("\(surah.translation) · \(surah.revelationPlace) · \(surah.totalVerses) verses")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            OrnamentDivider()
                .frame(width: 180)
                .padding(.top, 6)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background { IslamicPattern(tile: 48, lineWidth: 0.6, color: Palette.accent.opacity(0.08)) }
        .clipShape(.rect(cornerRadius: 30))
        .glassPanel(cornerRadius: 30, tint: Palette.glow.opacity(0.35))
        .appearAnimation(0)
    }
}

private struct VerseCard: View {
    let verse: Verse
    let arabicSize: Double
    let showTranslation: Bool
    let isBookmarked: Bool
    let isReciting: Bool
    let onPlay: () -> Void
    let onToggleBookmark: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(verse.surah):\(verse.number)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Palette.accent.opacity(0.14), in: .capsule)
                if isReciting {
                    Image(systemName: "waveform")
                        .foregroundStyle(Palette.accent)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                Button(action: onPlay) {
                    Image(systemName: "play.circle")
                        .foregroundStyle(Color.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Play from verse \(verse.number)")
                Button(action: onToggleBookmark) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(isBookmarked ? Palette.highlight : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: isBookmarked)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.pressable)
                .haptic(.impact(weight: .medium), trigger: isBookmarked)
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
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Palette.accent.opacity(isReciting ? 0.8 : 0), lineWidth: 1.5)
        }
        .shadow(color: Palette.accent.opacity(isReciting ? 0.35 : 0), radius: 12)
        .animation(.smooth(duration: 0.4), value: isReciting)
        .contextMenu {
            Button("Play from here", systemImage: "play.fill") { onPlay() }
            Button(isBookmarked ? "Remove bookmark" : "Bookmark",
                   systemImage: isBookmarked ? "bookmark.slash" : "bookmark") { onToggleBookmark() }
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = "\(verse.arabic)\n\n\(verse.translation)\n— Quran \(verse.surah):\(verse.number)"
            }
        }
    }
}
