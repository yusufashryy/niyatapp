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
    /// A word was tapped (nil: outside the text), and on which line.
    let onTap: (WordID?, Int) -> Void

    @State private var store = QuranStore.shared
    @State private var goal = QuranGoalModel.shared
    @State private var readTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            if let text = MushafPageText.page(number) {
                content(text, size: geo.size)
            } else {
                Color.clear
            }
        }
        .onChange(of: isCurrent, initial: true) { _, current in
            readTask?.cancel()
            let verses = store.verses(onPage: number)
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

    private func content(_ text: MushafPageText, size: CGSize) -> some View {
        let margin = MushafMetrics.margin(for: size.width)
        let width = size.width - margin * 2
        let linesHeight = max(size.height - MushafMetrics.headerHeight - MushafMetrics.footerHeight, 100)
        let rowHeight = floor(linesHeight / CGFloat(MushafMetrics.lineCount))
        let fontSize = MushafMetrics.fontSize(for: text, width: width, rowHeight: rowHeight)
        let style = colors.textStyle(size: fontSize, tajweed: tajweed, highContrast: highContrast)
        let label = Color(colors.label)

        return VStack(spacing: 0) {
            HStack {
                Text(store.surah(text.surah)?.transliteration ?? "")
                Spacer()
                Text("Part \(text.juz)")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(label)
            .lineLimit(1)
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

            Text("\(number)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(label)
                .frame(maxWidth: .infinity)
                .frame(height: MushafMetrics.footerHeight)
                .contentShape(.rect)
                .onTapGesture { onTap(nil, 0) }
                .accessibilityLabel("Page \(number)")
        }
        .padding(.horizontal, margin)
        .frame(width: size.width, height: size.height)
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
            QuranTextView(pieces: [piece], style: basmalaStyle(style), layout: .centredLine) { _ in onTap(nil, index) }
        case .text(let pieces):
            QuranTextView(pieces: pieces, style: style, layout: opening ? .centredLine : .justifiedLine) { word in
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

/// The frame around a surah's title: a pointed cartouche for the name, with
/// star rosettes on each side. Niyat's own drawing, in the page's colours.
struct SurahFrame: View {
    let surah: Surah?
    let colors: MushafColors
    let fontSize: CGFloat

    var body: some View {
        let frame = Color(colors.frame)
        let fill = Color(colors.frameFill)
        let ornament = Color(colors.ornament)
        let paper = Color(colors.paper)
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let midY = rect.midY
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(fill))
            context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(frame), lineWidth: 1.2)
            context.stroke(Path(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerRadius: 2),
                           with: .color(frame.opacity(0.55)), lineWidth: 0.6)

            // The name sits in a cartouche with pointed ends.
            let cartoucheWidth = rect.width * 0.5
            let cartoucheHeight = rect.height * 0.76
            let tip = cartoucheHeight * 0.5
            func cartouche(_ inset: CGFloat) -> Path {
                let left = rect.midX - cartoucheWidth / 2 + inset, right = rect.midX + cartoucheWidth / 2 - inset
                let top = midY - cartoucheHeight / 2 + inset, bottom = midY + cartoucheHeight / 2 - inset
                var path = Path()
                path.move(to: CGPoint(x: left, y: midY))
                path.addQuadCurve(to: CGPoint(x: left + tip, y: top), control: CGPoint(x: left + tip * 0.2, y: top))
                path.addLine(to: CGPoint(x: right - tip, y: top))
                path.addQuadCurve(to: CGPoint(x: right, y: midY), control: CGPoint(x: right - tip * 0.2, y: top))
                path.addQuadCurve(to: CGPoint(x: right - tip, y: bottom), control: CGPoint(x: right - tip * 0.2, y: bottom))
                path.addLine(to: CGPoint(x: left + tip, y: bottom))
                path.addQuadCurve(to: CGPoint(x: left, y: midY), control: CGPoint(x: left + tip * 0.2, y: bottom))
                path.closeSubpath()
                return path
            }
            context.fill(cartouche(0), with: .color(paper))
            context.stroke(cartouche(0), with: .color(frame), lineWidth: 1.2)
            context.stroke(cartouche(2.5), with: .color(frame.opacity(0.5)), lineWidth: 0.6)

            // Side panels: a fine line from the cartouche, a star rosette in
            // the middle and a smaller star on each side of it.
            let panelWidth = (rect.width - cartoucheWidth) / 2
            for side in [-1.0, 1.0] {
                var line = Path()
                line.move(to: CGPoint(x: rect.midX + side * cartoucheWidth / 2, y: midY))
                line.addLine(to: CGPoint(x: rect.midX + side * (rect.width / 2 - 6), y: midY))
                context.stroke(line, with: .color(frame.opacity(0.45)), lineWidth: 0.6)

                let centreX = rect.midX + side * (cartoucheWidth / 2 + panelWidth / 2)
                let radius = min(rect.height * 0.3, panelWidth * 0.2)
                let flower = CGRect(x: centreX - radius, y: midY - radius, width: radius * 2, height: radius * 2)
                context.fill(EightPointStar().path(in: flower), with: .color(ornament.opacity(0.85)))
                context.stroke(EightPointStar().path(in: flower), with: .color(frame), lineWidth: 0.8)
                context.fill(Path(ellipseIn: flower.insetBy(dx: radius * 0.58, dy: radius * 0.58)), with: .color(frame))
                for offset in [-0.3, 0.3] {
                    let x = centreX + offset * panelWidth
                    let small = CGRect(x: x - radius * 0.4, y: midY - radius * 0.4, width: radius * 0.8, height: radius * 0.8)
                    context.fill(EightPointStar().path(in: small), with: .color(frame.opacity(0.8)))
                }
            }
        }
        .overlay {
            GeometryReader { geo in
                let size = fontSize * 1.1
                Text("سورة " + (surah?.name ?? ""))
                    .font(.quran(size: size))
                    .foregroundStyle(Color(colors.label))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: geo.size.width * 0.4, height: geo.size.height)
                    // Amiri Quran's line is tall (room for stacked marks), so
                    // its letters sit low in the line: lift them to the middle.
                    .offset(y: -0.37 * size)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Surah \(surah?.transliteration ?? "")")
    }
}
