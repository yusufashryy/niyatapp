import SwiftUI
import UIKit

/// The Qur'an page by page, styled like a printed Madinah mushaf.
///
/// Which verses sit on which page (and where each juz and hizb starts) comes
/// from Tanzil's verified metadata in `chapters.json`. The printed page image
/// itself is copyrighted, so Niyat typesets each page from the verified text:
/// same verses per page, but line breaks can differ from a printed copy.
///
/// Like the surah reader: tap a verse to play it, bookmark, copy or see its
/// meaning; recitation highlights the verse and turns the pages for you.
struct MushafPageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = QuranStore.shared
    @State private var goal = QuranGoalModel.shared
    @State private var player = RecitationPlayer.shared
    @AppStorage("quran.mushafPage") private var page = 1
    @State private var options = MushafOptions.load()
    @State private var showChrome = true
    @State private var showJump = false
    @State private var showOptions = false
    @State private var selected: Verse?

    var body: some View {
        NavigationStack {
            ZStack {
                if store.pageStarts.isEmpty {
                    ProgressView()
                } else {
                    // Pages turn right-to-left, like a printed mushaf.
                    TabView(selection: $page) {
                        ForEach(1...store.pageStarts.count, id: \.self) { number in
                            MushafPage(number: number, isCurrent: number == page, options: options,
                                       selected: selected?.id, reciting: recitingVerseID) { verse in
                                tapped(verse)
                            }
                            .environment(\.layoutDirection, .leftToRight)
                            .tag(number)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .environment(\.layoutDirection, .rightToLeft)
                    .haptic(.selection, trigger: page)
                }
            }
            .niyatBackground()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let selected {
                        MushafVerseActions(verse: selected, options: options,
                                           canPlay: store.edition.riwayah.hasVerseAudio,
                                           isBookmarked: store.isBookmarked(selected),
                                           onPlayFromHere: { play(from: selected) },
                                           onPlayVerse: { play(from: selected, only: true) },
                                           onBookmark: { store.toggleBookmark(selected) },
                                           onClose: { withAnimation(.smooth) { self.selected = nil } })
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    RecitationMiniPlayer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .animation(.smooth, value: selected)
                .animation(.smooth, value: player.current)
            }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Page settings", systemImage: "textformat.size") { showOptions = true }
                }
            }
            .sheet(isPresented: $showJump) {
                MushafJumpSheet(page: $page, pageCount: store.pageStarts.count)
            }
            .sheet(isPresented: $showOptions) {
                MushafOptionsSheet(options: $options)
            }
            .onChange(of: options) { _, new in new.save() }
            .onChange(of: page) { _, _ in
                if selected != nil { withAnimation(.smooth) { selected = nil } }
            }
            // Follow the recitation onto the next page.
            .onChange(of: player.current) { _, current in
                guard options.followRecitation, case .verse(let surah, let verse)? = current else { return }
                let target = store.page(containing: VerseReference(surah: surah, verse: verse))
                if target != page { withAnimation(.smooth) { page = target } }
            }
            .onAppear {
                page = min(max(page, 1), 604)
                UIApplication.shared.isIdleTimerDisabled = options.keepScreenOn
            }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .task { await store.load() }
        }
    }

    private var title: String {
        guard !store.pageStarts.isEmpty else { return "Mushaf" }
        let first = store.pageStarts[min(page, store.pageStarts.count) - 1]
        return "Page \(page) · Juz \(store.juz(containing: first))"
    }

    /// The verse being recited, as a page verse ID (surah × 1000 + verse).
    private var recitingVerseID: Int? {
        guard case .verse(let surah, let verse)? = player.current else { return nil }
        return store.verse(VerseReference(surah: surah, verse: verse))?.id
    }

    private func tapped(_ verse: Verse?) {
        guard let verse else {
            // Tapped outside the text: show or hide the bars.
            withAnimation(.smooth) {
                if selected != nil { selected = nil } else { showChrome.toggle() }
            }
            return
        }
        if options.tapAction == .play, store.edition.riwayah.hasVerseAudio {
            play(from: verse)
        } else {
            withAnimation(.smooth) { selected = selected?.id == verse.id ? nil : verse }
        }
    }

    private func play(from verse: Verse, only: Bool = false) {
        let reference = verse.hafsReference
        player.play(surah: reference.surah, from: reference.verse, verseCounts: store.hafsVerseCounts,
                    acrossSurahs: true, only: only)
    }
}

