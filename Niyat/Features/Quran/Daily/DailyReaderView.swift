import SwiftUI

/// The daily reader: one ayah at a time, with where it sits in the Qur'an,
/// its translation, recitation and tafsir. An ayah counts towards today's
/// goal when you read on past it (Next or a swipe), or hear it to the end.
/// It keeps its own green bookmark, apart from the reader's red ribbon; the
/// pencil chooses where it reads from.
struct DailyReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var store = QuranStore.shared
    @State private var goal = QuranGoalModel.shared
    @State private var player = RecitationPlayer.shared
    @State private var tajweedStore = TajweedStore.shared
    @AppStorage("quran.arabicSize") private var arabicSize = 30.0
    @AppStorage("quran.showTranslation") private var showTranslation = true
    @AppStorage("quran.tajweed") private var tajweedOn = true
    @AppStorage(QuranLineSpacing.key) private var lineHeight = QuranLineSpacing.standard
    @AppStorage(QuranTextWeight.key) private var textWeight = QuranTextWeight.regular.rawValue

    @State private var place = DailyPlace(surah: 1, verse: 1)
    @State private var started = false
    /// Moving forwards (true) or back, for the slide.
    @State private var forwards = true
    @State private var tafsirTarget: TafsirTarget?
    @State private var sharing: QuranShareContent?
    @State private var showGoal = false
    @State private var choosingStart = false
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
                            // Swipe the ayah sideways to move, like turning a page.
                            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { drag in
                                guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5,
                                      abs(drag.translation.width) > 60 else { return }
                                move(forwards: drag.translation.width < 0)
                            })
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
        .sheet(isPresented: $choosingStart) {
            DailyStartSheet(start: place, verseCounts: verseCounts) { chosen in
                player.stop()
                forwards = chosen.surah * 1000 + chosen.verse >= place.surah * 1000 + place.verse
                withAnimation(.smooth(duration: 0.35)) { place = chosen }
            }
        }
        .sheet(isPresented: $showSummary, onDismiss: { dismiss() }) {
            DailySummarySheet(countedNow: countedThisVisit)
        }
        .task {
            await store.load()
            guard !started else { return }
            verseCounts = (1...114).map { store.verseCount(for: $0) }
            started = true
            let ribbon = store.ribbon.map { DailyPlace(surah: $0.surah, verse: $0.verse) }
            place = DailyReading.start(mark: store.dailyPlace, ribbon: ribbon, verseCounts: verseCounts)
            if let verse { store.setDailyMark(to: verse) }
        }
        // The green bookmark stays on the ayah you're on.
        .onChange(of: place) { _, _ in
            if started, let verse { store.setDailyMark(to: verse) }
        }
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

    /// Ayat per surah in the shown reading, worked out once the text is loaded.
    @State private var verseCounts: [Int] = Array(repeating: 0, count: 114)

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

    /// The ayah: listen and tafsir, where it is, choose where to read and
    /// share; the Arabic. The translation sits below.
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
                            // The ayah number is in the dock below; here, the surah's name in Arabic.
                            Text(store.surah(place.surah)?.name ?? "")
                                .font(.calligraphy(size: 17))
                                .foregroundStyle(Palette.highlight.opacity(0.85))
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
                        startButton
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

    /// The pencil: choose where the daily reading goes from.
    private var startButton: some View {
        Button { choosingStart = true } label: {
            Image(systemName: "pencil")
                .font(.title3)
                .foregroundStyle(Color(QuranTextStyle.dailyGreen))
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose where to read")
        .accessibilityHint("Moves your daily reading, and its green bookmark, to another ayah")
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

    /// A small centred dock: back, where you are, forward.
    private var controls: some View {
        let canGoBack = DailyReading.previous(before: place, verseCounts: verseCounts) != nil
        let canGoOn = DailyReading.next(after: place, verseCounts: verseCounts) != nil
        return HStack(spacing: 0) {
            Button { move(forwards: false) } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(canGoBack ? 0.9 : 0.25))
                    .frame(width: 52, height: 52)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .accessibilityLabel("Previous ayah")

            // Where you are: the ayah's number in a star, like the mushaf's ayah marks.
            HStack(spacing: 10) {
                ZStack {
                    EightPointStar()
                        .stroke(Palette.highlight.opacity(0.8), lineWidth: 1.2)
                    Text("\(place.verse)")
                        .font(.system(size: place.verse > 99 ? 11 : 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.highlight)
                        .contentTransition(.numericText(value: Double(place.verse)))
                }
                .frame(width: 34, height: 34)
                Text("of \(verseCounts[place.surah - 1])")
                    .font(.footnote.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 110)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ayah \(place.verse) of \(verseCounts[place.surah - 1])")

            Button { move(forwards: true) } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Palette.control.gradient, in: .circle)
                    .opacity(canGoOn ? 1 : 0.35)
                    .frame(width: 52, height: 52)
                    .contentShape(.circle)
            }
            .buttonStyle(.pressable)
            .disabled(!canGoOn)
            .accessibilityLabel("Next ayah")
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .animation(.smooth, value: place)
        .haptic(.selection, trigger: place)
    }

    // MARK: Actions

    private func move(forwards: Bool) {
        let target = forwards
            ? DailyReading.next(after: place, verseCounts: verseCounts)
            : DailyReading.previous(before: place, verseCounts: verseCounts)
        guard let target else { return }
        // Reading on past an ayah counts it.
        if DailyReading.countsWhenMoving(forwards: forwards), let verse { record(verse) }
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

    private func record(_ verse: Verse) {
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
