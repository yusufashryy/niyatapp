import SwiftUI

/// The Qur'an page by page, following the 604 pages of the Madinah mushaf.
///
/// Which verses sit on which page (and where each juz and hizb starts) comes
/// from Tanzil's verified metadata in `chapters.json`. The printed page image
/// itself is copyrighted, so Niyat typesets each page from the verified text:
/// same verses per page, but line breaks can differ from a printed copy.
struct MushafPageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = QuranStore.shared
    @State private var goal = QuranGoalModel.shared
    @AppStorage("quran.mushafPage") private var page = 1
    @State private var showChrome = true
    @State private var showJump = false

    var body: some View {
        NavigationStack {
            ZStack {
                if store.pageStarts.isEmpty {
                    ProgressView()
                } else {
                    // Pages turn right-to-left, like a printed mushaf.
                    TabView(selection: $page) {
                        ForEach(1...store.pageStarts.count, id: \.self) { number in
                            MushafPage(number: number, isCurrent: number == page)
                                .environment(\.layoutDirection, .leftToRight)
                                .tag(number)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .environment(\.layoutDirection, .rightToLeft)
                    .haptic(.selection, trigger: page)
                    .onTapGesture { withAnimation(.smooth) { showChrome.toggle() } }
                }
            }
            .niyatBackground()
            .overlay {
                if let streak = goal.celebration {
                    GoalCelebration(streak: streak) { goal.celebration = nil }
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(.bouncy, value: goal.celebration)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(showChrome ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    QuranGoalPill { }
                        .allowsHitTesting(false)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Go to page", systemImage: "list.number") { showJump = true }
                }
            }
            .sheet(isPresented: $showJump) {
                MushafJumpSheet(page: $page, pageCount: store.pageStarts.count)
            }
            .task { await store.load() }
            .onAppear { page = min(max(page, 1), 604) }
        }
    }

    private var title: String {
        guard !store.pageStarts.isEmpty else { return "Mushaf" }
        let first = store.pageStarts[min(page, store.pageStarts.count) - 1]
        return "Page \(page) · Juz \(store.juz(containing: first))"
    }
}

/// One typeset page: surah banners, Bismillah, and flowing verses with ayah markers.
private struct MushafPage: View {
    let number: Int
    let isCurrent: Bool

    @State private var store = QuranStore.shared
    @State private var goal = QuranGoalModel.shared
    @AppStorage("quran.arabicSize") private var arabicSize = 30.0
    @State private var readTask: Task<Void, Never>?

    var body: some View {
        let verses = store.verses(onPage: number)
        let surahIDs = Array(Set(verses.map(\.surah))).sorted()
        ScrollView {
            VStack(spacing: 14) {
                header(verses)
                ForEach(surahIDs, id: \.self) { surahID in
                    let surahVerses = verses.filter { $0.surah == surahID }
                    if surahVerses.first?.number == 1, let surah = store.surah(surahID) {
                        SurahBanner(surah: surah)
                        if store.showsBismillahHeader(for: surah) {
                            Text(store.bismillah)
                                .font(.quran(size: arabicSize * 0.9))
                                .foregroundStyle(Palette.highlight)
                        }
                    }
                    Text(flowingText(surahVerses))
                        .font(.quran(size: arabicSize * 0.85))
                        .lineSpacing(arabicSize * 0.45)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                Spacer(minLength: 12)
                Text(Self.arabicDigits(number))
                    .font(.quran(size: 20))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 14).padding(.vertical, 2)
                    .background(Palette.accent.opacity(0.12), in: .capsule)
                    .accessibilityLabel("Page \(number)")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .overlay {
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(Palette.highlight.opacity(0.25), lineWidth: 1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .onChange(of: isCurrent, initial: true) { _, current in
            readTask?.cancel()
            guard current, !verses.isEmpty else { return }
            store.markRead(verses[0])
            // Count the page towards today's goal once it has stayed open long
            // enough to actually be read (about 1.5 s per verse, 4–20 s).
            let dwell = min(max(Double(verses.count) * 1.5, 4), 20)
            readTask = Task {
                try? await Task.sleep(for: .seconds(dwell))
                guard !Task.isCancelled else { return }
                for verse in verses { goal.recordRead(verse) }
            }
        }
        .onDisappear { readTask?.cancel() }
    }

    private func header(_ verses: [Verse]) -> some View {
        let first = verses.first?.hafsReference ?? VerseReference(surah: 1, verse: 1)
        let surahNames = Array(Set(verses.map(\.surah))).sorted().compactMap { store.surah($0)?.name }
        return HStack {
            Text(surahNames.joined(separator: " · "))
                .font(.quran(size: 18))
            Spacer()
            if let hizb = hizbMarker(verses) {
                Text(hizb)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
            Text("الجزء \(Self.arabicDigits(store.juz(containing: first)))")
                .font(.quran(size: 18))
        }
        .foregroundStyle(.secondary)
        .environment(\.layoutDirection, .rightToLeft)
    }

    /// "Hizb 3 ¼" when a hizb quarter starts on this page.
    private func hizbMarker(_ verses: [Verse]) -> String? {
        let ids = Set(verses.map(\.hafsReference))
        guard let index = store.hizbStarts.firstIndex(where: { ids.contains($0) }) else { return nil }
        let hizb = index / 4 + 1
        let quarter = ["", " ¼", " ½", " ¾"][index % 4]
        return "Hizb \(hizb)\(quarter)"
    }

    /// Verses run together, each closed by an ayah marker ۝ with its number.
    private func flowingText(_ verses: [Verse]) -> AttributedString {
        var text = AttributedString()
        for verse in verses {
            // (The Bismillah is already split off verse 1 when the text loads.)
            var arabic = AttributedString(verse.arabic)
            arabic.foregroundColor = Color.white
            var marker = AttributedString(" \u{06DD}\(Self.arabicDigits(verse.number)) ")
            marker.foregroundColor = store.sajdahVerses.contains(verse.hafsReference) ? Palette.highlight : Palette.accent
            text += arabic + marker
        }
        return text
    }

    static func arabicDigits(_ value: Int) -> String {
        let digits = Array("٠١٢٣٤٥٦٧٨٩")
        return String(String(value).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }
}

/// The ornamental frame at the start of a surah.
private struct SurahBanner: View {
    let surah: Surah

    var body: some View {
        HStack(spacing: 12) {
            EightPointStar().fill(Palette.accent).frame(width: 14, height: 14)
            Text("سُورَةُ \(surah.name)")
                .font(.quran(size: 24))
                .foregroundStyle(Palette.highlight)
            EightPointStar().fill(Palette.accent).frame(width: 14, height: 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background { IslamicPattern(tile: 30, lineWidth: 0.5, color: Palette.accent.opacity(0.12)) }
        .clipShape(.rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.highlight.opacity(0.4), lineWidth: 1) }
        .accessibilityLabel("Surah \(surah.transliteration)")
    }
}

/// Jump to a page, juz or surah.
private struct MushafJumpSheet: View {
    @Binding var page: Int
    let pageCount: Int
    @Environment(\.dismiss) private var dismiss
    @State private var store = QuranStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Page") {
                    Stepper(value: $page, in: 1...pageCount) {
                        Text("Page \(page)").monospacedDigit()
                    }
                }
                Section("Juz") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(store.juzStarts.enumerated()), id: \.offset) { index, start in
                                Button("\(index + 1)") { go(to: start) }
                                    .buttonStyle(.glass)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                Section("Surah") {
                    ForEach(store.surahs) { surah in
                        Button {
                            go(to: VerseReference(surah: surah.id, verse: 1))
                        } label: {
                            HStack {
                                Text("\(surah.id). \(surah.transliteration)").foregroundStyle(.white)
                                Spacer()
                                Text(surah.name).font(.quran(size: 18)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .niyatBackground()
            .navigationTitle("Go to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func go(to reference: VerseReference) {
        page = store.page(containing: reference)
        dismiss()
    }
}
