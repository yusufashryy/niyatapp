import SwiftUI

struct SurahListView: View {
    @State private var store = QuranStore.shared
    @State private var searchText = ""
    /// The surah open in the reader, kept per window through folding, unfolding
    /// and the app closing in the background ("" when none).
    @SceneStorage("quran.openSurah") private var openSurah = ""
    /// On a narrow screen (iPhone, iPhone Duo closed) the list and the reader
    /// share one stack; this says which shows.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var restored = false
    @State private var goal = QuranGoalModel.shared
    @State private var deepLink = DeepLink.shared
    @State private var showSettings = false
    @State private var showGoal = false
    @State private var showDaily = false
    @State private var showMushaf = false
    @State private var showNotifications = false
    @State private var showFinder = false
    @State private var verseBookmarks = VerseBookmarkStore.shared
    @State private var editingBookmark: VerseBookmark?
    /// Counts places found by reciting, so finding the verse that's already
    /// open still opens it afresh and starts following.
    @State private var foundCount = 0
    /// "verses" (default) opens surahs verse by verse; "pages" in the mushaf view.
    @AppStorage("quran.readingLayout") private var readingLayout = "verses"
    @AppStorage("quran.mushafPage") private var mushafPage = 1

    var body: some View {
        // The list beside the reader when there's room (iPhone Duo open, iPad);
        // one stack, as before, when there isn't.
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            Group {
                if let error = store.loadError {
                    ContentUnavailableView("Quran unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if !store.isLoaded {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .niyatBackground()
            .sheet(item: $editingBookmark) { BookmarkSheet(reference: $0.verse, editing: $0) }
            .sheet(isPresented: $showFinder) {
                FindByRecitingSheet { place in
                    RecitationHandoff.pending = place
                    foundCount += 1
                    open(ReaderDestination(surah: place.surah, verse: place.verse))
                }
            }
            .navigationTitle("Quran")
            // The reader hides the tab bar on iPhone; it comes back here.
            .toolbar(.visible, for: .tabBar)
            // Wide enough for the Duas and Mushaf tiles side by side.
            .navigationSplitViewColumnWidth(min: 340, ideal: 380, max: 440)
            .searchable(text: $searchText, prompt: "Surah name or number")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openMushafAtRibbon() } label: { Image(systemName: "book.pages") }
                        .accessibilityLabel("Mushaf pages")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNotifications = true } label: { Image(systemName: "bell.badge") }
                        .accessibilityLabel("Qur'an notifications")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                        .accessibilityLabel("Qur'an settings")
                }
            }
            .sheet(isPresented: $showSettings) { QuranSettingsView() }
            .sheet(isPresented: $showGoal) { QuranGoalSheet() }
            .sheet(isPresented: $showNotifications) {
                NavigationStack { QuranNotificationsView(showsDone: true) }
            }
            .fullScreenCover(isPresented: $showMushaf) { MushafPageView() }
            .fullScreenCover(isPresented: $showDaily, onDismiss: { goal.refresh() }) { DailyReaderView() }
            .task { await store.load() }
            .onAppear { goal.refresh() }
            // A Qur'an reminder was tapped: go straight to the ribbon.
            .onChange(of: deepLink.pending, initial: true) { _, destination in
                let target: VerseReference
                switch destination {
                case .quranContinueReading: target = store.ribbon ?? VerseReference(surah: 1, verse: 1)
                case .quranVerse(let surah, let verse): target = VerseReference(surah: surah, verse: verse)
                case .hadith, nil: return
                }
                deepLink.pending = nil
                open(ReaderDestination(surah: target.surah, verse: target.verse))
            }
        } detail: {
            if let destination = ReaderDestination(storageKey: openSurah) {
                NavigationStack {
                    SurahReaderView(surahID: destination.surah, startVerse: destination.verse)
                        .id("\(destination.storageKey)|\(foundCount)")
                }
            } else {
                VStack(spacing: 24) {
                    ContentUnavailableView("Choose a surah", systemImage: "book.pages",
                                           description: Text("It opens here, beside the list. Or recite, and Niyat finds it."))
                        .frame(maxHeight: 260)
                    FindByRecitingButton { showFinder = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .niyatBackground()
            }
        }
        // Shares the width between the list and the reader rather than sliding over it.
        .navigationSplitViewStyle(.balanced)
        // The window reopened with a surah open (e.g. after the app was closed
        // in the background): bring the reader back in front, once.
        .onAppear {
            guard !restored else { return }
            restored = true
            if ReaderDestination(storageKey: openSurah) != nil { compactColumn = .detail }
        }
    }

    /// Opens the mushaf at the ribbon's page (or wherever it was last left).
    private func openMushafAtRibbon() {
        if let ribbonPage = store.ribbonPage { mushafPage = ribbonPage }
        showMushaf = true
    }

    /// Opens a surah or verse in the chosen reading layout.
    private func open(_ destination: ReaderDestination) {
        if readingLayout == "pages", !store.pageStarts.isEmpty {
            mushafPage = store.page(containing: VerseReference(surah: destination.surah, verse: destination.verse ?? 1))
            showMushaf = true
        } else {
            openSurah = destination.storageKey
            compactColumn = .detail
        }
    }

    private var filteredSurahs: [Surah] {
        let found = Set(SurahSearch.matches(store.surahs.map(SurahSearch.Entry.init), query: searchText).map(\.id))
        return store.surahs.filter { found.contains($0.id) }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if searchText.isEmpty {
                    // The daily reader is where ayat count; without a goal yet, set one first.
                    QuranGoalCard {
                        if goal.goal == nil { showGoal = true } else { showDaily = true }
                    }
                        .appearAnimation(0)
                }
                if searchText.isEmpty, let ribbon = store.ribbon, let surah = store.surah(ribbon.surah) {
                    Button { open(ReaderDestination(surah: surah.id, verse: ribbon.verse)) } label: {
                        ContinueReadingCard(surah: surah, verse: ribbon.verse)
                    }
                    .buttonStyle(.pressable)
                    .appearAnimation(0)
                }

                // Recite anywhere in the Qur'an and go straight there.
                if searchText.isEmpty {
                    Button { showFinder = true } label: { FindByRecitingCard() }
                        .buttonStyle(.pressable)
                        .appearAnimation(1)
                }

                if searchText.isEmpty {
                    HStack(spacing: 10) {
                        NavigationLink {
                            QuranicDuasView { reference in
                                open(ReaderDestination(surah: reference.surah, verse: reference.verse))
                            }
                        } label: {
                            QuranToolTile(title: "Duas", subtitle: "From the Qur'an", icon: "hands.and.sparkles.fill")
                        }
                        .buttonStyle(.pressable)
                        Button { openMushafAtRibbon() } label: {
                            QuranToolTile(title: "Mushaf", subtitle: "15-line pages", icon: "book.pages.fill")
                        }
                        .buttonStyle(.pressable)
                    }
                    .appearAnimation(1)
                }

                if searchText.isEmpty, !store.bookmarks.isEmpty {
                    Text("Saved verses").sectionLabelStyle().padding(.top, 8)
                    ScrollView(.horizontal, showsIndicators: false) {
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(store.bookmarks) { bookmark in
                                    if let surah = store.surah(bookmark.surah) {
                                        Button { open(ReaderDestination(surah: surah.id, verse: bookmark.verse)) } label: {
                                            Label("\(surah.transliteration) \(bookmark.surah):\(bookmark.verse)", systemImage: "star.fill")
                                                .font(.subheadline.weight(.semibold))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 10)
                                                .glassEffect(.regular.interactive(), in: .capsule)
                                        }
                                        .buttonStyle(.pressable)
                                        .contextMenu {
                                            Button("Remove from saved verses", systemImage: "star.slash", role: .destructive) {
                                                if let index = store.bookmarks.firstIndex(of: bookmark) {
                                                    store.removeBookmarks(atOffsets: IndexSet(integer: index))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .scrollClipDisabled()
                }

                // Your bookmarks, with their notes: the newest few.
                if searchText.isEmpty, !verseBookmarks.all.isEmpty {
                    HStack {
                        Text("Bookmarks").sectionLabelStyle()
                        Spacer()
                        if verseBookmarks.all.count > 3 {
                            NavigationLink {
                                BookmarksListView { open(ReaderDestination(surah: $0.surah, verse: $0.verse)) }
                            } label: {
                                Text("See all \(verseBookmarks.all.count)").font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .padding(.top, 8)
                    ForEach(verseBookmarks.all.prefix(3)) { bookmark in
                        BookmarkListItem(bookmark: bookmark,
                                         onOpen: { open(ReaderDestination(surah: $0.surah, verse: $0.verse)) },
                                         onEdit: { editingBookmark = bookmark })
                    }
                }

                Text("Surahs").sectionLabelStyle().padding(.top, 8)

                ForEach(Array(filteredSurahs.enumerated()), id: \.element.id) { index, surah in
                    Button { open(ReaderDestination(surah: surah.id, verse: nil)) } label: {
                        SurahRow(surah: surah, verseCount: store.verseCount(for: surah.id))
                    }
                    .buttonStyle(.pressable)
                    .scrollFade()
                    // Only the first screenful animates in, so scrolling stays calm.
                    .appearAnimation(index, enabled: index < 12 && searchText.isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableWidth()
        }
    }
}

struct ReaderDestination: Hashable {
    let surah: Int
    let verse: Int?
}

extension ReaderDestination {
    /// "18:16", or "2" for a surah from its start: how the open surah is kept
    /// in scene storage, so it survives folding an iPhone Duo.
    var storageKey: String { verse.map { "\(surah):\($0)" } ?? "\(surah)" }

    init?(storageKey: String) {
        let parts = storageKey.split(separator: ":").map { Int($0) }
        guard let surah = parts.first ?? nil, (1...114).contains(surah) else { return nil }
        self.init(surah: surah, verse: parts.count > 1 ? parts[1] : nil)
    }
}

private struct ContinueReadingCard: View {
    let surah: Surah
    let verse: Int

    var body: some View {
        HStack(spacing: 16) {
            RibbonMark(color: Color(QuranTextStyle.ribbonRed), starColor: .white)
                .frame(width: 20, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Continue reading")
                    .sectionLabelStyle()
                    .foregroundStyle(Palette.accent)
                Text(surah.transliteration)
                    .font(.title3.weight(.bold))
                Text("Verse \(verse)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(surah.name)
                .font(.quran(size: 28))
                .foregroundStyle(Palette.highlight)
        }
        .padding(18)
        .background(alignment: .trailing) {
            Rosette(color: Palette.highlight.opacity(0.15))
                .frame(width: 150, height: 150)
                .offset(x: 50)
        }
        .clipShape(.rect(cornerRadius: 26))
        .glassPanel(cornerRadius: 26, tint: Palette.glow.opacity(0.4), interactive: true)
    }
}

private struct SurahRow: View {
    let surah: Surah
    let verseCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Text("\(surah.id)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .fitText()
                .foregroundStyle(Palette.accent)
                .frame(width: 42, height: 42)
                .background {
                    EightPointStar()
                        .stroke(Palette.accent.opacity(0.6), lineWidth: 1.5)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(surah.transliteration)
                    .font(.headline)
                Text("\(surah.translation) · \(verseCount) verses · \(surah.revelationPlace)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }

            Spacer(minLength: 8)

            Text(surah.name)
                .font(.quran(size: 22))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .surface(cornerRadius: 20)
        .contentShape(.rect)
    }
}

/// Today's goal at the top of the Qur'an tab: opens the daily reader.
private struct QuranGoalCard: View {
    @State private var goal = QuranGoalModel.shared
    @State private var store = QuranStore.shared
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                if let target = goal.goal {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today").sectionLabelStyle()
                        Spacer()
                        Label("\(goal.streak)-day streak", systemImage: "flame.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(goal.streak > 0 ? Palette.highlight : .secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(goal.today.count)")
                            .font(.display(30, weight: .heavy))
                            .contentTransition(.numericText(value: Double(goal.today.count)))
                        Text("/ \(target) ayat")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        if goal.today.isComplete {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.highlight)
                        }
                        Spacer()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.1))
                            Capsule()
                                .fill(LinearGradient(colors: [Palette.accent, Palette.highlight], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * goal.progress)
                                .animation(.smooth(duration: 0.6), value: goal.progress)
                        }
                    }
                    .frame(height: 8)
                    HStack(spacing: 10) {
                        Text(continueText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        Label(goal.today.isComplete ? "Read more" : "Read", systemImage: "book.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Palette.control.gradient, in: .capsule)
                    }
                } else {
                    HStack(spacing: 14) {
                        Image(systemName: "target")
                            .font(.title2)
                            .foregroundStyle(Palette.highlight)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set a daily Qur'an goal").font(.headline)
                            Text("A few ayat a day, one at a time. Track it and build a streak.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .glassPanel(cornerRadius: 26, tint: Palette.glow.opacity(0.3), interactive: true)
        }
        .buttonStyle(.pressable)
        .accessibilityHint(goal.goal == nil ? "Choose how many ayat to read each day" : "Opens the daily reader")
        .onAppear { goal.refresh() }
    }

    /// "Continue at Al-Baqarah 2:23", or where a first reading starts.
    private var continueText: String {
        let ribbon = store.ribbon.map { DailyPlace(surah: $0.surah, verse: $0.verse) }
        let mark = store.dailyPlace
        let counts = (1...114).map { store.verseCount(for: $0) }
        let place = DailyReading.start(mark: mark, ribbon: ribbon, verseCounts: counts)
        let name = store.surah(place.surah)?.transliteration ?? "Surah \(place.surah)"
        return "\(mark == nil && ribbon == nil ? "Start at" : "Continue at") \(name) \(place.surah):\(place.verse)"
    }
}

/// A small tile on the Qur'an screen (Duas, Mushaf).
private struct QuranToolTile: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.highlight)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).fitText(0.7)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).fitText(0.7)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity)
        .surface(cornerRadius: 18)
    }
}

/// "Recite to find a surah": the way into finding by reciting, at the top of the list.
private struct FindByRecitingCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "mic.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Palette.control.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recite to find a surah").font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                Text("Niyat opens it where you are").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity)
        .surface(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Find by reciting")
        .accessibilityHint("Recite a few words and Niyat opens that surah and ayah.")
    }
}
