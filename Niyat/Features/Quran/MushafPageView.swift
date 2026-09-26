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
            .background {
                if options.layout == .screen {
                    options.style.colors.paper.ignoresSafeArea()
                } else {
                    AmbientBackground().ignoresSafeArea()
                }
            }
            .toolbarColorScheme(options.style.isLight && options.layout == .screen ? .light : .dark, for: .navigationBar)
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
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundStyle(barIconColor)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    MushafHeader(page: page, colors: options.style.colors)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Go to page, juz or surah", systemImage: "list.number") { showJump = true }
                        Button("Page settings", systemImage: "textformat.size") { showOptions = true }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(barIconColor)
                    }
                    .accessibilityLabel("Page options")
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
                // Opened while listening: go to the verse being recited.
                if options.followRecitation, !store.pageStarts.isEmpty, case .verse(let surah, let verse)? = player.current {
                    page = store.page(containing: VerseReference(surah: surah, verse: verse))
                }
                UIApplication.shared.isIdleTimerDisabled = options.keepScreenOn
            }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .task {
                await store.load()
                await TajweedStore.shared.load()
            }
        }
    }

    /// Bar buttons stay readable on light paper.
    private var barIconColor: Color {
        options.layout == .screen && options.style.isLight ? options.style.colors.label : .white
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

/// Surah · page · juz, in the navigation bar.
private struct MushafHeader: View {
    let page: Int
    let colors: MushafColors
    @State private var store = QuranStore.shared
    @State private var goal = QuranGoalModel.shared

    var body: some View {
        let start = store.pageStarts.isEmpty ? VerseReference(surah: 1, verse: 1) : store.pageStarts[min(page, store.pageStarts.count) - 1]
        HStack(spacing: 10) {
            Text("جزء \(MushafTypesetter.arabicDigits(store.juz(containing: start)))")
            ZStack {
                Circle().stroke(.secondary.opacity(0.4), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: goal.progress)
                    .stroke(Palette.control, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(MushafTypesetter.arabicDigits(page)).font(.quran(size: 12))
            }
            .frame(width: 30, height: 30)
            .accessibilityLabel("Page \(page), today's goal \(Int(goal.progress * 100)) percent")
            Text(store.surah(start.surah)?.name ?? "")
        }
        .font(.quran(size: 16))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .environment(\.layoutDirection, .rightToLeft)
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

    enum Layout: String, Codable, CaseIterable, Identifiable {
        /// Text across the whole screen, like most Qur'an apps.
        case screen
        /// A framed page, like holding a printed copy.
        case book
        var id: String { rawValue }
        var title: String { self == .screen ? "Full screen" : "Book page" }
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

    var layout = Layout.screen
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
        layout = value(.layout, d.layout)
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
    case paper, sepia, white, rose, mint, sky, lavender, stone, night, black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: "Cream"
        case .sepia: "Sepia"
        case .white: "White"
        case .rose: "Rose"
        case .mint: "Mint"
        case .sky: "Sky"
        case .lavender: "Lavender"
        case .stone: "Stone"
        case .night: "Night"
        case .black: "Black"
        }
    }

    /// Light pages get dark bars and text around them.
    var isLight: Bool { self != .night && self != .black }

    var colors: MushafColors {
        // The paper styles are deliberately fixed colours: they recreate a
        // printed mushaf rather than following the app theme.
        switch self {
        case .paper:
            .printed(paper: (0.985, 0.962, 0.885), shade: (0.94, 0.90, 0.79), band: (0.91, 0.94, 0.86),
                     gold: (0.72, 0.55, 0.24), green: (0.27, 0.47, 0.36), rose: (0.72, 0.33, 0.36),
                     ink: (0.11, 0.09, 0.07), marker: (0.55, 0.39, 0.10), label: (0.30, 0.24, 0.14))
        case .sepia:
            .printed(paper: (0.96, 0.91, 0.80), shade: (0.88, 0.80, 0.66), band: (0.93, 0.87, 0.74),
                     gold: (0.62, 0.45, 0.20), green: (0.35, 0.45, 0.30), rose: (0.62, 0.30, 0.28),
                     ink: (0.20, 0.13, 0.07), marker: (0.50, 0.32, 0.10), label: (0.36, 0.24, 0.12))
        case .white:
            .printed(paper: (1, 1, 1), shade: (0.95, 0.95, 0.95), band: (0.95, 0.96, 0.97),
                     gold: (0.70, 0.56, 0.28), green: (0.20, 0.45, 0.38), rose: (0.66, 0.28, 0.35),
                     ink: (0.05, 0.05, 0.05), marker: (0.45, 0.35, 0.12), label: (0.25, 0.25, 0.25))
        case .rose:
            .printed(paper: (0.99, 0.94, 0.93), shade: (0.95, 0.86, 0.85), band: (0.97, 0.89, 0.88),
                     gold: (0.72, 0.50, 0.32), green: (0.45, 0.55, 0.45), rose: (0.74, 0.36, 0.42),
                     ink: (0.16, 0.08, 0.09), marker: (0.62, 0.33, 0.30), label: (0.40, 0.20, 0.22))
        case .mint:
            .printed(paper: (0.93, 0.97, 0.93), shade: (0.85, 0.92, 0.86), band: (0.88, 0.94, 0.89),
                     gold: (0.60, 0.52, 0.26), green: (0.20, 0.47, 0.34), rose: (0.62, 0.36, 0.34),
                     ink: (0.05, 0.13, 0.09), marker: (0.20, 0.42, 0.30), label: (0.14, 0.32, 0.22))
        case .sky:
            .printed(paper: (0.93, 0.96, 0.99), shade: (0.85, 0.90, 0.96), band: (0.88, 0.92, 0.97),
                     gold: (0.66, 0.56, 0.30), green: (0.22, 0.42, 0.60), rose: (0.60, 0.34, 0.42),
                     ink: (0.05, 0.09, 0.16), marker: (0.20, 0.36, 0.58), label: (0.15, 0.27, 0.45))
        case .lavender:
            .printed(paper: (0.96, 0.94, 0.99), shade: (0.90, 0.86, 0.96), band: (0.92, 0.89, 0.97),
                     gold: (0.66, 0.54, 0.32), green: (0.38, 0.40, 0.62), rose: (0.62, 0.36, 0.56),
                     ink: (0.10, 0.07, 0.16), marker: (0.46, 0.34, 0.64), label: (0.32, 0.24, 0.46))
        case .stone:
            .printed(paper: (0.93, 0.93, 0.91), shade: (0.85, 0.85, 0.83), band: (0.89, 0.89, 0.87),
                     gold: (0.58, 0.52, 0.40), green: (0.36, 0.42, 0.38), rose: (0.55, 0.38, 0.38),
                     ink: (0.10, 0.10, 0.10), marker: (0.40, 0.38, 0.32), label: (0.30, 0.30, 0.28))
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
        case .black:
            // Pure black with silver ornaments: easy on the eyes at night and on OLED screens.
            .printed(paper: (0.07, 0.07, 0.08), shade: (0, 0, 0), band: (0.14, 0.14, 0.15),
                     gold: (0.62, 0.62, 0.64), green: (0.45, 0.45, 0.47), rose: (0.55, 0.55, 0.58),
                     ink: (0.96, 0.96, 0.96), marker: (0.72, 0.72, 0.74), label: (0.85, 0.85, 0.86))
        }
    }
}

struct MushafColors {
    typealias RGB = (Double, Double, Double)

    static func printed(paper: RGB, shade: RGB, band: RGB, gold: RGB, green: RGB, rose: RGB,
                        ink: RGB, marker: RGB, label: RGB) -> MushafColors {
        func color(_ c: RGB) -> Color { Color(red: c.0, green: c.1, blue: c.2) }
        func uiColor(_ c: RGB) -> UIColor { UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1) }
        return MushafColors(paper: color(paper), paperShade: color(shade), band: color(band), gold: color(gold),
                            green: color(green), rose: color(rose), ink: uiColor(ink), marker: uiColor(marker),
                            label: color(label))
    }

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
    @AppStorage("quran.tajweed") private var tajweedOn = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Layout") {
                    Picker("Layout", selection: $options.layout) {
                        ForEach(MushafOptions.Layout.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Paper") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
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
                                        .frame(height: 52)
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
                }

                if options.layout == .book {
                    Section("Book page") {
                        Picker("Border", selection: $options.border) {
                            ForEach(MushafOptions.Border.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Toggle("Surah and juz at the top", isOn: $options.showHeader)
                    }
                }

                Section {
                    VStack(alignment: .leading) {
                        LabeledContent("Text size", value: options.textScale <= 1.001 ? "Fit page" : "\(Int(options.textScale * 100))%")
                        Slider(value: $options.textScale, in: 1...1.6, step: 0.1)
                    }
                } footer: {
                    Text("At \"Fit page\" each page fills its frame like a printed mushaf. Bigger text scrolls within the page.")
                }

                Section {
                    Toggle("Tajweed colours", isOn: $tajweedOn)
                    NavigationLink("Colour guide") { TajweedGuideView() }
                } header: {
                    Text("Tajweed")
                } footer: {
                    Text("For the Uthmani script (Hafs).")
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
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var viewportHeight: CGFloat = 0

    static let pageSpace = "mushafPage"

    /// Keeps the verse being recited in view when bigger text makes the page scroll.
    private func scrollToVerse(atY y: CGFloat) {
        guard isCurrent, options.textScale > 1.001 else { return }
        withAnimation(.smooth(duration: 0.5)) {
            scrollPosition.scrollTo(y: max(0, y - viewportHeight * 0.3))
        }
    }

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

    @AppStorage("quran.tajweed") private var tajweedOn = true
    @State private var tajweedStore = TajweedStore.shared

    /// Tajweed colours are for the Uthmani (Hafs) text they were made for.
    private var showsTajweed: Bool {
        tajweedOn && store.edition == .uthmani && tajweedStore.isLoaded
    }

    var body: some View {
        let verses = store.verses(onPage: number)
        GeometryReader { geo in
            let size = options.layout == .screen ? geo.size : Self.pageSize(in: geo.size)
            let pageLayout = makeLayout(verses, size: size)
            ScrollView(.vertical) {
                page(verses, layout: pageLayout)
                    .frame(width: size.width, height: pageLayout.pageHeight)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    .coordinateSpace(.named(Self.pageSpace))
            }
            .scrollPosition($scrollPosition)
            .scrollDisabled(pageLayout.pageHeight <= size.height + 1)
            .scrollIndicators(.hidden)
            .onAppear { viewportHeight = geo.size.height }
            .onChange(of: geo.size.height) { _, height in viewportHeight = height }
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
        let textWidth: CGFloat
        let textHeight: CGFloat
        let maxSize: CGFloat
        switch options.layout {
        case .screen:
            textWidth = size.width - Self.screenMargin * 2
            textHeight = size.height - Self.screenTop - Self.footerHeight - Self.spacing
            maxSize = min(36, textWidth / 10.5)
        case .book:
            let headerHeight = options.showHeader ? Self.headerHeight + Self.spacing : 0
            textWidth = size.width - contentInset * 2
            textHeight = size.height - contentInset * 2 - headerHeight - Self.footerHeight - Self.spacing
            maxSize = min(30, textWidth / 10)
        }
        let fit = MushafTypesetter.fittingSize(page: number, segments: segments, store: store,
                                               width: textWidth, height: textHeight, maxSize: maxSize)
        guard options.textScale > 1.001 else { return Layout(segments: segments, fontSize: fit, pageHeight: size.height) }
        // Bigger than print: the page grows and scrolls.
        let fontSize = fit * options.textScale
        let needed = MushafTypesetter.totalHeight(segments, size: fontSize, width: textWidth, store: store)
        return Layout(segments: segments, fontSize: fontSize, pageHeight: size.height + max(0, needed - textHeight))
    }

    private static let screenMargin: CGFloat = 12
    private static let screenTop: CGFloat = 14

    @ViewBuilder
    private func page(_ verses: [Verse], layout: Layout) -> some View {
        switch options.layout {
        case .screen: screenPage(layout: layout)
        case .book: bookPage(verses, layout: layout)
        }
    }

    /// Full-screen layout: text across the whole screen, page number below.
    private func screenPage(layout: Layout) -> some View {
        VStack(spacing: Self.spacing) {
            segmentViews(layout)
            Spacer(minLength: 0)
            Text(MushafTypesetter.arabicDigits(number))
                .font(.quran(size: 15))
                .foregroundStyle(colors.label)
                .frame(height: Self.footerHeight)
                .accessibilityLabel("Page \(number)")
        }
        .padding(.horizontal, Self.screenMargin)
        .padding(.top, Self.screenTop)
    }

    /// Banners, Bismillah and verses, shared by both layouts.
    private func segmentViews(_ layout: Layout) -> some View {
        let fontSize = layout.fontSize
        return ForEach(layout.segments) { segment in
            switch segment.kind {
            case .banner(let surah):
                SurahBanner(surah: surah, colors: colors, height: MushafTypesetter.bannerHeight(fontSize))
                    .onTapGesture { onTap(nil) }
            case .bismillah:
                MushafTextView(text: MushafTypesetter.centered(store.bismillah, size: fontSize, color: colors.ink,
                                                               tajweedBismillah: showsTajweed, dark: !options.style.isLight)) { _ in
                    onTap(nil)
                }
            case .verses(let verses):
                VerseTextBlock(text: MushafTypesetter.verses(verses, size: fontSize, colors: colors,
                                                             sajdahs: store.sajdahVerses,
                                                             selected: selected,
                                                             reciting: options.highlightRecitation ? reciting : nil,
                                                             tajweed: showsTajweed, dark: !options.style.isLight),
                               focus: reciting.flatMap { id in verses.contains { $0.id == id } ? id : nil },
                               onScroll: scrollToVerse) { id in
                    onTap(id.flatMap { id in verses.first { $0.id == id } })
                }
            }
        }
    }

    /// Book layout: a framed printed page.
    private func bookPage(_ verses: [Verse], layout: Layout) -> some View {
        let first = verses.first?.hafsReference ?? VerseReference(surah: 1, verse: 1)

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
                    segmentViews(layout)
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

    static func bannerHeight(_ fontSize: CGFloat) -> CGFloat { fontSize * 2.1 }

    /// The largest text size at which the whole page fits, like a printed page
    /// filling its frame. Capped so short pages (Al-Fatiha) don't get huge.
    static func fittingSize(page: Int, segments: [MushafSegment], store: QuranStore,
                            width: CGFloat, height: CGFloat, maxSize: CGFloat) -> CGFloat {
        let key = "\(page)-\(Int(width))-\(Int(height))-\(Int(maxSize))-\(store.edition.rawValue)"
        if let cached = sizeCache[key] { return cached }
        var low: CGFloat = 9
        var high = maxSize
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

    /// Lines sit close together like a printed mushaf. Amiri Quran's natural
    /// line is 2.45× its size (room for stacked marks); print is closer to 1.8×.
    static let lineHeight: CGFloat = 1.8

    private static func paragraph(_ alignment: NSTextAlignment, size: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.baseWritingDirection = .rightToLeft
        style.lineBreakMode = .byWordWrapping
        style.minimumLineHeight = size * lineHeight
        style.maximumLineHeight = size * lineHeight
        style.lineSpacing = 0
        return style
    }

    static func centered(_ text: String, size: CGFloat, color: UIColor, tajweedBismillah: Bool = false, dark: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: font(size), .foregroundColor: color,
                                                                          .paragraphStyle: paragraph(.center, size: size)])
        if tajweedBismillah {
            TajweedStore.shared.colour(result, verseText: text, at: 0, surah: 1, verse: 1, dark: dark)
        }
        return result
    }

    /// Verses run together, justified, each closed by an ayah marker ۝ with its
    /// number in Arabic-Indic digits (the font draws the ornament around it).
    static func verses(_ verses: [Verse], size: CGFloat, colors: MushafColors, sajdahs: Set<VerseReference>,
                       selected: Int?, reciting: Int?, tajweed: Bool = false, dark: Bool = false) -> NSAttributedString {
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
            let start = text.length
            text.append(NSAttributedString(string: verse.arabic, attributes: attributes))
            if tajweed {
                TajweedStore.shared.colour(text, verseText: verse.arabic, at: start,
                                           surah: verse.surah, verse: verse.number, dark: dark)
            }
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

/// A run of verses that reports where the reciting verse is on the page.
private struct VerseTextBlock: View {
    let text: NSAttributedString
    let focus: Int?
    let onScroll: (CGFloat) -> Void
    let onTap: (Int?) -> Void
    @State private var top: CGFloat = 0

    var body: some View {
        MushafTextView(text: text, focus: focus, onFocus: { rect in onScroll(top + rect.minY) }, onTap: onTap)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(MushafPage.pageSpace)).minY
            } action: { top = $0 }
    }
}

/// Justified Arabic text that knows which verse was tapped. (SwiftUI's Text
/// can't justify lines or report where it was tapped.)
private struct MushafTextView: UIViewRepresentable {
    let text: NSAttributedString
    /// A verse to bring into view (the one being recited), and where it is
    /// reported: its rectangle inside this text.
    var focus: Int? = nil
    var onFocus: ((CGRect) -> Void)? = nil
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
        // Lines are tighter than the font's natural height, so tall marks may
        // reach just outside the view: draw them rather than clip them.
        view.clipsToBounds = false
        view.layer.masksToBounds = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onTap = onTap
        if view.attributedText != text { view.attributedText = text }
        guard focus != context.coordinator.lastFocus else { return }
        context.coordinator.lastFocus = focus
        guard let focus, let onFocus else { return }
        // After this layout pass, find where the verse sits and report it.
        DispatchQueue.main.async {
            var range: NSRange?
            view.textStorage.enumerateAttribute(.niyatVerse, in: NSRange(location: 0, length: view.textStorage.length)) { value, found, stop in
                if value as? Int == focus {
                    range = found
                    stop.pointee = true
                }
            }
            guard let range else { return }
            view.layoutManager.ensureLayout(for: view.textContainer)
            let glyphs = view.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            onFocus(view.layoutManager.boundingRect(forGlyphRange: glyphs, in: view.textContainer))
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: MushafTypesetter.height(text, width: width))
    }

    final class Coordinator: NSObject {
        var onTap: (Int?) -> Void = { _ in }
        var lastFocus: Int?

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

/// The ornamental title where a new surah begins: a framed band with a
/// pointed cartouche in the middle and rosettes on each side.
private struct SurahBanner: View {
    let surah: Surah
    let colors: MushafColors
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let midY = rect.midY
            context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(colors.band))
            context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(colors.gold), lineWidth: 1.4)
            context.stroke(Path(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerRadius: 2),
                           with: .color(colors.gold.opacity(0.55)), lineWidth: 0.6)

            // Centre cartouche with pointed ends.
            let cartoucheWidth = rect.width * 0.46
            let cartoucheHeight = rect.height * 0.74
            let tip = cartoucheHeight * 0.45
            func cartouche(_ inset: CGFloat) -> Path {
                let left = rect.midX - cartoucheWidth / 2 + inset, right = rect.midX + cartoucheWidth / 2 - inset
                let top = midY - cartoucheHeight / 2 + inset, bottom = midY + cartoucheHeight / 2 - inset
                var path = Path()
                path.move(to: CGPoint(x: left, y: midY))
                path.addLine(to: CGPoint(x: left + tip, y: top))
                path.addLine(to: CGPoint(x: right - tip, y: top))
                path.addLine(to: CGPoint(x: right, y: midY))
                path.addLine(to: CGPoint(x: right - tip, y: bottom))
                path.addLine(to: CGPoint(x: left + tip, y: bottom))
                path.closeSubpath()
                return path
            }
            context.fill(cartouche(0), with: .color(colors.paper))
            context.stroke(cartouche(0), with: .color(colors.gold), lineWidth: 1.4)
            context.stroke(cartouche(3), with: .color(colors.gold.opacity(0.5)), lineWidth: 0.6)

            // Side panels: a rosette in each, joined to the cartouche by fine scrolls.
            let panelWidth = (rect.width - cartoucheWidth) / 2
            for side in [-1.0, 1.0] {
                let centreX = rect.midX + side * (cartoucheWidth / 2 + panelWidth / 2)
                let radius = rect.height * 0.3
                let flower = CGRect(x: centreX - radius, y: midY - radius, width: radius * 2, height: radius * 2)
                context.fill(EightPointStar().path(in: flower), with: .color(colors.rose.opacity(0.85)))
                context.stroke(EightPointStar().path(in: flower), with: .color(colors.gold), lineWidth: 0.8)
                context.fill(Path(ellipseIn: flower.insetBy(dx: radius * 0.55, dy: radius * 0.55)), with: .color(colors.gold))
                for offset in [-0.5, 0.5] {
                    let x = centreX + offset * panelWidth * 0.62
                    let small = CGRect(x: x - radius * 0.38, y: midY - radius * 0.38, width: radius * 0.76, height: radius * 0.76)
                    context.fill(EightPointStar().path(in: small), with: .color(colors.green.opacity(0.8)))
                }
                var scroll = Path()
                let inner = rect.midX + side * cartoucheWidth / 2
                let outer = rect.midX + side * (rect.width / 2 - 8)
                for dy in [-rect.height * 0.3, rect.height * 0.3] {
                    scroll.move(to: CGPoint(x: inner, y: midY + dy * 0.4))
                    scroll.addQuadCurve(to: CGPoint(x: outer, y: midY + dy),
                                        control: CGPoint(x: (inner + outer) / 2, y: midY + dy * 1.4))
                }
                context.stroke(scroll, with: .color(colors.gold.opacity(0.7)), lineWidth: 0.8)
            }
        }
        .frame(height: height)
        .overlay {
            GeometryReader { geo in
                Text("سورة " + surah.name)
                    .font(.quran(size: height * 0.4))
                    .foregroundStyle(colors.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: geo.size.width * 0.36, height: geo.size.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .accessibilityElement(children: .ignore)
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
