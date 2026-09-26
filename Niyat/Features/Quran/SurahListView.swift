import SwiftUI

struct SurahListView: View {
    @State private var store = QuranStore.shared
    @State private var searchText = ""
    @State private var path: [ReaderDestination] = []
    @State private var goal = QuranGoalModel.shared
    @State private var deepLink = DeepLink.shared
    @State private var showSettings = false
    @State private var showGoal = false
    @State private var showMushaf = false
    @State private var showNotifications = false
    @State private var showRecite = false

    var body: some View {
        NavigationStack(path: $path) {
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
            .navigationTitle("Quran")
            .navigationDestination(for: ReaderDestination.self) { destination in
                SurahReaderView(surahID: destination.surah, startVerse: destination.verse)
            }
            .searchable(text: $searchText, prompt: "Surah name or number")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showMushaf = true } label: { Image(systemName: "book.pages") }
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
            .fullScreenCover(isPresented: $showRecite) {
                RecitationCheckView(surah: store.lastRead?.surah ?? 1, verse: store.lastRead?.verse ?? 1)
            }
            .task { await store.load() }
            .onAppear { goal.refresh() }
            // A Qur'an reminder was tapped: go straight to where you left off.
            .onChange(of: deepLink.pending, initial: true) { _, destination in
                let target: VerseReference
                switch destination {
                case .quranContinueReading: target = store.lastRead ?? VerseReference(surah: 1, verse: 1)
                case .quranVerse(let surah, let verse): target = VerseReference(surah: surah, verse: verse)
                case nil: return
                }
                deepLink.pending = nil
                path = [ReaderDestination(surah: target.surah, verse: target.verse)]
            }
        }
    }

    private var filteredSurahs: [Surah] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.surahs }
        if let number = Int(query) { return store.surahs.filter { $0.id == number } }
        return store.surahs.filter {
            $0.transliteration.localizedCaseInsensitiveContains(query)
                || $0.translation.localizedCaseInsensitiveContains(query)
                || $0.name.contains(query)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if searchText.isEmpty {
                    QuranGoalCard { showGoal = true }
                        .appearAnimation(0)
                }
                if searchText.isEmpty, let lastRead = store.lastRead, let surah = store.surah(lastRead.surah) {
                    NavigationLink(value: ReaderDestination(surah: surah.id, verse: lastRead.verse)) {
                        ContinueReadingCard(surah: surah, verse: lastRead.verse)
                    }
                    .buttonStyle(.pressable)
                    .appearAnimation(0)
                }

                if searchText.isEmpty {
                    HStack(spacing: 10) {
                        NavigationLink {
                            QuranicDuasView { reference in
                                path.append(ReaderDestination(surah: reference.surah, verse: reference.verse))
                            }
                        } label: {
                            QuranToolTile(title: "Duas", subtitle: "From the Qur'an", icon: "hands.and.sparkles.fill")
                        }
                        .buttonStyle(.pressable)
                        Button { showRecite = true } label: {
                            QuranToolTile(title: "Recite", subtitle: "Beta · follows along", icon: "mic.fill")
                        }
                        .buttonStyle(.pressable)
                    }
                    .appearAnimation(1)
                }

                if searchText.isEmpty, !store.bookmarks.isEmpty {
                    Text("Bookmarks").sectionLabelStyle().padding(.top, 8)
                    ScrollView(.horizontal, showsIndicators: false) {
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(store.bookmarks) { bookmark in
                                    if let surah = store.surah(bookmark.surah) {
                                        NavigationLink(value: ReaderDestination(surah: surah.id, verse: bookmark.verse)) {
                                            Label("\(surah.transliteration) \(bookmark.surah):\(bookmark.verse)", systemImage: "bookmark.fill")
                                                .font(.subheadline.weight(.semibold))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 10)
                                                .glassEffect(.regular.interactive(), in: .capsule)
                                        }
                                        .buttonStyle(.pressable)
                                        .contextMenu {
                                            Button("Remove bookmark", systemImage: "bookmark.slash", role: .destructive) {
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

                Text("Surahs").sectionLabelStyle().padding(.top, 8)

                ForEach(Array(filteredSurahs.enumerated()), id: \.element.id) { index, surah in
                    NavigationLink(value: ReaderDestination(surah: surah.id, verse: nil)) {
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
        }
    }
}

struct ReaderDestination: Hashable {
    let surah: Int
    let verse: Int?
}

private struct ContinueReadingCard: View {
    let surah: Surah
    let verse: Int

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "book.pages.fill")
                .font(.title2)
                .foregroundStyle(Palette.highlight)
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
                    .lineLimit(1)
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

/// Today's goal at the top of the Qur'an tab.
private struct QuranGoalCard: View {
    @State private var goal = QuranGoalModel.shared
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
                } else {
                    HStack(spacing: 14) {
                        Image(systemName: "target")
                            .font(.title2)
                            .foregroundStyle(Palette.highlight)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set a daily Qur'an goal").font(.headline)
                            Text("A few ayat a day, every day. Track it and build a streak.")
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
        .onAppear { goal.refresh() }
    }
}

/// A small tile on the Qur'an screen (Duas, Recite).
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
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity)
        .surface(cornerRadius: 18)
    }
}
