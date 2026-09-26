import SwiftUI
import UIKit

struct SurahReaderView: View {
    let surahID: Int
    /// Hafs verse number to open at (from bookmarks or "continue reading").
    let startVerse: Int?

    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var store = QuranStore.shared
    @State private var player = RecitationPlayer.shared
    @State private var live = LiveRecitation.shared
    @State private var highlights = WordHighlights.shared
    @State private var goal = QuranGoalModel.shared
    @AppStorage("quran.arabicSize") private var arabicSize = 30.0
    @AppStorage("quran.showTranslation") private var showTranslation = true
    @AppStorage("quran.tajweed") private var tajweedOn = true
    @AppStorage(QuranLineSpacing.key) private var lineHeight = QuranLineSpacing.standard
    @State private var tajweedStore = TajweedStore.shared
    @State private var didScroll = false
    @State private var showSettings = false
    @State private var showGoal = false
    @State private var showReview = false
    @State private var showIntro = false
    /// Verses currently on screen, for counting what's actually read.
    @State private var visibleVerses: Set<Int> = []
    /// Where the list is scrolled to, by Verse.id (0 = the Bismillah).
    @State private var position = ScrollPosition(idType: Int.self)
    private static let bismillahID = 0

    /// A verse counts as read after it has been on screen this long.
    private let readingDwell: Duration = .seconds(3)

