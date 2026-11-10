import SwiftUI

/// Move through the whole mushaf with one drag: a track from page 1 on the
/// right (where a mushaf opens) to page 604 on the left, marked with each juz.
/// The page changes when you let go.
struct MushafScrubber: View {
    let page: Int
    let colors: MushafColors
    let onCommit: (Int) -> Void

    @State private var store = QuranStore.shared
    @State private var dragged: Int?

    private static let knob: CGFloat = 18

    var body: some View {
        let shown = dragged ?? page
        let label = Color(colors.label)
        VStack(spacing: 6) {
            Text(title(for: shown))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(label)
                .contentTransition(.numericText(value: Double(shown)))
            GeometryReader { geo in
                let width = geo.size.width
                let midY = geo.size.height / 2 - 6
                ZStack {
                    Capsule()
                        .fill(label.opacity(0.18))
                        .frame(height: 4)
                        .position(x: width / 2, y: midY)
                    ForEach(Array(store.juzStarts.enumerated()), id: \.offset) { index, start in
                        let x = position(of: store.page(containing: start), in: width)
                        let labelled = index == 0 || (index + 1).isMultiple(of: 5)
                        Rectangle()
                            .fill(label.opacity(labelled ? 0.6 : 0.3))
                            .frame(width: 1, height: labelled ? 12 : 7)
                            .position(x: x, y: midY)
                        if labelled {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(label.opacity(0.7))
                                .position(x: x, y: midY + 17)
                        }
                    }
                    Circle()
                        .fill(Color(colors.marker))
                        .frame(width: Self.knob, height: Self.knob)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .position(x: position(of: shown, in: width), y: midY)
                }
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in dragged = page(at: value.location.x, in: width) }
                        .onEnded { value in
                            onCommit(page(at: value.location.x, in: width))
                            dragged = nil
                        }
                )
            }
            .frame(height: 44)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 12)
        .haptic(.selection, trigger: dragged.map { store.juz(containing: firstVerse(on: $0)) })
        .accessibilityElement()
        .accessibilityLabel("Page")
        .accessibilityValue(title(for: shown))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: MushafBook.page(after: page).map(onCommit)
            case .decrement: MushafBook.page(before: page).map(onCommit)
            @unknown default: break
            }
        }
    }

    /// "Page 245 · Juz 13 · Al-Isra"
    private func title(for page: Int) -> String {
        let first = firstVerse(on: page)
        let surah = store.surah(first.surah)?.transliteration ?? ""
        return "Page \(page) · Juz \(store.juz(containing: first)) · \(surah)"
    }

    private func firstVerse(on page: Int) -> VerseReference {
        store.verses(onPage: page).first?.hafsReference ?? VerseReference(surah: 1, verse: 1)
    }

    /// Page 1 sits at the right end of the track.
    private func position(of page: Int, in width: CGFloat) -> CGFloat {
        let inset = Self.knob / 2
        let share = CGFloat(page - 1) / CGFloat(MushafBook.pageCount - 1)
        return width - inset - share * (width - inset * 2)
    }

    private func page(at x: CGFloat, in width: CGFloat) -> Int {
        let inset = Self.knob / 2
        let share = (width - inset - x) / max(width - inset * 2, 1)
        let page = Int((share * CGFloat(MushafBook.pageCount - 1)).rounded()) + 1
        return min(max(page, 1), MushafBook.pageCount)
    }
}