// MARK: - Options

/// Everything the reader can adjust about the mushaf pages.
struct MushafOptions: Codable, Equatable {
    enum TapAction: String, Codable, CaseIterable, Identifiable {
        case actions, play
        var id: String { rawValue }
        var title: String { self == .actions ? "Show verse options" : "Play recitation" }
    }

    enum Border: String, Codable, CaseIterable, Identifiable {
        case illuminated, simple, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .illuminated: "Illuminated"
            case .simple: "Simple"
            case .none: "None"
            }
        }
    }

    var style = MushafStyle.paper
    var border = Border.illuminated
    /// 1 = fit the page like print; larger scrolls within the page.
    var textScale = 1.0
    var tapAction = TapAction.actions
    var showTranslation = true
    var followRecitation = true
    var highlightRecitation = true
    var keepScreenOn = false
    var showHeader = true

    private static let key = "quran.mushafOptions"

    static func load() -> MushafOptions {
        UserDefaults.standard.decoded(MushafOptions.self, forKey: key) ?? MushafOptions()
    }

    func save() {
        UserDefaults.standard.setEncoded(self, forKey: Self.key)
    }

    init() {}

    // Tolerant decoding, so adding options later never resets the others.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let d = MushafOptions()
        style = value(.style, d.style)
        border = value(.border, d.border)
        textScale = value(.textScale, d.textScale)
        tapAction = value(.tapAction, d.tapAction)
        showTranslation = value(.showTranslation, d.showTranslation)
        followRecitation = value(.followRecitation, d.followRecitation)
        highlightRecitation = value(.highlightRecitation, d.highlightRecitation)
        keepScreenOn = value(.keepScreenOn, d.keepScreenOn)
        showHeader = value(.showHeader, d.showHeader)
    }
}

enum MushafStyle: String, Codable, CaseIterable, Identifiable {
    /// Cream paper, like a printed copy.
    case paper
    /// Warmer, older paper.
    case sepia
    /// Bright white.
    case white
    /// Dark page in the app's theme colours, for reading at night.
    case night

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colors: MushafColors {
        // Paper, sepia and white are deliberately fixed colours: they recreate
        // a printed mushaf rather than following the app theme.
        switch self {
        case .paper:
            MushafColors(paper: Color(red: 0.985, green: 0.962, blue: 0.885),
                         paperShade: Color(red: 0.94, green: 0.90, blue: 0.79),
                         band: Color(red: 0.91, green: 0.94, blue: 0.86),
                         gold: Color(red: 0.72, green: 0.55, blue: 0.24),
                         green: Color(red: 0.27, green: 0.47, blue: 0.36),
                         rose: Color(red: 0.72, green: 0.33, blue: 0.36),
                         ink: UIColor(red: 0.11, green: 0.09, blue: 0.07, alpha: 1),
                         marker: UIColor(red: 0.55, green: 0.39, blue: 0.10, alpha: 1),
                         label: Color(red: 0.30, green: 0.24, blue: 0.14))
        case .sepia:
            MushafColors(paper: Color(red: 0.96, green: 0.91, blue: 0.80),
                         paperShade: Color(red: 0.88, green: 0.80, blue: 0.66),
                         band: Color(red: 0.93, green: 0.87, blue: 0.74),
                         gold: Color(red: 0.62, green: 0.45, blue: 0.20),
                         green: Color(red: 0.35, green: 0.45, blue: 0.30),
                         rose: Color(red: 0.62, green: 0.30, blue: 0.28),
                         ink: UIColor(red: 0.20, green: 0.13, blue: 0.07, alpha: 1),
                         marker: UIColor(red: 0.50, green: 0.32, blue: 0.10, alpha: 1),
                         label: Color(red: 0.36, green: 0.24, blue: 0.12))
        case .white:
            MushafColors(paper: .white,
                         paperShade: Color(white: 0.95),
                         band: Color(red: 0.95, green: 0.96, blue: 0.97),
                         gold: Color(red: 0.70, green: 0.56, blue: 0.28),
                         green: Color(red: 0.20, green: 0.45, blue: 0.38),
                         rose: Color(red: 0.66, green: 0.28, blue: 0.35),
                         ink: UIColor(white: 0.05, alpha: 1),
                         marker: UIColor(red: 0.45, green: 0.35, blue: 0.12, alpha: 1),
                         label: Color(white: 0.25))
        case .night:
            MushafColors(paper: Palette.base.mix(with: .white, by: 0.06),
                         paperShade: Palette.base,
                         band: Palette.glow.opacity(0.45),
                         gold: Palette.highlight,
                         green: Palette.accent.opacity(0.7),
                         rose: Palette.highlight.opacity(0.55),
                         ink: .white,
                         marker: UIColor(Palette.highlight),
                         label: Palette.highlight)
        }
    }
}