    var body: some View {
        let surah = store.surah(surahID)
        let audioAvailable = store.edition.riwayah.hasVerseAudio
        ScrollView {
                LazyVStack(spacing: 8) {
                    if let surah {
                        SurahHeader(surah: surah, verseCount: store.verseCount(for: surah.id), edition: store.edition)
                            .padding(.bottom, 6)
                        if store.showsBismillahHeader(for: surah), let opening = store.verses(for: 1).first {
                            let reciting = player.current == .bismillah(surah: surah.id)
                            let words = QuranWords.shared.words(for: opening, edition: store.edition)
                            QuranTextView(pieces: [QuranTextPiece(words: words, range: 0...max(words.words.count - 1, 0),
                                                                  showsVerseEnd: false)],
                                          style: textStyle(size: 28, ink: UIColor(Palette.highlight)),
                                          layout: .centredLine)
                                .frame(height: 64)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background {
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(Palette.accent.opacity(reciting ? 0.15 : 0))
                                }
                                .id(Self.bismillahID)
                                .appearAnimation(1)
                        }
                    }
                    ForEach(store.verses(for: surahID)) { verse in
                        VerseCard(verse: verse, words: QuranWords.shared.words(for: verse, edition: store.edition),
                                  style: textStyle(size: arabicSize, ink: .white),
                                  showTranslation: showTranslation,
                                  isBookmarked: store.isBookmarked(verse),
                                  isReciting: player.current == .verse(surah: surahID, verse: verse.number),
                                  showsPlay: audioAvailable,
                                  onPlay: { play(from: verse.number) }) {
                            store.toggleBookmark(verse)
                        }
                        .id(verse.id)
                        .scrollFade()
                        .onAppear {
                            store.markRead(verse)
                            visibleVerses.insert(verse.id)
                            countWhenRead(verse)
                        }
                        .onDisappear { visibleVerses.remove(verse.id) }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollPosition($position, anchor: .center)
            .onAppear {
                guard !didScroll else { return }
                didScroll = true
                // Opened while this surah is being recited: go to that verse.
                if let current = player.current, current.surah == surahID {
                    DispatchQueue.main.async { follow(current, animated: false) }
                    return
                }
                guard let startVerse, startVerse > 1 else { return }
                let target = store.verse(VerseReference(surah: surahID, verse: startVerse))?.id ?? surahID * 1000 + startVerse
                DispatchQueue.main.async { position.scrollTo(id: target, anchor: .top) }
            }
            // Follow along: keep the verse being recited in the middle of the screen.
            .onChange(of: player.current) { _, current in
                guard let current, current.surah == surahID else { return }
                follow(current, animated: true)
            }
            // Reciting yourself: the same, verse by verse.
            .onChange(of: highlights.activeVerse) { _, verse in
                guard live.isListening, let verse, verse.surah == surahID else { return }
                withAnimation(.smooth(duration: 0.5)) { position.scrollTo(id: verse.surah * 1000 + verse.verse, anchor: .center) }
            }
        .niyatBackground()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if live.isListening || highlights.flaggedCount > 0 {
                    recitationBar.transition(.move(edge: .bottom).combined(with: .opacity))
                }
                RecitationMiniPlayer()
            }
            .padding(.bottom, 6)
            .animation(.smooth, value: player.current)
            .animation(.smooth, value: live.isListening)
            .animation(.smooth, value: highlights.flaggedCount > 0)
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
            // Memorisation (eye) sits immediately left of the microphone, next to play.
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { highlights.setHidden(!highlights.isHidden) } label: {
                    Image(systemName: highlights.isHidden ? "eye.slash.fill" : "eye.slash")
                        .foregroundStyle(highlights.isHidden ? Palette.control : Color.primary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(highlights.isHidden ? "Show the text" : "Hide the text to recite from memory")
                Button(action: toggleListening) {
                    Image(systemName: live.isListening ? "mic.fill" : "mic")
                        .foregroundStyle(live.isListening ? Palette.control : Color.primary)
                        .symbolEffect(.pulse, options: .repeating, isActive: live.isListening)
                }
                .accessibilityLabel(live.isListening ? "Stop listening" : "Recite: follow along as I recite")
                if audioAvailable {
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
        .haptic(.selection, trigger: highlights.isHidden)
        .haptic(.impact(weight: .light), trigger: live.isListening)
        .sheet(isPresented: $showSettings) { QuranSettingsView() }
        .sheet(isPresented: $showGoal) { QuranGoalSheet() }
        .sheet(isPresented: $showReview) {
            RecitationReviewSheet(onListen: listenAction) { key in
                withAnimation(.smooth) { position.scrollTo(id: key.surah * 1000 + key.verse, anchor: .center) }
            }
        }
        .sheet(isPresented: $showIntro) {
            ReciteIntroSheet(edition: store.edition) { startListening() }
        }
        .alert("Recite with Niyat", isPresented: unavailableBinding) {
            Button("OK", role: .cancel) { live.acknowledge() }
        } message: {
            if case .unavailable(let message) = live.status { Text(message) }
        }
        .task { await tajweedStore.load() }
        .onChange(of: live.isListening) { _, listening in
            UIApplication.shared.isIdleTimerDisabled = listening
        }
        .onDisappear {
            // Leaving the surah ends listening, memorisation and the review.
            live.stop()
            live.clearReview()
            highlights.setHidden(false)
            UIApplication.shared.isIdleTimerDisabled = false
            // Update the afternoon reminder with today's remaining ayat.
            model.refresh()
        }
    }

    /// Live recitation's status, with the review and a stop button.
    private var recitationBar: some View {
        HStack(spacing: 10) {
            if live.isListening {
                LiveRecitationStatus()
            } else {
                Text("Recitation finished")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if highlights.flaggedCount > 0 {
                Button { showReview = true } label: {
                    Label("Review \(highlights.flaggedCount)", systemImage: "text.badge.checkmark")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                .buttonStyle(.pressable)
                .foregroundStyle(Palette.highlight)
            }
            if live.isListening {
                Button { live.stop() } label: {
                    Label("Stop", systemImage: "stop.fill").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.pressable)
                .foregroundStyle(.white)
            } else {
                Button { live.clearReview() } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.bold)).frame(width: 28, height: 28)
                }
                .buttonStyle(.pressable)
                .foregroundStyle(.white)
                .accessibilityLabel("Clear marks")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(Palette.glow.opacity(0.4)), in: .capsule)
        .padding(.horizontal, 12)
    }

    private var unavailableBinding: Binding<Bool> {
        Binding(get: {
            if case .unavailable = live.status { return true }
            return false
        }, set: { shown in
            if !shown { live.acknowledge() }
        })
    }

    /// How Qur'an text is drawn in the reader.
    private func textStyle(size: Double, ink: UIColor) -> QuranTextStyle {
        var style = QuranTextStyle()
        style.fontSize = CGFloat(size)
        style.lineHeight = CGFloat(lineHeight)
        style.ink = ink
        style.marker = UIColor(Palette.highlight)
        style.tajweed = showsTajweed
        style.dark = true
        style.highContrast = contrast == .increased
        return style
    }

    // MARK: Live recitation

    private func toggleListening() {
        if live.isListening {
            live.stop()
        } else if UserDefaults.standard.bool(forKey: ReciteIntroSheet.seenKey) {
            startListening()
        } else {
            showIntro = true
        }
    }

    /// Listens across the whole surah, starting the search at the verse at
    /// the top of the screen.
    private func startListening() {
        let verses = store.verses(for: surahID)
        let words = verses.map { QuranWords.shared.words(for: $0, edition: store.edition) }
        let top = visibleVerses.min() ?? store.lastRead.flatMap { $0.surah == surahID ? surahID * 1000 + $0.verse : nil }
        var start = 0
        if let top {
            for (verse, verseWords) in zip(verses, words) {
                if verse.id >= top { break }
                start += verseWords.words.count
            }
        }
        Task { await live.start(verses: words, edition: store.edition, at: start, searchingAhead: 300) }
    }

    /// Scrolls so the verse being recited sits in the middle of the screen.
    private func follow(_ item: RecitationItem, animated: Bool) {
        // Recitation is numbered like Hafs; find the matching card. Cards are
        // identified by Verse.id (surah × 1000 + verse), the same as the ForEach.
        let target = item.verse.map { store.verse(VerseReference(surah: surahID, verse: $0))?.id ?? surahID * 1000 + $0 }
            ?? Self.bismillahID
        if animated {
            withAnimation(.smooth(duration: 0.5)) { position.scrollTo(id: target, anchor: .center) }
        } else {
            position.scrollTo(id: target, anchor: .center)
        }
    }

    /// Tajweed colours are for the Uthmani (Hafs) text they were made for.
    private var showsTajweed: Bool {
        tajweedOn && store.edition == .uthmani && tajweedStore.isLoaded
    }

    private func play(from verse: Int) {
        live.stop()
        player.play(surah: surahID, from: verse, verseCounts: store.hafsVerseCounts)
    }

    /// "Listen" in the review, when there's audio for the reading.
    private var listenAction: ((VerseKey) -> Void)? {
        guard store.edition.riwayah.hasVerseAudio else { return nil }
        return { key in play(only: key) }
    }

    /// Plays one verse (from the review).
    private func play(only key: VerseKey) {
        guard let verse = store.verses(for: key.surah).first(where: { $0.number == key.verse }) else { return }
        live.stop()
        player.play(surah: surahID, from: verse.hafsReference.verse, verseCounts: store.hafsVerseCounts, only: true)
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
    let words: VerseWords
    let style: QuranTextStyle
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

            QuranTextView(pieces: [QuranTextPiece(verse: words)], style: style)
                .frame(maxWidth: .infinity)

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
