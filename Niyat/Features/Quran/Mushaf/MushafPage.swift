import SwiftUI
import UIKit

/// One page of the mushaf: surah and part at the top, the page's 15 lines,
/// and the page number. Every line is exactly as in the printed Madinah
/// mushaf; each is justified to the full width.
struct MushafPage: View {
    let number: Int
    let isCurrent: Bool
    let colors: MushafColors
    let tajweed: Bool
    let highContrast: Bool
    var textSize = MushafOptions.TextSize.standard
    var weight: CGFloat = 0
    /// The reading ribbon lies in this page.
    var hasRibbon = false
    var placement = MushafBook.Placement.single
    /// The page was zoomed in (true) or back to fit (false).
    var onZoomChange: (Bool) -> Void = { _ in }
    /// The page number was tapped (opens the scrubber).
    var onPageNumber: () -> Void = {}
    /// A word was tapped (nil: outside the text), and on which line.
    let onTap: (WordID?, Int) -> Void

    @State private var store = QuranStore.shared
    @State private var goal = QuranGoalModel.shared
    @State private var readTask: Task<Void, Never>?
    // Pinch to zoom: the settled zoom and pan, and the gesture in progress.
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var anchor: UnitPoint = .center
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private static let maxZoom: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            if let text = MushafPageText.page(number) {
                let scale = min(max(zoom * pinch, 1), Self.maxZoom)
                content(text, size: geo.size)
                    .scaleEffect(scale, anchor: anchor)
                    .offset(clamped(CGSize(width: pan.width + drag.width, height: pan.height + drag.height),
                                    scale: scale, size: geo.size))
                    .clipped()
                    .contentShape(.rect)
                    .gesture(magnify)
                    // While zoomed, dragging moves around the page instead of turning it.
                    .highPriorityGesture(panning(size: geo.size), including: zoom > 1 ? .all : .subviews)
            } else {
                Color.clear
            }
        }
        .onChange(of: isCurrent) { _, current in
            if !current { resetZoom() }
        }
        .onChange(of: zoom > 1) { _, zoomed in onZoomChange(zoomed) }
        .onChange(of: isCurrent, initial: true) { _, current in
            readTask?.cancel()
            let verses = store.verses(onPage: number)
            guard current, !verses.isEmpty else { return }
            // Count the page towards today's goal once it has stayed open long
            // enough to actually be read.
            let dwell = ReadingRibbon.pageDwell(verseCount: verses.count)
            readTask = Task {
                try? await Task.sleep(for: .seconds(dwell))
                guard !Task.isCancelled else { return }
                for verse in verses { goal.recordRead(verse) }
            }
        }
        .onDisappear { readTask?.cancel() }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onChanged { value in
                if zoom == 1 { anchor = value.startAnchor }
            }
            .onEnded { value in
                let settled = min(max(zoom * value.magnification, 1), Self.maxZoom)
                if settled < 1.08 {
                    withAnimation(.smooth) { resetZoom() }
                } else {
                    zoom = settled
                }
            }
    }

    private func panning(size: CGSize) -> some Gesture {
        DragGesture()
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                pan = clamped(CGSize(width: pan.width + value.translation.width, height: pan.height + value.translation.height),
                              scale: zoom, size: size)
            }
    }

    /// Keeps the zoomed page covering the screen: scaled about the anchor,
    /// its edges may move in by at most the extra size on each side.
    private func clamped(_ offset: CGSize, scale: CGFloat, size: CGSize) -> CGSize {
        let extraX = (scale - 1) * size.width, extraY = (scale - 1) * size.height
        return CGSize(width: min(max(offset.width, -extraX * (1 - anchor.x)), extraX * anchor.x),
                      height: min(max(offset.height, -extraY * (1 - anchor.y)), extraY * anchor.y))
    }

    private func resetZoom() {
        zoom = 1
        pan = .zero
        anchor = .center
    }

    private func content(_ text: MushafPageText, size available: CGSize) -> some View {
        // A printed page's shape: on a wide screen (iPad, landscape) the page
        // sits in the middle instead of stretching sideways.
        let size = CGSize(width: min(available.width, available.height * MushafMetrics.pageShape),
                          height: available.height)
        let margin = MushafMetrics.margin(for: size.width, share: textSize.margin)
        let width = size.width - margin * 2
        let linesHeight = max(size.height - MushafMetrics.headerHeight - MushafMetrics.footerHeight, 100)
        let rowHeight = floor(linesHeight / CGFloat(MushafMetrics.lineCount))
        let fontSize = MushafMetrics.fontSize(for: text, width: width, rowHeight: rowHeight, squeeze: textSize.squeeze)
        var style = colors.textStyle(size: fontSize, tajweed: tajweed, highContrast: highContrast,
                                     weight: weight, squeeze: textSize.squeeze)
        style.ribbon = store.ribbon.map { VerseKey(surah: $0.surah, verse: $0.verse) }
        style.ribbonColor = QuranTextStyle.ribbonRed.withAlphaComponent(colors.isLight ? 0.13 : 0.24)
        let label = Color(colors.label)

        return VStack(spacing: 0) {
            HStack {
                Text(store.surah(text.surah)?.transliteration ?? "")
                Spacer()
                Text("Part \(text.juz)")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(label)
            .lineLimit(1).minimumScaleFactor(0.75)
            .frame(height: MushafMetrics.headerHeight)
            .contentShape(.rect)
            .onTapGesture { onTap(nil, 0) }
            .accessibilityElement(children: .combine)

            // The opening pages have fewer, centred lines, in the middle of the page.
            if text.isOpening { Spacer(minLength: 0) }
            ForEach(Array(text.rows.enumerated()), id: \.offset) { index, row in
                rowView(row, index: index, style: style, opening: text.isOpening)
                    .frame(height: rowHeight)
            }
            Spacer(minLength: 0)

            footer(label: label)
        }
        .padding(.horizontal, margin)
        // The ribbon hangs from the top edge, over the gap between the surah
        // name and the part number, just reaching the first line.
        .overlay(alignment: .top) {
            if hasRibbon {
                RibbonMark(color: Color(QuranTextStyle.ribbonRed), starColor: Color(colors.paper))
                    .frame(width: 18, height: MushafMetrics.headerHeight + 16)
                    .offset(y: -6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay { PageBinding(placement: placement, page: number, colors: colors) }
        // Facing pages meet at the spine; a single page sits in the middle.
        .frame(width: available.width, height: available.height, alignment: pageAlignment)
    }

    private var pageAlignment: Alignment {
        switch placement {
        case .single: .center
        case .right: .leading
        case .left: .trailing
        }
    }

    /// The page number in the middle; a hizb mark, where one starts on this
    /// page, in the outer corner. Tapping the number opens the scrubber.
    private func footer(label: Color) -> some View {
        ZStack {
            if let hizb = hizbMark {
                Text(hizb)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(label.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: placement == .right ? .trailing : .leading)
            }
            Button(action: onPageNumber) {
                Text("\(number)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(label)
                    .padding(.horizontal, 16)
                    .frame(height: MushafMetrics.footerHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Page \(number)")
            .accessibilityHint("Shows a scrubber to move through the mushaf")
        }
        .frame(maxWidth: .infinity)
        .frame(height: MushafMetrics.footerHeight)
        // Around the number: like the top of the page, outside the text.
        .contentShape(.rect)
        .onTapGesture { onTap(nil, MushafMetrics.lineCount - 1) }
    }

    /// The hizb quarter that starts on this page, if any.
    private var hizbMark: String? {
        guard let quarter = store.hizbStarts.firstIndex(where: { store.page(containing: $0) == number }) else { return nil }
        return MushafBook.hizbLabel(quarter: quarter + 1)
    }

    @ViewBuilder
    private func rowView(_ row: MushafPageText.Row, index: Int, style: QuranTextStyle, opening: Bool) -> some View {
        switch row {
        case .header(let surah):
            SurahFrame(surah: store.surah(surah), colors: colors, fontSize: style.fontSize)
                .padding(.vertical, 2)
                .contentShape(.rect)
                .onTapGesture { onTap(nil, index) }
        case .basmala(let piece):
            QuranTextView(pieces: [piece], style: basmalaStyle(style), layout: .centredLine,
                          sharpness: zoom) { _ in onTap(nil, index) }
        case .text(let pieces):
            QuranTextView(pieces: pieces, style: style, layout: opening ? .centredLine : .justifiedLine,
                          sharpness: zoom) { word in
                onTap(word, index)
            }
        case .empty:
            Color.clear
        }
    }

    /// The Bismillah line: centred, without a band or highlights of its own.
    private func basmalaStyle(_ style: QuranTextStyle) -> QuranTextStyle {
        var style = style
        style.band = nil
        return style
    }
}

/// What makes a page look bound into a book: a soft shadow by the spine and,
/// on the outer edge, the edges of the pages on that side, more of them the
/// further you are from that cover.
private struct PageBinding: View {
    let placement: MushafBook.Placement
    let page: Int
    let colors: MushafColors

    var body: some View {
        let edges = MushafBook.edges(page: page)
        HStack(spacing: 0) {
            switch placement {
            case .single, .left:
                PageEdges(share: edges.unread, color: Color(colors.frame))
                Spacer(minLength: 0)
                spine(fadingTo: .leading)
            case .right:
                spine(fadingTo: .trailing)
                Spacer(minLength: 0)
                PageEdges(share: edges.read, color: Color(colors.frame))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func spine(fadingTo edge: UnitPoint) -> some View {
        LinearGradient(colors: [.black.opacity(placement == .single ? 0.08 : 0.16), .clear],
                       startPoint: edge == .leading ? .trailing : .leading, endPoint: edge)
            .frame(width: placement == .single ? 10 : 22)
    }
}

/// Fine lines for the edges of the pages beyond this one.
private struct PageEdges: View {
    let share: CGFloat
    let color: Color

    var body: some View {
        let count = Int((share * 4).rounded(.up))
        HStack(spacing: 1.4) {
            ForEach(0..<count, id: \.self) { index in
                Rectangle()
                    .fill(color.opacity(0.45 - Double(index) * 0.08))
                    .frame(width: 0.6)
            }
        }
        .padding(.vertical, 6)
    }
}
