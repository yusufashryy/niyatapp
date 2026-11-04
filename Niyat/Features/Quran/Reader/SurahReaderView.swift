import SwiftUI
import UIKit

struct SurahReaderView: View {
    /// The surah shown. Live recitation can move it to another surah.
    @State private var surahID: Int
    /// Hafs verse number to open at (from saved verses or "continue reading").
    let startVerse: Int?

    init(surahID: Int, startVerse: Int?) {
        _surahID = State(initialValue: surahID)
        self.startVerse = startVerse
    }

    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The ayah found by reciting from the Qur'an list, where listening starts.
    @State private var handoffVerse: Int?
    @State private var store = QuranStore.shared
    @State private var player = RecitationPlayer.shared
    @State private var live = LiveRecitation.shared
    @State private var highlights = WordHighlights.shared
    @State private var goal = QuranGoalModel.shared
    @AppStorage("quran.arabicSize") private var arabicSize = 30.0
    @AppStorage("quran.showTranslation") private var showTranslation = true
    @AppStorage("quran.tajweed") private var tajweedOn = true
    @AppStorage(QuranLineSpacing.key) private var lineHeight = QuranLineSpacing.standard
    @AppStorage(QuranTextWeight.key) private var textWeight = QuranTextWeight.regular.rawValue
    @AppStorage(ReadingRibbon.followsKey) private var ribbonFollows = true
    @State private var tajweedStore = TajweedStore.shared
    @State private var didScroll = false
    @State private var showSettings = false
    @State private var showGoal = false
    @State private var showReview = false
    @State private var showIntro = false
    /// Verses currently on screen, for counting what's actually read.
    @State private var visibleVerses: Set<Int> = []
    /// Verses at least half on screen, by Verse.id, for placing the ribbon.
    @State private var onScreen: [Int] = []
    /// You scrolled by hand since the ribbon last moved.
    @State private var scrolledByReader = false
    @State private var ribbonTask: Task<Void, Never>?
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
                                  isSaved: store.isBookmarked(verse),
                                  hasRibbon: store.hasRibbon(verse),
                                  isReciting: player.current == .verse(surah: surahID, verse: verse.number),
                                  showsPlay: audioAvailable,
                                  onPlay: { play(from: verse.number) },
                                  onPlaceRibbon: { withAnimation(.smooth) { store.moveRibbon(to: verse) } }) {
                            store.toggleBookmark(verse)
                        }
                        // No fade-in: under the Recite row a fading card stayed
                        // blank, and the text should never be hidden while you scroll.
                        .id(verse.id)
                        .onAppear {
                            visibleVerses.insert(verse.id)
                            countWhenRead(verse)
                        }
                        .onDisappear { visibleVerses.remove(verse.id) }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                // Qur'an text reads best at a book-like width.
                .readableWidth(820)
            }
            .scrollPosition($position, anchor: .center)
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.5) { onScreen = $0 }
            .onScrollPhaseChange { _, phase in scrollPhaseChanged(to: phase) }
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
            // Recited from another surah (or far away): go there and keep listening.
            .onChange(of: live.jump) { _, jump in
                guard let jump else { return }
                follow(jump.word)
            }
            // Reciting yourself: the same, verse by verse.
            .onChange(of: highlights.activeVerse) { _, verse in
                guard live.isListening, let verse, verse.surah == surahID else { return }
                withAnimation(.smooth(duration: 0.5)) { position.scrollTo(id: verse.surah * 1000 + verse.verse, anchor: .center) }
            }
        .niyatBackground()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                RecitationDock(onRecite: toggleListening) { showReview = true }
                RecitationMiniPlayer()
            }
            .readableWidth(600)
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
        // Reading on iPhone: the tab bar steps aside, leaving the Recite row
        // the bottom of the screen to itself. Beside the list (iPad, Duo
        // open) it stays.
        .toolbar(sizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                QuranGoalPill { showGoal = true }
            }
            // Memorisation (eye) next to play; Recite is its own button at the bottom.
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { highlights.setHidden(!highlights.isHidden) } label: {
                    Image(systemName: highlights.isHidden ? "eye.slash.fill" : "eye.slash")
                        .foregroundStyle(highlights.isHidden ? Palette.control : Color.primary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(highlights.isHidden ? "Show the text" : "Hide the text to recite from memory")
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
        // Found by reciting from the Qur'an list: carry on following from there.
        .task {
            guard let place = RecitationHandoff.take(for: surahID) else { return }
            handoffVerse = place.verse
            try? await Task.sleep(for: .milliseconds(600))
            if !live.isListening { toggleListening() }
        }
        .onChange(of: live.isListening) { _, listening in
            UIApplication.shared.isIdleTimerDisabled = listening
        }
        .onDisappear {
            // Leaving the surah ends listening, memorisation and the review.
            live.stop()
            live.clearReview()
            highlights.setHidden(false)
            ribbonTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
            // Update the afternoon reminder with today's remaining ayat.
            model.refresh()
        }
    }

    /// The ribbon follows you once you've scrolled somewhere yourself and
    /// stayed there. Scrolling done for you (opening at a verse, following a
    /// recitation) doesn't count.
    private func scrollPhaseChanged(to phase: ScrollPhase) {
        ribbonTask?.cancel()
        switch phase {
        case .interacting: scrolledByReader = true
        case .animating: scrolledByReader = false
        default: break
        }
        guard phase == .idle, ReadingRibbon.shouldMove(follows: ribbonFollows, movedByReader: scrolledByReader) else { return }
        ribbonTask = Task {
            try? await Task.sleep(for: ReadingRibbon.readerDwell)
            guard !Task.isCancelled, let top = onScreen.filter({ $0 != Self.bismillahID }).min(),
                  let verse = store.verses(for: surahID).first(where: { $0.id == top }) else { return }
            scrolledByReader = false
            withAnimation(.smooth) { store.moveRibbon(to: verse) }
        }
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
        style.weight = (QuranTextWeight(rawValue: textWeight) ?? .regular).stroke
        return style
    }

    // MARK: Live recitation

    private func toggleListening() {
        if live.isListening {
            live.stop()
        } else if !ReciteIntroSheet.isNeeded(for: store.edition) {
            startListening()
        } else {
            showIntro = true
        }
    }

    /// Moves to the surah and verse of `word` and listens from there.
    private func follow(_ word: WordID) {
        if word.surah != surahID { surahID = word.surah }
        let verses = store.verses(for: word.surah)
        let words = verses.map { QuranWords.shared.words(for: $0, edition: store.edition) }
        var start = 0
        for verseWords in words {
            if verseWords.key.verse >= word.verse { break }
            start += verseWords.words.count
        }
        live.move(verses: words, at: start + word.index, searchingAhead: 300)
        let target = word.surah * 1000 + word.verse
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.5)) { position.scrollTo(id: target, anchor: .center) }
        }
    }

    /// Listens across the whole surah, starting the search at the verse at
    /// the top of the screen.
    private func startListening() {
        let verses = store.verses(for: surahID)
        let words = verses.map { QuranWords.shared.words(for: $0, edition: store.edition) }
        // Found by reciting: start at the ayah that was found; otherwise the top of the screen.
        let found = handoffVerse.flatMap { store.verse(VerseReference(surah: surahID, verse: $0))?.id }
        handoffVerse = nil
        let top = found ?? visibleVerses.min() ?? store.ribbon.flatMap { $0.surah == surahID ? surahID * 1000 + $0.verse : nil }
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
    let isSaved: Bool
    let hasRibbon: Bool
    let isReciting: Bool
    let showsPlay: Bool
    let onPlay: () -> Void
    let onPlaceRibbon: () -> Void
    let onToggleSaved: () -> Void

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
                Button(action: onToggleSaved) {
                    Image(systemName: isSaved ? "star.fill" : "star")
                        .font(.subheadline)
                        .foregroundStyle(isSaved ? Palette.highlight : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: isSaved)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.pressable)
                .haptic(.impact(weight: .medium), trigger: isSaved)
                .accessibilityLabel(isSaved ? "Remove from saved verses" : "Save verse")
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
        // The ribbon hangs from the top of the verse it marks, between the
        // verse number and the buttons.
        .overlay(alignment: .top) {
            if hasRibbon {
                RibbonMark(color: Palette.highlight, starColor: Palette.base)
                    .frame(width: 16, height: 30)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityElement()
                    .accessibilityLabel("Your ribbon is here")
            }
        }
        .animation(.smooth(duration: 0.4), value: isReciting)
        .contextMenu {
            if showsPlay {
                Button("Play from here", systemImage: "play.fill") { onPlay() }
            }
            if !hasRibbon {
                Button("Move the ribbon here", systemImage: "bookmark") { onPlaceRibbon() }
            }
            Button(isSaved ? "Remove from saved verses" : "Save verse",
                   systemImage: isSaved ? "star.slash" : "star") { onToggleSaved() }
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
