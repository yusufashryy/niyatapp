import SwiftUI
import UIKit

/// The Qur'an page by page, laid out like the printed Madinah mushaf: the
/// same 604 pages and the same 15 lines on each page, each line justified to
/// the full width. The line breaks come from a published layout of the
/// Madinah mushaf, checked word by word against Niyat's verified text, which
/// is what's drawn (see MushafLayout and docs/SOURCES.md).
///
/// Everything happens on the page: tap a verse for its options, play the
/// recitation (the page follows the reciter word by word when it can),
/// recite yourself with the microphone, or hide the text to recite from memory.
struct MushafPageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var store = QuranStore.shared
    @State private var layout = MushafLayout.shared
    @State private var tajweedStore = TajweedStore.shared
    @State private var goal = QuranGoalModel.shared
    @State private var player = RecitationPlayer.shared
    @State private var live = LiveRecitation.shared
    @State private var highlights = WordHighlights.shared
    @AppStorage("quran.mushafPage") private var page = 1
    @AppStorage("quran.tajweed") private var tajweedOn = true
    @State private var options = MushafOptions.load()
    @State private var selected: Verse?
    /// Show the verse options at the top when the tapped verse is low on the page.
    @State private var actionsAtTop = false
    @State private var showJump = false
    @State private var showOptions = false
    @State private var showReview = false
    @State private var showIntro = false
    /// First page of the text live recitation is following.
    @State private var listeningFrom = 1
    /// The page was turned to follow the recitation, not by the reader.
    @State private var followedTurn = false

    /// Mushaf pages are laid out for the Uthmani script (Hafs); the "fewer
    /// marks" edition has exactly the same words.
    private var isSupported: Bool { store.edition == .uthmani || store.edition == .uthmaniMinimal }

    /// Tajweed colours are for the Uthmani text they were made for.
    private var showsTajweed: Bool { tajweedOn && store.edition == .uthmani && tajweedStore.isLoaded }

    var body: some View {
        let colors = options.style.colors
        ZStack {
            Color(colors.paper).ignoresSafeArea()
            if !isSupported {
                unsupported
            } else if layout.isLoaded, store.isLoaded {
                pages(colors)
            } else {
                ProgressView().tint(Color(colors.label))
            }
        }
        // Verse options float over the page, above the control bar: at the
        // bottom, or at the top when the verse is low on the page.
        .overlay(alignment: selected != nil && actionsAtTop ? .top : .bottom) {
            if let selected {
                MushafVerseActions(verse: selected, showTranslation: options.showTranslation,
                                   canPlay: store.edition.riwayah.hasVerseAudio,
                                   isBookmarked: store.isBookmarked(selected),
                                   onPlayFromHere: { play(from: selected) },
                                   onPlayVerse: { play(from: selected, only: true) },
                                   onBookmark: { store.toggleBookmark(selected) },
                                   onClose: { select(nil) })
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .transition(.move(edge: actionsAtTop ? .top : .bottom).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom) { controls(colors) }
        .overlay(alignment: .top) {
            if let error = player.errorMessage {
                Text(error)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .glassEffect(.regular.tint(.red.opacity(0.3)), in: .capsule)
                    .padding(.top, 36)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if let streak = goal.celebration {
                GoalCelebration(streak: streak) { goal.celebration = nil }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .background { PageFollower { follow($0) } }
        .animation(.smooth, value: selected)
        .animation(.bouncy, value: goal.celebration)
        .preferredColorScheme(colors.isLight ? .light : .dark)
        // Sheets keep the app's dark look, whatever the paper.
        .sheet(isPresented: $showJump) { MushafJumpSheet(page: $page).preferredColorScheme(.dark) }
        .sheet(isPresented: $showOptions) { MushafOptionsSheet(options: $options).preferredColorScheme(.dark) }
        .sheet(isPresented: $showReview) {
            RecitationReviewSheet(onListen: listenAction, onGoTo: { key in go(to: key) })
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showIntro) {
            ReciteIntroSheet(edition: store.edition) { startListening() }
                .preferredColorScheme(.dark)
        }
        .alert("Recite with Niyat", isPresented: unavailableBinding) {
            Button("OK", role: .cancel) { live.acknowledge() }
        } message: {
            if case .unavailable(let message) = live.status { Text(message) }
        }
        .onChange(of: options) { _, new in new.save() }
        .onChange(of: page) { _, new in pageChanged(to: new) }
        // Follow the recitation onto the page of the verse being recited.
        .onChange(of: player.current) { _, current in
            guard options.followRecitation, case .verse(let surah, let verse)? = current,
                  let displayed = store.verse(VerseReference(surah: surah, verse: verse)) else { return }
            follow(WordID(surah: displayed.surah, verse: displayed.number, index: 0))
        }
        .onChange(of: live.isListening) { _, _ in updateIdleTimer() }
        .onAppear {
            page = min(max(page, 1), MushafLayout.pageCount)
            updateIdleTimer()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            // Leaving the pages ends listening, memorisation and the review.
            live.stop()
            live.clearReview()
            highlights.setHidden(false)
            select(nil)
        }
        .task {
            await store.load()
            await layout.load()
            await tajweedStore.load()
            // Opened while listening to the reciter: go to that verse.
            if case .verse(let surah, let verse)? = player.current,
               let displayed = store.verse(VerseReference(surah: surah, verse: verse)) {
                page = layout.page(containing: WordID(surah: displayed.surah, verse: displayed.number, index: 0))
            }
        }
    }

    // MARK: Pages

    private func pages(_ colors: MushafColors) -> some View {
        // Pages turn right to left, like a printed mushaf.
        TabView(selection: $page) {
            ForEach(1...MushafLayout.pageCount, id: \.self) { number in
                MushafPage(number: number, isCurrent: number == page, colors: colors, tajweed: showsTajweed,
                           highContrast: contrast == .increased) { word, row in
                    tapped(word, row: row)
                }
                .environment(\.layoutDirection, .leftToRight)
                .tag(number)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, .rightToLeft)
        .haptic(.selection, trigger: page)
        .overlay(alignment: .top) {
            LiveRecitationStatus(light: colors.isLight)
                .frame(height: MushafMetrics.headerHeight)
                .allowsHitTesting(false)
        }
    }

    private var unsupported: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.pages")
                .font(.system(size: 44))
                .foregroundStyle(Palette.highlight)
            Text("Mushaf pages use the Uthmani script")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text("The 15-line pages follow the Madinah mushaf, which is written in the Uthmani script (Hafs). You're reading the \(store.edition.title) text.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Use the Uthmani script") {
                player.stop()
                Task { await store.setEdition(.uthmani) }
            }
            .buttonStyle(.glassProminent)
        }
        .padding(32)
    }

    // MARK: Controls

    /// The bar under the page. The microphone and the eye (memorisation) sit
    /// next to play; while the reciter plays, previous and next join them.
    private func controls(_ colors: MushafColors) -> some View {
        let playing = player.current != nil
        let tint = Color(colors.label)
        let active = Color(colors.marker)
        return HStack(spacing: 2) {
            barButton("Close", "xmark", tint: tint) { dismiss() }
            if playing {
                barButton("Previous verse", "backward.fill", tint: tint) { player.previous() }
                barButton("Next verse", "forward.fill", tint: tint) { player.next() }
                barButton(player.repeatVerse ? "Stop repeating verse" : "Repeat verse", "repeat.1",
                          tint: player.repeatVerse ? active : tint) { player.repeatVerse.toggle() }
            } else {
                barButton("Go to page, juz or surah", "list.bullet", tint: tint) { showJump = true }
                barButton(isPageBookmarked ? "Remove bookmark" : "Bookmark this page",
                          isPageBookmarked ? "bookmark.fill" : "bookmark",
                          tint: isPageBookmarked ? active : tint) { bookmarkPage() }
            }
            if highlights.flaggedCount > 0 {
                Button { showReview = true } label: {
                    Label("\(highlights.flaggedCount)", systemImage: "text.badge.checkmark")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(active)
                        .padding(.horizontal, 8)
                        .frame(height: 40)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Review \(highlights.flaggedCount) marked words")
            }
            Spacer(minLength: 0)
            barButton(highlights.isHidden ? "Show the text" : "Hide the text to recite from memory",
                      highlights.isHidden ? "eye.slash.fill" : "eye.slash",
                      tint: highlights.isHidden ? active : tint) { highlights.setHidden(!highlights.isHidden) }
            Button(action: toggleListening) {
                Image(systemName: live.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(live.isListening ? active : tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: live.isListening)
                    .frame(width: 40, height: 40)
                    .background(active.opacity(live.isListening ? 0.18 : 0), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(live.isListening ? "Stop listening" : "Recite: follow along as I recite")
            if store.edition.riwayah.hasVerseAudio {
                Button(action: togglePlay) {
                    Group {
                        if player.isLoading {
                            ProgressView().tint(tint)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play recitation")
            }
            if playing {
                barButton("Stop recitation", "stop.fill", tint: tint) { withAnimation(.smooth) { player.stop() } }
            } else {
                barButton("Page settings", "textformat.size", tint: tint) { showOptions = true }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .haptic(.selection, trigger: highlights.isHidden)
        .haptic(.impact(weight: .light), trigger: live.isListening)
        .animation(.smooth, value: playing)
        .animation(.smooth, value: highlights.flaggedCount)
    }

    private func barButton(_ label: String, _ icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }

    private var unavailableBinding: Binding<Bool> {
        Binding(get: {
            if case .unavailable = live.status { return true }
            return false
        }, set: { shown in
            if !shown { live.acknowledge() }
        })
    }

    // MARK: Actions

    private var isPageBookmarked: Bool {
        store.verses(onPage: page).first.map(store.isBookmarked) ?? false
    }

    private func bookmarkPage() {
        if let first = store.verses(onPage: page).first { store.toggleBookmark(first) }
    }

    private func tapped(_ word: WordID?, row: Int) {
        guard let word, let verse = displayedVerse(word.verseKey) else {
            select(nil)
            return
        }
        if options.tapAction == .play, store.edition.riwayah.hasVerseAudio {
            play(from: verse)
        } else if selected?.id == verse.id {
            select(nil)
        } else {
            actionsAtTop = row >= 8
            select(verse)
        }
    }

    /// Selects a verse (a band behind it) or clears the selection.
    private func select(_ verse: Verse?) {
        withAnimation(.smooth) { selected = verse }
        if let verse {
            highlights.setBand(VerseKey(surah: verse.surah, verse: verse.number))
        } else if case .verse(let surah, let number)? = player.current,
                  let playing = store.verse(VerseReference(surah: surah, verse: number)) {
            highlights.setBand(VerseKey(surah: playing.surah, verse: playing.number))
        } else {
            highlights.setBand(nil)
        }
    }

    private func displayedVerse(_ key: VerseKey) -> Verse? {
        let verses = store.verses(for: key.surah)
        return verses.indices.contains(key.verse - 1) ? verses[key.verse - 1] : nil
    }

    private func play(from verse: Verse, only: Bool = false) {
        live.stop()
        let reference = verse.hafsReference
        player.play(surah: reference.surah, from: reference.verse, verseCounts: store.hafsVerseCounts,
                    acrossSurahs: true, only: only)
        withAnimation(.smooth) { selected = nil }
    }

    private func play(_ key: VerseKey) {
        if let verse = displayedVerse(key) { play(from: verse, only: true) }
    }

    /// "Listen" in the review, when there's audio for the reading.
    private var listenAction: ((VerseKey) -> Void)? {
        guard store.edition.riwayah.hasVerseAudio else { return nil }
        return { key in play(key) }
    }

    private func togglePlay() {
        if player.current != nil {
            player.togglePlayPause()
        } else if let verse = selected ?? store.verses(onPage: page).first {
            play(from: verse)
        }
    }

    private func go(to key: VerseKey) {
        page = layout.page(containing: WordID(surah: key.surah, verse: key.verse, index: 0))
        if let verse = displayedVerse(key) {
            actionsAtTop = false
            select(verse)
        }
    }

    /// Turns to the page of the word being recited (by the reciter or you).
    private func follow(_ word: WordID) {
        guard options.followRecitation || live.isListening else { return }
        let target = layout.page(containing: word)
        guard target != page else { return }
        followedTurn = true
        withAnimation(.smooth) { page = target }
    }

    private func pageChanged(to newPage: Int) {
        if selected != nil { select(nil) }
        let followed = followedTurn
        followedTurn = false
        guard live.isListening else { return }
        // Turned by hand: listen on this page. Followed: only once the
        // recitation nears the end of the pages being followed.
        if !followed || newPage >= listeningFrom + Self.listeningPages - 2 {
            listeningFrom = newPage
            live.move(verses: listeningVerses(from: newPage), at: startIndex(onPage: newPage), searchingAhead: 300)
        }
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

    private func startListening() {
        select(nil)
        listeningFrom = page
        let verses = listeningVerses(from: page)
        let start = startIndex(onPage: page)
        Task { await live.start(verses: verses, edition: store.edition, at: start, searchingAhead: 300) }
        updateIdleTimer()
    }

    /// How many pages of text live recitation follows at a time.
    private static let listeningPages = 6

    /// The verses on `first` and the pages after it, so the recitation can be
    /// followed across page turns.
    private func listeningVerses(from first: Int) -> [VerseWords] {
        var keys: [VerseKey] = []
        for number in first...min(first + Self.listeningPages - 1, MushafLayout.pageCount) {
            for key in MushafPageText.page(number)?.verses ?? [] where keys.last.map({ $0 < key }) ?? true {
                keys.append(key)
            }
        }
        return keys.compactMap(displayedVerse).map { QuranWords.shared.words(for: $0, edition: store.edition) }
    }

    /// Where the first word of `page` is among the words of `listeningVerses(from: page)`:
    /// the page may start in the middle of a verse.
    private func startIndex(onPage page: Int) -> Int {
        layout.firstWord(onPage: page)?.index ?? 0
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = options.keepScreenOn || live.isListening
    }
}

/// Calls back when the word being followed changes. Only this small view
/// reads it, so the pages aren't re-evaluated for every word.
private struct PageFollower: View {
    let onWord: (WordID) -> Void
    @State private var highlights = WordHighlights.shared

    var body: some View {
        Color.clear
            .onChange(of: highlights.activeWord) { _, word in
                if let word { onWord(word) }
            }
    }
}