struct MushafColors {
    let paper: Color
    let paperShade: Color
    let band: Color
    let gold: Color
    let green: Color
    let rose: Color
    let ink: UIColor
    let marker: UIColor
    let label: Color
}

/// Page settings sheet.
private struct MushafOptionsSheet: View {
    @Binding var options: MushafOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Page") {
                    HStack(spacing: 10) {
                        ForEach(MushafStyle.allCases) { style in
                            let colors = style.colors
                            Button {
                                options.style = style
                            } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(colors.paper)
                                        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(colors.gold, lineWidth: 2).padding(3) }
                                        .overlay {
                                            Text("بِسْمِ")
                                                .font(.quran(size: 14))
                                                .foregroundStyle(Color(colors.ink))
                                        }
                                        .frame(height: 64)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(options.style == style ? Palette.control : .clear, lineWidth: 2)
                                                .padding(-3)
                                        }
                                    Text(style.title).font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.pressable)
                            .haptic(.selection, trigger: options.style)
                        }
                    }
                    .padding(.vertical, 4)
                    Picker("Border", selection: $options.border) {
                        ForEach(MushafOptions.Border.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Surah and juz at the top", isOn: $options.showHeader)
                }

                Section {
                    VStack(alignment: .leading) {
                        LabeledContent("Text size", value: options.textScale <= 1.001 ? "Fit page" : "\(Int(options.textScale * 100))%")
                        Slider(value: $options.textScale, in: 1...1.6, step: 0.1)
                    }
                } footer: {
                    Text("At \"Fit page\" each page fills its frame like a printed mushaf. Bigger text scrolls within the page.")
                }

                Section("Tap and recitation") {
                    Picker("Tapping a verse", selection: $options.tapAction) {
                        ForEach(MushafOptions.TapAction.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Show meaning of tapped verse", isOn: $options.showTranslation)
                    Toggle("Highlight the verse being recited", isOn: $options.highlightRecitation)
                    Toggle("Turn pages with the recitation", isOn: $options.followRecitation)
                    Toggle("Keep screen on", isOn: $options.keepScreenOn)
                        .onChange(of: options.keepScreenOn) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
                }
            }
            .scrollContentBackground(.hidden)
            .niyatBackground()
            .navigationTitle("Page settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Bar shown after tapping a verse: its meaning and what you can do with it.
private struct MushafVerseActions: View {
    let verse: Verse
    let options: MushafOptions
    let canPlay: Bool
    let isBookmarked: Bool
    let onPlayFromHere: () -> Void
    let onPlayVerse: () -> Void
    let onBookmark: () -> Void
    let onClose: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(QuranStore.shared.surah(verse.surah)?.transliteration ?? "") \(verse.surah):\(verse.number)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 28, height: 28)
                }
                .accessibilityLabel("Close")
            }
            if options.showTranslation, !verse.translation.isEmpty {
                ScrollView {
                    Text(verse.translation)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if canPlay {
                    action("Play from here", "play.fill", onPlayFromHere)
                    action("This verse", "repeat.1", onPlayVerse)
                }
                action(isBookmarked ? "Saved" : "Bookmark", isBookmarked ? "bookmark.fill" : "bookmark", onBookmark)
                action(copied ? "Copied" : "Copy", copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = "\(verse.arabic)\n\n\(verse.translation)\n— Qur'an \(verse.surah):\(verse.number)"
                    copied = true
                }
            }
            .haptic(.impact(weight: .light), trigger: isBookmarked)
            .haptic(.success, trigger: copied)
        }
        .foregroundStyle(.white)
        .padding(14)
        .glassPanel(cornerRadius: 24, tint: Palette.glow.opacity(0.35))
        .onChange(of: verse) { _, _ in copied = false }
    }

    private func action(_ title: String, _ icon: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.headline)
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Page

