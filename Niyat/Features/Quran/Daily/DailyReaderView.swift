import SwiftUI

/// The daily reader: one ayah at a time, with where it sits in the Qur'an,
/// its translation, recitation and tafsir. An ayah counts towards today's
/// goal only after it has been on screen long enough to read, or heard to the end.
struct DailyReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var store = QuranStore.shared
    @State private var goal = QuranGoalModel.shared
    @State private var player = RecitationPlayer.shared
    @State private var tajweedStore = TajweedStore.shared
    @AppStorage(DailyReading.placeKey) private var savedPlace = ""
    @AppStorage("quran.arabicSize") private var arabicSize = 30.0
    @AppStorage("quran.showTranslation") private var showTranslation = true
    @AppStorage("quran.tajweed") private var tajweedOn = true
    @AppStorage(QuranLineSpacing.key) private var lineHeight = QuranLineSpacing.standard
    @AppStorage(QuranTextWeight.key) private var textWeight = QuranTextWeight.regular.rawValue
    @AppStorage(ReadingRibbon.followsKey) private var ribbonFollows = true

    @State private var place = DailyPlace(surah: 1, verse: 1)
    @State private var started = false
    /// Moving forwards (true) or back, for the slide.
    @State private var forwards = true
    /// How far through its reading time the shown ayah is (0...1).
    @State private var readProgress = 0.0
    @State private var tafsirTarget: TafsirTarget?
    @State private var sharing: QuranShareContent?
    @State private var showGoal = false
    @State private var showSummary = false
    /// Ayat counted since the reader opened.
    @State private var countedThisVisit = 0
    /// When the current stretch of reading began (nil while in the background).
    @State private var sittingStart: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let verse {
                    VStack(spacing: 22) {
                        goalBar(verse)
                        ayahCard(verse)
                            .id(place)
                            .transition(.push(from: forwards ? .trailing : .leading))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .readableWidth(720)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .niyatBackground()
            .navigationTitle("Daily reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { close() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                        .fontWeight(.semibold)
                        .accessibilityHint("Ends today's reading and shows what you read")
                }
            }
            .safeAreaInset(edge: .bottom) { controls }
            .overlay {
                if let streak = goal.celebration {
                    GoalCelebration(streak: streak) { goal.celebration = nil }
                }
            }
            .animation(.bouncy, value: goal.celebration)
        }
        .sheet(item: $tafsirTarget) { TafsirSheet(surah: $0.surah, ayah: $0.ayah) }
        .sheet(item: $sharing) { QuranShareSheet(content: $0) }
        .sheet(isPresented: $showGoal) { QuranGoalSheet() }
        .sheet(isPresented: $showSummary, onDismiss: { dismiss() }) {
            DailySummarySheet(countedNow: countedThisVisit)
        }
        .task {
            await store.load()
            guard !started else { return }
            started = true
            let ribbon = store.ribbon.map { DailyPlace(surah: $0.surah, verse: $0.verse) }
            place = DailyReading.start(saved: savedPlace, ribbon: ribbon, verseCounts: verseCounts)
        }
        // The reading clock runs only while the ayah is on screen and the app is open.
        .task(id: ReadingClock(place: place, active: scenePhase == .active && started && !showSummary)) {
            await runReadingClock()
        }
        .onChange(of: place) { _, new in savedPlace = new.storageKey }
        // Time spent reading: counted while the reader is open and the app is in front.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { sittingStart = sittingStart ?? .now } else { saveReadingTime() }
        }
        .onChange(of: player.current) { old, new in followRecitation(from: old, to: new) }
        .onDisappear {
            saveReadingTime()
            if player.current != nil { player.stop() }
            store.resumeRibbon()
        }
    }

    // MARK: Data

    private var verseCounts: [Int] { (1...114).map { store.verseCount(for: $0) } }

    private var verse: Verse? {
        let verses = store.verses(for: place.surah)
        return verses.indices.contains(place.verse - 1) ? verses[place.verse - 1] : nil
    }

    private func isCounted(_ verse: Verse) -> Bool {
        let reference = verse.hafsReference
        return goal.today.verses.contains("\(reference.surah):\(reference.verse)")
    }

    private var audioAvailable: Bool { store.edition.riwayah.hasVerseAudio }

    private var isPlayingHere: Bool { player.isPlaying }

    // MARK: Parts

    /// Today's goal as a bar: "7/10", where you are in the juz, and the
    /// percentage. Tapping it changes the goal.
    private func goalBar(_ verse: Verse) -> some View {
        let target = max(goal.goal ?? 0, 1)
        let reference = verse.hafsReference
        let juz = store.juz(containing: reference)
        let left = DailyReading.ayatLeftInJuz(after: DailyPlace(surah: reference.surah, verse: reference.verse),
                                              juzStarts: store.juzStarts.map { DailyPlace(surah: $0.surah, verse: $0.verse) },
                                              verseCounts: store.hafsVerseCounts)
        return Button { showGoal = true } label: {
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.accent, Palette.highlight],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * goal.progress)
                    }
                }
                .frame(height: 8)
                .animation(.smooth(duration: 0.5), value: goal.progress)
                HStack {
                    Text(goal.goal == nil ? "\(goal.today.count)" : "\(goal.today.count)/\(target)")
                        .contentTransition(.numericText(value: Double(goal.today.count)))
                    Spacer()
                    Text("Juz \(juz) · \(left) ayat left")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if goal.today.isComplete {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.highlight)
                    } else {
                        Text("\(Int(goal.progress * 100))%")
                    }
                }
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
            }
            .foregroundStyle(.white)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(goal.today.count) of \(target) ayat today. Juz \(juz), \(left) ayat left in it.")
        .accessibilityHint("Changes your daily goal")
    }

    /// The ayah: listen and tafsir, where it is, share; the Arabic; a thin
    /// line that fills while it's read. The translation sits below.
    private func ayahCard(_ verse: Verse) -> some View {
        let counted = isCounted(verse)
        let surahName = store.surah(place.surah)?.transliteration ?? "Surah \(place.surah)"
        let count = verseCounts[place.surah - 1]
        return VStack(spacing: 18) {
            VStack(spacing: 22) {
                HStack(alignment: .top) {
                    HStack(spacing: 2) {
                        if audioAvailable {
                            iconButton(isPlayingHere ? "pause.fill" : "speaker.wave.2",
                                       label: isPlayingHere ? "Pause" : "Listen") { toggleAudio() }
                        }
                        if store.edition.riwayah == .hafs {
                            iconButton("text.book.closed", label: "Tafsir") {
                                tafsirTarget = TafsirTarget(surah: verse.surah, ayah: verse.number)
                            }
                        }
                    }
                    .frame(width: 84, alignment: .leading)
                    Spacer(minLength: 4)
                    VStack(spacing: 3) {
                        Text("\(place.surah). \(surahName)")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        HStack(spacing: 5) {
                            Text("\(place.verse)/\(count)")
                            if counted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Palette.highlight)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(surahName), ayah \(place.verse) of \(count)\(counted ? ", counted" : "")")
                    Spacer(minLength: 4)
                    HStack(spacing: 2) {
                        ribbonButton(verse)
                        iconButton("square.and.arrow.up", label: "Share") { sharing = .verse(verse) }
                    }
                    .frame(width: 84, alignment: .trailing)
                }

                if verse.number == 1, let surah = store.surah(place.surah), store.showsBismillahHeader(for: surah),
                   let opening = store.verses(for: 1).first {
                    let words = QuranWords.shared.words(for: opening, edition: store.edition)
                    QuranTextView(pieces: [QuranTextPiece(words: words, range: 0...max(words.words.count - 1, 0),
                                                          showsVerseEnd: false)],
                                  style: textStyle(size: 24, ink: UIColor(Palette.highlight)),
                                  layout: .centredLine)
                        .frame(height: 48)
                        .frame(maxWidth: .infinity)
                }
                QuranTextView(pieces: [QuranTextPiece(verse: QuranWords.shared.words(for: verse, edition: store.edition))],
                              style: textStyle(size: arabicSize + 4, ink: .white), layout: .centredParagraph)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .surface(cornerRadius: 28)
            // Fills while the ayah is read; stays, dimmer, once it counts.
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Palette.highlight)
                        .frame(width: geo.size.width * (counted ? 1 : readProgress), height: 3)
                }
                .frame(height: 3)
                .padding(.horizontal, 28)
                .padding(.bottom, 10)
                .opacity(counted ? 0.45 : 1)
                .accessibilityHidden(true)
            }
            .animation(.smooth, value: counted)

            if showTranslation, !verse.translation.isEmpty {
                Text(verse.translation)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// The reading ribbon, shared with the reader and the mushaf: the place
    /// "where I left off". Red when it's on this ayah.
    private func ribbonButton(_ verse: Verse) -> some View {
        let here = store.hasRibbon(verse)
        return Button {
            withAnimation(.smooth) { store.toggleRibbon(verse) }
        } label: {
            Image(systemName: here ? "bookmark.fill" : "bookmark")
                .font(.title3)
                .foregroundStyle(here ? Color(QuranTextStyle.ribbonRed) : .white.opacity(0.85))
                .frame(width: 40, height: 40)
                .contentShape(.rect)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .haptic(.selection, trigger: here)
        .accessibilityLabel(here ? "Remove the ribbon" : "Move the ribbon here")
        .accessibilityHint("The ribbon marks where you left off, here, in the reader and in the mushaf")
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityLabel(label)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { move(forwards: false) } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 52, height: 52)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(DailyReading.previous(before: place, verseCounts: verseCounts) == nil)
            .accessibilityLabel("Previous ayah")

            Button { move(forwards: true) } label: {
                HStack(spacing: 6) {
                    Text("Next")
                    Image(systemName: "chevron.right")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.control)
            .disabled(DailyReading.next(after: place, verseCounts: verseCounts) == nil)
            .accessibilityLabel("Next ayah")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .readableWidth(720)
        .haptic(.selection, trigger: place)
    }

    // MARK: Actions

    private func move(forwards: Bool) {
        let target = forwards
            ? DailyReading.next(after: place, verseCounts: verseCounts)
            : DailyReading.previous(before: place, verseCounts: verseCounts)
        guard let target else { return }
        let wasPlaying = player.isPlaying
        self.forwards = forwards
        withAnimation(.smooth(duration: 0.35)) { place = target }
        if wasPlaying { playFromPlace() }
    }

    private func finish() {
        player.stop()
        saveReadingTime()
        showSummary = true
    }

    /// Adds the time since `sittingStart` to today (at most one long sitting).
    private func saveReadingTime() {
        guard let start = sittingStart else { return }
        sittingStart = nil
        let seconds = min(Int(Date.now.timeIntervalSince(start)), ReadingStats.longestSitting)
        goal.addReadingTime(seconds)
    }

    private func close() {
        player.stop()
        dismiss()
    }

    private func toggleAudio() {
        if player.isPlaying {
            player.togglePlayPause()
        } else if case .verse(let surah, let number)? = player.current, surah == place.surah, number == place.verse {
            player.togglePlayPause()
        } else {
            playFromPlace()
        }
    }

    /// Recites from the shown ayah onwards; the reader follows along.
    private func playFromPlace() {
        guard audioAvailable, let verse else { return }
        let reference = verse.hafsReference
        player.play(surah: reference.surah, from: reference.verse, verseCounts: store.hafsVerseCounts, acrossSurahs: true)
    }

    /// The recitation moved on: the ayah it finished was heard in full, so it
    /// counts, and the reader turns to the next one.
    private func followRecitation(from old: RecitationItem?, to new: RecitationItem?) {
        guard case .verse(let surah, let number)? = old, surah == place.surah, number == place.verse,
              let new, let verse else { return }
        record(verse)
        let next = DailyPlace(surah: new.surah, verse: new.verse ?? 1)
        guard next != place else { return }
        forwards = true
        withAnimation(.smooth(duration: 0.35)) { place = next }
    }

    private func runReadingClock() async {
        readProgress = 0
        guard started, scenePhase == .active, !showSummary, let verse, !isCounted(verse) else { return }
        let seconds = DailyReading.readingTime(letters: verse.letterCount)
        withAnimation(.linear(duration: seconds)) { readProgress = 1 }
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled else {
            readProgress = 0
            return
        }
        record(verse)
    }

    private func record(_ verse: Verse) {
        // Reading on carries the ribbon with you (unless you've turned that off,
        // or placed it further on yourself).
        if ribbonFollows { store.followRibbon(to: verse) }
        guard !isCounted(verse) else { return }
        goal.recordRead(verse)
        countedThisVisit += 1
    }

    private func textStyle(size: Double, ink: UIColor) -> QuranTextStyle {
        var style = QuranTextStyle()
        style.typeface = .for(store.edition)
        style.fontSize = CGFloat(size)
        style.lineHeight = CGFloat(lineHeight)
        style.ink = ink
        style.marker = UIColor(Palette.highlight)
        style.tajweed = tajweedOn && store.edition == .uthmani && tajweedStore.isLoaded
        style.dark = true
        style.highContrast = contrast == .increased
        style.weight = (QuranTextWeight(rawValue: textWeight) ?? .regular).stroke
        return style
    }
}

/// What restarts the reading clock: a new ayah, or the app coming back.
private struct ReadingClock: Equatable {
    let place: DailyPlace
    let active: Bool
}
