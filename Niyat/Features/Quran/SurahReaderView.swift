import SwiftUI
import UIKit

struct SurahReaderView: View {
    let surahID: Int
    /// Hafs verse number to open at (from bookmarks or "continue reading").
    let startVerse: Int?

    @Environment(AppModel.self) private var model
    @State private var store = QuranStore.shared
    @State private var player = RecitationPlayer.shared
    @State private var goal = QuranGoalModel.shared
    @AppStorage("quran.arabicSize") private var arabicSize = 30.0
    @AppStorage("quran.showTranslation") private var showTranslation = true
    @State private var didScroll = false
    @State private var showSettings = false
    @State private var showGoal = false
    /// Verses currently on screen, for counting what's actually read.
    @State private var visibleVerses: Set<Int> = []

    /// A verse counts as read after it has been on screen this long.
    private let readingDwell: Duration = .seconds(3)

    var body: some View {
        let surah = store.surah(surahID)
        let audioAvailable = store.edition.riwayah.hasVerseAudio
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let surah {
                        SurahHeader(surah: surah, verseCount: store.verseCount(for: surah.id), edition: store.edition)
                            .padding(.bottom, 6)
                        if store.showsBismillahHeader(for: surah) {
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
                                  showsPlay: audioAvailable,
                                  onPlay: { play(from: verse.number) }) {
                            store.toggleBookmark(verse)
                        }
                        .id(verse.number)
                        .scrollFade()
                        .onAppear {
                            store.markRead(verse)
                            visibleVerses.insert(verse.id)
                            countWhenRead(verse)
                        }
                        .onDisappear { visibleVerses.remove(verse.id) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .onAppear {
                guard !didScroll, let startVerse, startVerse > 1 else { return }
                didScroll = true
                let target = store.verse(VerseReference(surah: surahID, verse: startVerse))?.number ?? startVerse
                DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
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
        .niyatBackground()
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
        .overlay {
            if let streak = goal.celebration {
                GoalCelebration(streak: streak) { goal.celebration = nil }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.bouncy, value: goal.celebration)
        .navigationTitle(surah?.transliteration ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                QuranGoalPill { showGoal = true }
            }
            if audioAvailable {
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
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("Qur'an settings")
            }
        }
        .sheet(isPresented: $showSettings) { QuranSettingsView() }
        .sheet(isPresented: $showGoal) { QuranGoalSheet() }
        .onDisappear {
            // Update the afternoon reminder with today's remaining ayat.
            model.refresh()
        }
    }

    private func play(from verse: Int) {
        player.play(surah: surahID, from: verse, verseCounts: store.hafsVerseCounts)
    }

    /// Counts the verse towards today's goal if it's still on screen after a few seconds.
    private func countWhenRead(_ verse: Verse) {
        Task {
            try? await Task.sleep(for: readingDwell)
            guard visibleVerses.contains(verse.id) else { return }
            goal.recordRead(verse)
        }
    }
}

private struct SurahHeader: View {
    let surah: Surah
    let verseCount: Int
    let edition: QuranEdition

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
            Text("\(surah.translation) · \(surah.revelationPlace) · \(verseCount) verses")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if edition.riwayah != .hafs {
                Text(edition.riwayah.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Palette.accent.opacity(0.15), in: .capsule)
                    .foregroundStyle(Palette.accent)
            }
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
    let showsPlay: Bool
    let onPlay: () -> Void
    let onToggleBookmark: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row: verse number and small controls, kept apart from the text.
            HStack(spacing: 4) {
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
                        .padding(.leading, 6)
                }
                Spacer()
                if showsPlay {
                    Button(action: onPlay) {
                        Image(systemName: isReciting ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .font(.subheadline)
                            .foregroundStyle(isReciting ? Palette.accent : Color.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Play verse \(verse.number)")
                }
                Button(action: onToggleBookmark) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.subheadline)
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
            if showsPlay {
                Button("Play from here", systemImage: "play.fill") { onPlay() }
            }
            Button(isBookmarked ? "Remove bookmark" : "Bookmark",
                   systemImage: isBookmarked ? "bookmark.slash" : "bookmark") { onToggleBookmark() }
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = "\(verse.arabic)\n\n\(verse.translation)\n— Qur'an \(verse.surah):\(verse.number)"
            }
        }
    }
}

// MARK: - Daily goal UI

/// Compact progress ring in the reader's navigation bar: "7/10".
struct QuranGoalPill: View {
    @State private var goal = QuranGoalModel.shared
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: goal.progress)
                        .stroke(goal.today.isComplete ? Palette.highlight : Palette.accent,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth, value: goal.progress)
                }
                .frame(width: 18, height: 18)
                if let target = goal.goal {
                    Text("\(goal.today.count)/\(target)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText(value: Double(goal.today.count)))
                } else {
                    Text("Goal").font(.caption.weight(.bold))
                }
            }
        }
        .accessibilityLabel(goal.goal.map { "Today's Qur'an goal: \(goal.today.count) of \($0) ayat" } ?? "Set a daily Qur'an goal")
    }
}

/// Shown once when the day's goal is reached.
struct GoalCelebration: View {
    let streak: Int
    let onDismiss: () -> Void
    @State private var burst = false

    init(streak: Int, onDismiss: @escaping () -> Void) {
        self.streak = streak
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Rosette(color: Palette.highlight, lineWidth: 1.5)
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(burst ? 45 : 0))
                    .scaleEffect(burst ? 1 : 0.6)
                EightPointStar()
                    .fill(Palette.highlight)
                    .frame(width: 46, height: 46)
                    .shadow(color: Palette.highlight, radius: 14)
            }
            Text("Goal complete")
                .font(.display(26, weight: .heavy))
            Text("🔥 \(streak)-day Qur'an streak")
                .font(.headline)
                .foregroundStyle(Palette.highlight)
            Text("Alhamdulillah")
                .font(.calligraphy(size: 26))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(28)
        .glassPanel(cornerRadius: 32, tint: Palette.glow.opacity(0.4))
        .padding(40)
        .onAppear {
            if Haptics.isEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { burst = true }
            Task {
                try? await Task.sleep(for: .seconds(2.8))
                onDismiss()
            }
        }
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
    }
}