/// One page: ornamental frame, header labels, surah banners, Bismillah,
/// justified verses with ayah markers, and the page number.
private struct MushafPage: View {
    let number: Int
    let isCurrent: Bool
    let options: MushafOptions
    /// Page verse IDs to highlight.
    let selected: Int?
    let reciting: Int?
    /// A verse was tapped (nil: tapped outside any verse).
    let onTap: (Verse?) -> Void

    @State private var store = QuranStore.shared
    @State private var goal = QuranGoalModel.shared
    @State private var readTask: Task<Void, Never>?

    // Page geometry, in points.
    private static let aspect: CGFloat = 0.64
    private static let headerHeight: CGFloat = 26
    private static let footerHeight: CGFloat = 30
    private static let spacing: CGFloat = 6

    private var contentInset: CGFloat {
        switch options.border {
        case .illuminated: 30
        case .simple: 22
        case .none: 16
        }
    }

    private var colors: MushafColors { options.style.colors }

    var body: some View {
        let verses = store.verses(onPage: number)
        GeometryReader { geo in
            let size = Self.pageSize(in: geo.size)
            let pageLayout = makeLayout(verses, size: size)
            ScrollView(.vertical) {
                page(verses, layout: pageLayout)
                    .frame(width: size.width, height: pageLayout.pageHeight)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollDisabled(pageLayout.pageHeight <= size.height + 1)
            .scrollIndicators(.hidden)
        }
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

    private struct Layout {
        let segments: [MushafSegment]
        let fontSize: CGFloat
        let pageHeight: CGFloat
    }

    private static func pageSize(in available: CGSize) -> CGSize {
        let width = max(available.width - 20, 100)
        let height = max(available.height - 16, 100)
        return width / height > aspect
            ? CGSize(width: height * aspect, height: height)
            : CGSize(width: width, height: width / aspect)
    }

    private func makeLayout(_ verses: [Verse], size: CGSize) -> Layout {
        let segments = MushafTypesetter.segments(for: verses, store: store)
        let headerHeight = options.showHeader ? Self.headerHeight + Self.spacing : 0
        let textWidth = size.width - contentInset * 2
        let textHeight = size.height - contentInset * 2 - headerHeight - Self.footerHeight - Self.spacing
        let fit = MushafTypesetter.fittingSize(page: number, segments: segments, store: store,
                                               width: textWidth, height: textHeight)
        guard options.textScale > 1.001 else { return Layout(segments: segments, fontSize: fit, pageHeight: size.height) }
        // Bigger than print: the page grows and scrolls.
        let fontSize = fit * options.textScale
        let needed = MushafTypesetter.totalHeight(segments, size: fontSize, width: textWidth, store: store)
        return Layout(segments: segments, fontSize: fontSize, pageHeight: size.height + max(0, needed - textHeight))
    }

    private func page(_ verses: [Verse], layout: Layout) -> some View {
        let first = verses.first?.hafsReference ?? VerseReference(surah: 1, verse: 1)
        let fontSize = layout.fontSize

        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(RadialGradient(colors: [colors.paper, colors.paperShade], center: .center,
                                     startRadius: 120, endRadius: 520))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            MushafFrame(colors: colors, border: options.border)
                .padding(6)

            VStack(spacing: Self.spacing) {
                if options.showHeader {
                    // Surah on the right, juz on the left, as in print.
                    HStack {
                        Cartouche(text: MushafTypesetter.juzName(store.juz(containing: first)), colors: colors)
                        Spacer()
                        Cartouche(text: "سورة " + (store.surah(first.surah)?.name ?? ""), colors: colors)
                    }
                    .frame(height: Self.headerHeight)
                }

                VStack(spacing: Self.spacing) {
                    ForEach(layout.segments) { segment in
                        switch segment.kind {
                        case .banner(let surah):
                            SurahBanner(surah: surah, colors: colors, height: MushafTypesetter.bannerHeight(fontSize))
                                .onTapGesture { onTap(nil) }
                        case .bismillah:
                            MushafTextView(text: MushafTypesetter.centered(store.bismillah, size: fontSize, color: colors.ink)) { _ in
                                onTap(nil)
                            }
                        case .verses(let verses):
                            MushafTextView(text: MushafTypesetter.verses(verses, size: fontSize, colors: colors,
                                                                         sajdahs: store.sajdahVerses,
                                                                         selected: selected,
                                                                         reciting: options.highlightRecitation ? reciting : nil)) { id in
                                onTap(id.flatMap { id in verses.first { $0.id == id } })
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                PageMedallion(number: number, colors: colors)
                    .frame(height: Self.footerHeight)
            }
            .padding(contentInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page \(number)")
    }
}

// MARK: - Typesetting

private struct MushafSegment: Identifiable {
    enum Kind {
        case banner(Surah)
        case bismillah
        case verses([Verse])
    }

    let id: Int
    let kind: Kind
}

private extension NSAttributedString.Key {
    /// Which verse (surah × 1000 + number) a run of mushaf text belongs to.
    static let niyatVerse = NSAttributedString.Key("NiyatVerse")
}

@MainActor
private enum MushafTypesetter {
    private static var sizeCache: [String: CGFloat] = [:]

    static func font(_ size: CGFloat) -> UIFont {
        UIFont(name: "AmiriQuran-Regular", size: size) ?? .systemFont(ofSize: size)
    }

    static func segments(for verses: [Verse], store: QuranStore) -> [MushafSegment] {
        var result: [MushafSegment] = []
        for surahID in Array(Set(verses.map(\.surah))).sorted() {
            let surahVerses = verses.filter { $0.surah == surahID }
            if surahVerses.first?.number == 1, let surah = store.surah(surahID) {
                result.append(MushafSegment(id: result.count, kind: .banner(surah)))
                if store.showsBismillahHeader(for: surah) {
                    result.append(MushafSegment(id: result.count, kind: .bismillah))
                }
            }
            result.append(MushafSegment(id: result.count, kind: .verses(surahVerses)))
        }
        return result
    }

    static func bannerHeight(_ fontSize: CGFloat) -> CGFloat { fontSize * 1.9 }

    /// The largest text size at which the whole page fits, like a printed page
    /// filling its frame. Capped so short pages (Al-Fatiha) don't get huge.
    static func fittingSize(page: Int, segments: [MushafSegment], store: QuranStore,
                            width: CGFloat, height: CGFloat) -> CGFloat {
        let key = "\(page)-\(Int(width))-\(Int(height))-\(store.edition.rawValue)"
        if let cached = sizeCache[key] { return cached }
        var low: CGFloat = 9
        var high: CGFloat = min(30, width / 10)
        for _ in 0..<14 {
            let mid = (low + high) / 2
            if totalHeight(segments, size: mid, width: width, store: store) <= height * 0.97 {
                low = mid
            } else {
                high = mid
            }
        }
        sizeCache[key] = low
        return low
    }

    static func totalHeight(_ segments: [MushafSegment], size: CGFloat, width: CGFloat, store: QuranStore) -> CGFloat {
        let colors = MushafStyle.paper.colors
        var total = CGFloat(max(segments.count - 1, 0)) * 6
        for segment in segments {
            switch segment.kind {
            case .banner: total += bannerHeight(size)
            case .bismillah: total += height(centered(store.bismillah, size: size, color: colors.ink), width: width)
            case .verses(let verses):
                total += height(self.verses(verses, size: size, colors: colors, sajdahs: store.sajdahVerses,
                                            selected: nil, reciting: nil), width: width)
            }
        }
        return total
    }

    static func height(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height) + 2
    }

    private static func paragraph(_ alignment: NSTextAlignment, size: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.baseWritingDirection = .rightToLeft
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = size * 0.12
        return style
    }

    static func centered(_ text: String, size: CGFloat, color: UIColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font(size), .foregroundColor: color,
                                                      .paragraphStyle: paragraph(.center, size: size)])
    }

    /// Verses run together, justified, each closed by an ayah marker ۝ with its
    /// number in Arabic-Indic digits (the font draws the ornament around it).
    static func verses(_ verses: [Verse], size: CGFloat, colors: MushafColors, sajdahs: Set<VerseReference>,
                       selected: Int?, reciting: Int?) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.font: font(size), .foregroundColor: colors.ink,
                                                   .paragraphStyle: paragraph(.justified, size: size)]
        for verse in verses {
            var attributes = base
            attributes[.niyatVerse] = verse.id
            if verse.id == selected {
                attributes[.backgroundColor] = UIColor(colors.gold).withAlphaComponent(0.25)
            } else if verse.id == reciting {
                attributes[.backgroundColor] = UIColor(colors.green).withAlphaComponent(0.22)
            }
            // (The Bismillah is already split off verse 1 when the text loads.)
            text.append(NSAttributedString(string: verse.arabic, attributes: attributes))
            var markerAttributes = attributes
            markerAttributes[.foregroundColor] = sajdahs.contains(verse.hafsReference) ? UIColor(colors.rose) : colors.marker
            // No-break space keeps the marker on the same line as the verse's last word.
            text.append(NSAttributedString(string: "\u{00A0}\u{06DD}\(arabicDigits(verse.number))", attributes: markerAttributes))
            text.append(NSAttributedString(string: " ", attributes: base))
        }
        return text
    }

    static func arabicDigits(_ value: Int) -> String {
        let digits = Array("٠١٢٣٤٥٦٧٨٩")
        return String(String(value).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }

    /// "الجزء الخامس عشر", as printed at the top of the page.
    static func juzName(_ juz: Int) -> String {
        let ordinals = ["الأول", "الثاني", "الثالث", "الرابع", "الخامس", "السادس", "السابع", "الثامن", "التاسع", "العاشر",
                        "الحادي عشر", "الثاني عشر", "الثالث عشر", "الرابع عشر", "الخامس عشر", "السادس عشر",
                        "السابع عشر", "الثامن عشر", "التاسع عشر", "العشرون", "الحادي والعشرون", "الثاني والعشرون",
                        "الثالث والعشرون", "الرابع والعشرون", "الخامس والعشرون", "السادس والعشرون",
                        "السابع والعشرون", "الثامن والعشرون", "التاسع والعشرون", "الثلاثون"]
        guard (1...30).contains(juz) else { return "" }
        return "الجزء " + ordinals[juz - 1]
    }
}

/// Justified Arabic text that knows which verse was tapped. (SwiftUI's Text
/// can't justify lines or report where it was tapped.)
private struct MushafTextView: UIViewRepresentable {
    let text: NSAttributedString
    /// The tapped verse ID, or nil if the tap wasn't on a verse.
    let onTap: (Int?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        // TextKit 1, for simple "which character is under the finger" lookups.
        let view = UITextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onTap = onTap
        if view.attributedText != text { view.attributedText = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: MushafTypesetter.height(text, width: width))
    }

    final class Coordinator: NSObject {
        var onTap: (Int?) -> Void = { _ in }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? UITextView else { return }
            let point = gesture.location(in: view)
            let manager = view.layoutManager
            let glyph = manager.glyphIndex(for: point, in: view.textContainer)
            let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: view.textContainer)
            guard rect.insetBy(dx: -6, dy: -6).contains(point) else {
                onTap(nil)
                return
            }
            let index = manager.characterIndexForGlyph(at: glyph)
            guard index < view.textStorage.length else {
                onTap(nil)
                return
            }
            onTap(view.textStorage.attribute(.niyatVerse, at: index, effectiveRange: nil) as? Int)
        }
    }
}

// MARK: - Ornaments

/// The page border: a double gold rule and, when illuminated, a tinted band
/// of alternating star flowers with rosettes in the corners.
private struct MushafFrame: View {
    let colors: MushafColors
    let border: MushafOptions.Border

