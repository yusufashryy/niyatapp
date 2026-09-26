import SwiftUI
import UIKit

/// The Qur'an page by page, styled like a printed Madinah mushaf.
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
    @AppStorage("quran.mushafStyle") private var style = MushafStyle.paper
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
                            MushafPage(number: number, isCurrent: number == page, colors: style.colors)
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
                    Menu {
                        Button("Go to page, juz or surah", systemImage: "list.number") { showJump = true }
                        Picker("Page style", selection: $style) {
                            ForEach(MushafStyle.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Page options")
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

// MARK: - Look

enum MushafStyle: String, CaseIterable, Identifiable {
    /// Cream paper and a coloured border, like a printed copy.
    case paper
    /// Dark page in the app's theme colours, for reading at night.
    case night

    var id: String { rawValue }
    var title: String { self == .paper ? "Paper" : "Night" }
    var icon: String { self == .paper ? "sun.max" : "moon" }

    var colors: MushafColors {
        switch self {
        case .paper:
            // Deliberately fixed: these recreate a printed mushaf, not the app theme.
            MushafColors(paper: Color(red: 0.985, green: 0.962, blue: 0.885),
                         paperShade: Color(red: 0.94, green: 0.90, blue: 0.79),
                         band: Color(red: 0.91, green: 0.94, blue: 0.86),
                         gold: Color(red: 0.72, green: 0.55, blue: 0.24),
                         green: Color(red: 0.27, green: 0.47, blue: 0.36),
                         rose: Color(red: 0.72, green: 0.33, blue: 0.36),
                         ink: UIColor(red: 0.11, green: 0.09, blue: 0.07, alpha: 1),
                         marker: UIColor(red: 0.55, green: 0.39, blue: 0.10, alpha: 1),
                         label: Color(red: 0.30, green: 0.24, blue: 0.14))
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

// MARK: - Page

/// One page: ornamental frame, header labels, surah banners, Bismillah,
/// justified verses with ayah markers, and the page number.
private struct MushafPage: View {
    let number: Int
    let isCurrent: Bool
    let colors: MushafColors

    @State private var store = QuranStore.shared
    @State private var goal = QuranGoalModel.shared
    @State private var readTask: Task<Void, Never>?

    // Page geometry, in points.
    private static let aspect: CGFloat = 0.64
    private static let contentInset: CGFloat = 30
    private static let headerHeight: CGFloat = 26
    private static let footerHeight: CGFloat = 30
    private static let spacing: CGFloat = 6

    var body: some View {
        let verses = store.verses(onPage: number)
        GeometryReader { geo in
            let size = Self.pageSize(in: geo.size)
            page(verses, size: size)
                .frame(width: size.width, height: size.height)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
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

    private static func pageSize(in available: CGSize) -> CGSize {
        let width = max(available.width - 20, 100)
        let height = max(available.height - 16, 100)
        return width / height > aspect
            ? CGSize(width: height * aspect, height: height)
            : CGSize(width: width, height: width / aspect)
    }

    private func page(_ verses: [Verse], size: CGSize) -> some View {
        let segments = MushafTypesetter.segments(for: verses, store: store)
        let textWidth = size.width - Self.contentInset * 2
        let textHeight = size.height - Self.contentInset * 2 - Self.headerHeight - Self.footerHeight - Self.spacing * 2
        let fontSize = MushafTypesetter.fittingSize(page: number, segments: segments, store: store,
                                                    width: textWidth, height: textHeight)
        let first = verses.first?.hafsReference ?? VerseReference(surah: 1, verse: 1)

        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(RadialGradient(colors: [colors.paper, colors.paperShade], center: .center,
                                     startRadius: size.width * 0.3, endRadius: size.height * 0.75))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            MushafFrame(colors: colors)
                .padding(6)

            VStack(spacing: Self.spacing) {
                // Header: surah on the right, juz on the left, as in print.
                HStack {
                    Cartouche(text: MushafTypesetter.juzName(store.juz(containing: first)), colors: colors)
                    Spacer()
                    Cartouche(text: "سورة " + (store.surah(first.surah)?.name ?? ""), colors: colors)
                }
                .frame(height: Self.headerHeight)

                VStack(spacing: Self.spacing) {
                    ForEach(segments) { segment in
                        switch segment.kind {
                        case .banner(let surah):
                            SurahBanner(surah: surah, colors: colors, height: MushafTypesetter.bannerHeight(fontSize))
                        case .bismillah:
                            AttributedLabel(text: MushafTypesetter.centered(store.bismillah, size: fontSize, color: colors.ink))
                        case .verses(let verses):
                            AttributedLabel(text: MushafTypesetter.verses(verses, size: fontSize, colors: colors,
                                                                          sajdahs: store.sajdahVerses))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                PageMedallion(number: number, colors: colors)
                    .frame(height: Self.footerHeight)
            }
            .padding(Self.contentInset)
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

    private static func totalHeight(_ segments: [MushafSegment], size: CGFloat, width: CGFloat, store: QuranStore) -> CGFloat {
        let colors = MushafStyle.paper.colors
        var total = CGFloat(max(segments.count - 1, 0)) * 6
        for segment in segments {
            switch segment.kind {
            case .banner: total += bannerHeight(size)
            case .bismillah: total += height(centered(store.bismillah, size: size, color: colors.ink), width: width)
            case .verses(let verses):
                total += height(self.verses(verses, size: size, colors: colors, sajdahs: store.sajdahVerses), width: width)
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
    static func verses(_ verses: [Verse], size: CGFloat, colors: MushafColors,
                       sajdahs: Set<VerseReference>) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.font: font(size), .foregroundColor: colors.ink,
                                                   .paragraphStyle: paragraph(.justified, size: size)]
        for verse in verses {
            // (The Bismillah is already split off verse 1 when the text loads.)
            text.append(NSAttributedString(string: verse.arabic, attributes: base))
            var markerAttributes = base
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

/// A UILabel, because SwiftUI's Text can't justify lines.
private struct AttributedLabel: UIViewRepresentable {
    let text: NSAttributedString

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: MushafTypesetter.height(text, width: width))
    }
}

// MARK: - Ornaments

/// The illuminated border: a double gold rule, a tinted band of alternating
/// star flowers, and rosettes in the corners.
private struct MushafFrame: View {
    let colors: MushafColors

    var body: some View {
        Canvas { context, size in
            let outer = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
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
