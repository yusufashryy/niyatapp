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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = QuranStore.shared
    @State private var layout = MushafLayout.shared
    @State private var tajweedStore = TajweedStore.shared
    @State private var goal = QuranGoalModel.shared
    @State private var player = RecitationPlayer.shared
    @State private var live = LiveRecitation.shared
    @State private var highlights = WordHighlights.shared
    @AppStorage("quran.mushafPage") private var page = 1
    @AppStorage("quran.tajweed") private var tajweedOn = true
    @AppStorage(QuranTextWeight.key) private var textWeight = QuranTextWeight.regular.rawValue
    @AppStorage(ReadingRibbon.followsKey) private var ribbonFollows = true
    @State private var options = MushafOptions.load()
    @State private var selected: Verse?
    /// Show the verse options at the top when the tapped verse is low on the page.
    @State private var actionsAtTop = false
    @State private var showJump = false
    @State private var tafsirTarget: TafsirTarget?
    @State private var sharing: QuranShareContent?
    @State private var showOptions = false
    @State private var showIntro = false
    /// First page of the text live recitation is following.
    @State private var listeningFrom = 1
    /// The page was turned to follow the recitation, not by the reader.
    @State private var followedTurn = false
    /// The page was set by a jump (the page list, the review, a recitation), not turned.
    @State private var jumpedTurn = false
    @State private var ribbonTask: Task<Void, Never>?
    /// Closing with "move the ribbon as I read" off: the page to offer it.
    @State private var ribbonOffer: Int?
    /// A page is zoomed in: turning is off until it's back to fit.
    @State private var isZoomed = false
    /// Two facing pages are showing.
    @State private var isSpread = false
    @State private var showScrubber = false

    /// Mushaf pages are laid out for the Uthmani script (Hafs); the "fewer
    /// marks" edition has exactly the same words.
    private var isSupported: Bool { store.edition == .uthmani || store.edition == .uthmaniMinimal }

    /// Tajweed colours are for the Uthmani text they were made for.
    private var showsTajweed: Bool { tajweedOn && store.edition == .uthmani && tajweedStore.isLoaded }

    var body: some View {
        screen
            // With "move the ribbon as I read" off, closing offers to move it here.
            .confirmationDialog("Move your ribbon to page \(ribbonOffer ?? page)?", isPresented: ribbonOfferBinding,
                                titleVisibility: .visible) {
                Button("Move the ribbon") {
                    moveRibbon(toPage: ribbonOffer ?? page)
                    dismiss()
                }
                Button(store.ribbonPage.map { "Leave it on page \($0)" } ?? "Not now") { dismiss() }
                Button("Keep reading", role: .cancel) {}
            }
    }

    @ViewBuilder private var screen: some View {
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
                                   isSaved: store.isBookmarked(selected),
                                   hasRibbon: store.hasRibbon(selected),
                                   onPlayFromHere: { play(from: selected) },
                                   onPlayVerse: { play(from: selected, only: true) },
                                   onRibbon: { withAnimation(.smooth) { store.toggleRibbon(selected) } },
                                   onSave: { store.toggleBookmark(selected) },
                                   onTafsir: store.edition.riwayah == .hafs
                                       ? { tafsirTarget = TafsirTarget(surah: selected.surah, ayah: selected.number) } : nil,
                                   onShare: { sharing = .verse(selected) },
                                   onClose: { select(nil) })
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .transition(.move(edge: actionsAtTop ? .top : .bottom).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar(colors) }
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
        // Two facing pages: a book across the whole screen. The status bar
        // steps aside and, on iPhone Duo, no bar runs down the side.
        .statusBarHidden(isSpread)
        .horizontalBarsOnly()
        .animation(.smooth, value: selected)
        .animation(.bouncy, value: goal.celebration)
        .preferredColorScheme(colors.isLight ? .light : .dark)
        // Sheets keep the app's dark look, whatever the paper.
        .sheet(isPresented: $showJump) { MushafJumpSheet(page: jumpBinding).preferredColorScheme(.dark) }
        .sheet(item: $tafsirTarget) { TafsirSheet(surah: $0.surah, ayah: $0.ayah).preferredColorScheme(.dark) }
        .sheet(item: $sharing) { QuranShareSheet(content: $0).preferredColorScheme(.dark) }
        .sheet(isPresented: $showOptions) { MushafOptionsSheet(options: $options).preferredColorScheme(.dark) }
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
        // Highlight the verse being recited.
        .onChange(of: player.current, initial: true) { _, _ in showPlayingBand() }
        // Follow the recitation onto the page of the verse being recited.
        .onChange(of: player.current) { _, current in
            guard options.followRecitation, case .verse(let surah, let verse)? = current,
                  let displayed = store.verse(VerseReference(surah: surah, verse: verse)) else { return }
            follow(WordID(surah: displayed.surah, verse: displayed.number, index: 0))
        }
        .onChange(of: live.isListening) { _, _ in updateIdleTimer() }
        // Recited from somewhere else in the Qur'an: go to that page and listen there.
        .onChange(of: live.jump) { _, recited in
            guard let recited else { return }
            let target = layout.page(containing: recited.word)
            if target != page { withAnimation(.smooth) { jump(to: target) } }
        }
        .onAppear {
            page = min(max(page, 1), MushafLayout.pageCount)
            updateIdleTimer()
        }
        .onDisappear {
            ribbonTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
            // Leaving the pages ends listening, memorisation and the review.
            store.resumeRibbon()
            live.stop()
            live.clearReview()
            highlights.setHidden(false)
            select(nil)
        }
        .task {
            await store.load()
            await layout.load()
            await tajweedStore.load()
            // Found by reciting from the Qur'an list: carry on following.
            if let found = RecitationHandoff.pending {
                RecitationHandoff.pending = nil
                try? await Task.sleep(for: .milliseconds(600))
                if !live.isListening {
                    if ReciteIntroSheet.isNeeded(for: store.edition) {
                        showIntro = true
                    } else {
                        startListening(at: found)
                    }
                }
            }
            // Opened while listening to the reciter: go to that verse.
            if case .verse(let surah, let verse)? = player.current,
               let displayed = store.verse(VerseReference(surah: surah, verse: verse)) {
                jump(to: layout.page(containing: WordID(surah: displayed.surah, verse: displayed.number, index: 0)))
            }
        }
    }

    // MARK: Pages

    /// Pages turn right to left, like a printed mushaf: curled like paper
    /// (or slid, with Reduce Motion), and two facing pages on a wide screen.
    private func pages(_ colors: MushafColors) -> some View {
        // The same room on the left and the right, so the pages sit in the
        // middle of the screen. On iPhone Duo the status bar (and any bar)
        // is down one side only; without this the book sat off the fold.
        GeometryReader { window in
            let side = max(window.safeAreaInsets.leading, window.safeAreaInsets.trailing)
            GeometryReader { geo in
                let spread = options.twoPages && MushafBook.spreadFits(width: geo.size.width, height: geo.size.height)
                Group {
                    if MushafBook.turn(chosen: options.pageTurn, reduceMotion: reduceMotion) == .curl {
                        MushafCurlPager(page: $page, spread: spread, isEnabled: !isZoomed, paper: colors.paper) { number in
                            pageView(number, colors: colors, placement: placement(of: number, spread: spread), spread: spread)
                        }
                        .id(spread)
                    } else {
                        slidePages(colors, spread: spread)
                    }
                }
                .onChange(of: spread, initial: true) { _, wide in isSpread = wide }
            }
            .padding(.horizontal, side)
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .haptic(.selection, trigger: page)
        .animation(.smooth, value: store.ribbon)

    }

    private func slidePages(_ colors: MushafColors, spread: Bool) -> some View {
        let numbers = spread ? Array(stride(from: 1, through: MushafBook.pageCount, by: 2)) : Array(1...MushafBook.pageCount)
        return TabView(selection: spread ? spreadSelection : $page) {
            ForEach(numbers, id: \.self) { number in
                HStack(spacing: 0) {
                    if spread, let left = MushafBook.spread(containing: number).left {
                        pageView(left, colors: colors, placement: .left, spread: true)
                    }
                    pageView(number, colors: colors, placement: spread ? .right : .single, spread: spread)
                }
                .environment(\.layoutDirection, .leftToRight)
                .tag(number)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, .rightToLeft)
    }

    /// With two pages showing, the pager moves by spreads (named by their right page).
    private var spreadSelection: Binding<Int> {
        Binding(get: { MushafBook.spread(containing: page).right }, set: { page = $0 })
    }

    private func placement(of number: Int, spread: Bool) -> MushafBook.Placement {
        guard spread else { return .single }
        return number.isMultiple(of: 2) ? .left : .right
    }

    /// The pages in view: the current one, or both pages of its spread.
    private func isShowing(_ number: Int, spread: Bool) -> Bool {
        guard spread else { return number == page }
        let shown = MushafBook.spread(containing: page)
        return number == shown.right || number == shown.left
    }

    private func pageView(_ number: Int, colors: MushafColors, placement: MushafBook.Placement, spread: Bool) -> some View {
        MushafPage(number: number, isCurrent: isShowing(number, spread: spread), colors: colors, tajweed: showsTajweed,
                   highContrast: contrast == .increased, textSize: options.textSize,
                   weight: (QuranTextWeight(rawValue: textWeight) ?? .regular).stroke,
                   hasRibbon: number == store.ribbonPage, placement: placement,
                   onZoomChange: { isZoomed = $0 },
                   onPageNumber: { showScrubber.toggle() },
                   onTap: { word, row in tapped(word, row: row) })
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

    /// Under the page: the review pill, the scrubber when open, and the control bar.
    private func bottomBar(_ colors: MushafColors) -> some View {
        VStack(spacing: 8) {
            // Status and review only while there's something to say; Recite is in the bar.
            RecitationDock(light: colors.isLight, showsButton: false, onRecite: toggleListening)
            if showScrubber {
                MushafScrubber(page: page, colors: colors) { jump(to: $0) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            controls(colors)
        }
        .readableWidth(600)
        .animation(.smooth, value: highlights.flaggedCount > 0)
        .animation(.smooth, value: showScrubber)
    }

    /// The bar under the page. The eye (memorisation) sits next to play; while
    /// the reciter plays, previous and next join them. Recite is its own button
    /// above the bar.
    private func controls(_ colors: MushafColors) -> some View {
        let playing = player.current != nil
        let tint = Color(colors.label)
        let active = Color(colors.marker)
        return HStack(spacing: 2) {
            barButton("Close", "xmark", tint: tint) { close() }
            if playing {
                barButton("Previous verse", "backward.fill", tint: tint) { player.previous() }
                barButton("Next verse", "forward.fill", tint: tint) { player.next() }
                barButton(player.repeatVerse ? "Stop repeating verse" : "Repeat verse", "repeat.1",
                          tint: player.repeatVerse ? active : tint) { player.repeatVerse.toggle() }
            } else {
                barButton("Go to page, juz or surah", "list.bullet", tint: tint) { showJump = true }
                barButton(isRibbonHere ? "Remove the ribbon" : "Move the ribbon to this page",
                          isRibbonHere ? "bookmark.fill" : "bookmark",
                          tint: isRibbonHere ? active : tint) {
                    if isRibbonHere { withAnimation(.smooth) { store.removeRibbon() } } else { moveRibbon(toPage: page) }
                }
            }
            Spacer(minLength: 0)
            barButton(highlights.isHidden ? "Show the text" : "Hide the text to recite from memory",
                      highlights.isHidden ? "eye.slash.fill" : "eye.slash",
                      tint: highlights.isHidden ? active : tint) { highlights.setHidden(!highlights.isHidden) }
            ReciteButton(size: 44, action: toggleListening)
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

    private var isRibbonHere: Bool {
        guard let ribbonPage = store.ribbonPage else { return false }
        return isShowing(ribbonPage, spread: isSpread)
    }

    /// Puts the ribbon at the first verse that starts on a page (by hand,
    /// or following the reader).
    private func moveRibbon(toPage number: Int, following: Bool = false) {
        guard let first = store.verses(onPage: number).first else { return }
        withAnimation(.smooth) {
            if following { store.followRibbon(to: first) } else { store.moveRibbon(to: first) }
        }
    }

    /// The ribbon follows you onto a page you turned to yourself, once it has
    /// stayed open long enough to be read.
    private func scheduleRibbon(onPage number: Int, turnedByHand: Bool) {
        ribbonTask?.cancel()
        let verses = store.verses(onPage: number)
        guard !verses.isEmpty, ReadingRibbon.shouldMove(follows: ribbonFollows, movedByReader: turnedByHand) else { return }
        ribbonTask = Task {
            try? await Task.sleep(for: .seconds(ReadingRibbon.pageDwell(verseCount: verses.count)))
            guard !Task.isCancelled else { return }
            moveRibbon(toPage: number, following: true)
        }
    }

    /// Close, first offering to move the ribbon here when it doesn't follow you.
    private func close() {
        if let offer = ReadingRibbon.pageToOffer(follows: ribbonFollows, ribbonPage: store.ribbonPage, currentPage: page) {
            ribbonOffer = offer
        } else {
            dismiss()
        }
    }

    private var ribbonOfferBinding: Binding<Bool> {
        Binding(get: { ribbonOffer != nil }, set: { shown in if !shown { ribbonOffer = nil } })
    }

    /// Goes to a page without it counting as turned there by hand.
    private func jump(to target: Int) {
        guard target != page else { return }
        jumpedTurn = true
        page = target
    }

    /// The page list's choice is a jump.
    private var jumpBinding: Binding<Int> {
        Binding(get: { page }, set: { jump(to: $0) })
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
        } else {
            showPlayingBand()
        }
    }

    /// The band follows the verse being recited, unless a verse is selected.
    /// Driven by `player.current` (what the mini player shows), so it doesn't
    /// depend on the order the audio callbacks arrive in.
    private func showPlayingBand() {
        guard selected == nil else { return }
        if case .verse(let surah, let number)? = player.current,
           let playing = store.verse(VerseReference(surah: surah, verse: number)) {
            highlights.setBand(VerseKey(surah: playing.surah, verse: playing.number))
        } else if live.isListening, let recited = highlights.activeVerse {
            // Back to the ayah being recited.
            highlights.setBand(recited)
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
        jump(to: layout.page(containing: WordID(surah: key.surah, verse: key.verse, index: 0)))
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
        let jumped = jumpedTurn
        followedTurn = false
        jumpedTurn = false
        scheduleRibbon(onPage: newPage, turnedByHand: !followed && !jumped)
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
        } else if !ReciteIntroSheet.isNeeded(for: store.edition) {
            startListening()
        } else {
            showIntro = true
        }
    }

    /// Listens from this page; `found` is a place found by reciting, where
    /// following starts (and which is highlighted at once).
    private func startListening(at found: VerseReference? = nil) {
        select(nil)
        listeningFrom = page
        let verses = listeningVerses(from: page)
        var start = startIndex(onPage: page)
        var focus: VerseKey?
        if let found {
            let key = VerseKey(surah: found.surah, verse: found.verse)
            if let at = verses.firstIndex(where: { $0.key == key }) {
                start = verses[..<at].reduce(0) { $0 + $1.words.count }
                focus = key
            }
        }
        Task { await live.start(verses: verses, edition: store.edition, at: start, searchingAhead: 300, focus: focus) }
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