    var body: some View {
        Canvas { context, size in
            let outer = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            switch border {
            case .none:
                return
            case .simple:
                context.stroke(Path(outer.insetBy(dx: 6, dy: 6)), with: .color(colors.gold), lineWidth: 1.6)
                context.stroke(Path(outer.insetBy(dx: 9, dy: 9)), with: .color(colors.gold.opacity(0.6)), lineWidth: 0.7)
                return
            case .illuminated:
                break
            }
            let band: CGFloat = 15
            let inner = outer.insetBy(dx: band, dy: band)

            var bandPath = Path(outer)
            bandPath.addRect(inner)
            context.fill(bandPath, with: .color(colors.band), style: FillStyle(eoFill: true))

            context.stroke(Path(outer), with: .color(colors.gold), lineWidth: 2)
            context.stroke(Path(outer.insetBy(dx: 3, dy: 3)), with: .color(colors.gold.opacity(0.6)), lineWidth: 0.7)
            context.stroke(Path(inner), with: .color(colors.gold), lineWidth: 1.6)
            context.stroke(Path(inner.insetBy(dx: 3, dy: 3)), with: .color(colors.gold.opacity(0.6)), lineWidth: 0.7)

            let middle = outer.insetBy(dx: band / 2, dy: band / 2)
            func flower(at point: CGPoint, radius: CGFloat, index: Int) {
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(EightPointStar().path(in: rect), with: .color(index.isMultiple(of: 2) ? colors.rose : colors.green))
                context.fill(Path(ellipseIn: rect.insetBy(dx: radius * 0.58, dy: radius * 0.58)), with: .color(colors.gold))
            }
            let step: CGFloat = 13
            var index = 0
            for x in stride(from: middle.minX + step * 1.5, through: middle.maxX - step * 1.5, by: step) {
                flower(at: CGPoint(x: x, y: middle.minY), radius: 4.2, index: index)
                flower(at: CGPoint(x: x, y: middle.maxY), radius: 4.2, index: index + 1)
                index += 1
            }
            for y in stride(from: middle.minY + step * 1.5, through: middle.maxY - step * 1.5, by: step) {
                flower(at: CGPoint(x: middle.minX, y: y), radius: 4.2, index: index)
                flower(at: CGPoint(x: middle.maxX, y: y), radius: 4.2, index: index + 1)
                index += 1
            }
            for corner in [CGPoint(x: middle.minX, y: middle.minY), CGPoint(x: middle.maxX, y: middle.minY),
                           CGPoint(x: middle.minX, y: middle.maxY), CGPoint(x: middle.maxX, y: middle.maxY)] {
                let rect = CGRect(x: corner.x - 9, y: corner.y - 9, width: 18, height: 18)
                context.fill(EightPointStar().path(in: rect), with: .color(colors.gold))
                context.fill(EightPointStar().path(in: rect.insetBy(dx: 4, dy: 4)), with: .color(colors.rose))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Gold label at the top of the page (surah name, juz).
private struct Cartouche: View {
    let text: String
    let colors: MushafColors

    var body: some View {
        Text(text)
            .font(.quran(size: 12))
            .foregroundStyle(colors.label)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .background(colors.band, in: .capsule)
            .overlay { Capsule().strokeBorder(colors.gold, lineWidth: 1) }
            .overlay { Capsule().strokeBorder(colors.gold.opacity(0.5), lineWidth: 0.6).padding(2.5) }
    }
}

/// The framed title where a new surah begins.
private struct SurahBanner: View {
    let surah: Surah
    let colors: MushafColors
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            EightPointStar().fill(colors.rose).frame(width: height * 0.45, height: height * 0.45)
            Spacer(minLength: 4)
            Text("سورة " + surah.name)
                .font(.quran(size: height * 0.42))
                .foregroundStyle(colors.label)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            EightPointStar().fill(colors.rose).frame(width: height * 0.45, height: height * 0.45)
        }
        .padding(.horizontal, height * 0.3)
        .frame(height: height)
        .background {
            IslamicPattern(tile: height * 0.7, lineWidth: 0.5, color: colors.gold.opacity(0.25))
                .background(colors.band)
        }
        .clipShape(.rect(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(colors.gold, lineWidth: 1.4) }
        .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(colors.gold.opacity(0.55), lineWidth: 0.6).padding(3) }
        .accessibilityLabel("Surah \(surah.transliteration)")
    }
}

/// The page number in a small medallion at the foot of the page.
private struct PageMedallion: View {
    let number: Int
    let colors: MushafColors

    var body: some View {
        ZStack {
            EightPointStar()
                .fill(colors.band)
                .overlay { EightPointStar().stroke(colors.gold, lineWidth: 1.2) }
                .frame(width: 30, height: 30)
            Text(MushafTypesetter.arabicDigits(number))
                .font(.quran(size: 11))
                .foregroundStyle(colors.label)
        }
        .accessibilityHidden(true)
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
