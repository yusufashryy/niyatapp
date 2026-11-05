import CoreText
import SwiftUI

/// Where the parts of a surah heading go, for a heading of a given size, in the
/// manner of the printed Madinah mushaf: a long cartouche for the name in the
/// middle, a medallion on each side, interlaced arabesque all round. Niyat's
/// own layout, not a copy of any printed heading. Pure geometry, so it's tested.
struct SurahFrameGeometry {
    let bounds: CGRect

    init(size: CGSize) {
        bounds = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
    }

    var height: CGFloat { bounds.height }
    var midY: CGFloat { bounds.midY }

    /// Inside the double rule, where the arabesque goes.
    var field: CGRect { bounds.insetBy(dx: height * 0.1, dy: height * 0.1) }

    /// The name's cartouche (its pointed tips reach `tip` beyond each side).
    var cartouche: CGRect {
        let width = bounds.width * 0.46
        let h = height * 0.7
        return CGRect(x: bounds.midX - width / 2, y: midY - h / 2, width: width, height: h)
    }
    var tip: CGFloat { height * 0.16 }

    /// The name's box, clear of the cartouche's rounded ends and inner frame.
    var nameBox: CGRect { cartouche.insetBy(dx: cartouche.height * 0.62, dy: cartouche.height * 0.1) }

    /// Room on each side between the cartouche's tip and the field's edge.
    private var sideRoom: CGFloat { field.width / 2 - cartouche.width / 2 - tip }

    /// Medallion radius: as large as fits between the cartouche and the edge.
    var medallionRadius: CGFloat { max(0, min(height * 0.4, sideRoom * 0.3)) }

    /// Medallion centres, right then left (reading order): the right one holds
    /// the surah's number, the left one its count of ayat.
    var medallions: [CGPoint] {
        let offset = cartouche.width / 2 + tip + sideRoom * 0.42
        return [CGPoint(x: bounds.midX + offset, y: midY), CGPoint(x: bounds.midX - offset, y: midY)]
    }

    /// Where to start drawing a line of text so its ink (not its line box)
    /// sits in the middle of `box`. `ink` is the glyphs' bounds relative to
    /// the text's origin on the baseline, y up (CoreText's coordinates).
    /// The result is in y-down coordinates.
    static func centredOrigin(ink: CGRect, in box: CGRect) -> CGPoint {
        CGPoint(x: box.midX - ink.midX, y: box.midY + ink.midY)
    }

    /// Text size that fits `ink` (measured at `size`) inside `box`.
    static func fittingSize(_ size: CGFloat, ink: CGRect, in box: CGRect) -> CGFloat {
        guard ink.width > 0, ink.height > 0 else { return size }
        return size * min(1, box.width / ink.width, box.height / ink.height)
    }
}

/// A surah's heading in the mushaf: the gilded band (`SurahFrameArt`), the
/// title with its harakat in the cartouche, and the surah's number and count of
/// ayat in the medallions, each centred on its ink.
struct SurahFrame: View {
    let surah: Surah?
    let colors: MushafColors
    let fontSize: CGFloat

    private static let font = QuranTypeface.oldMadina.rawValue

    var body: some View {
        Canvas { context, size in
            let g = SurahFrameGeometry(size: size)
            SurahFrameArt(geometry: g, gold: Color(colors.frame), fill: Color(colors.frameFill), paper: Color(colors.paper))
                .draw(in: &context)
            let ink = colors.label
            Self.drawCentred(SurahTitles.title(for: surah), size: fontSize * 1.1, color: ink, in: g.nameBox, context: &context)
            guard let surah, g.medallionRadius > 6 else { return }
            let labels = [("ترتيبها", surah.id), ("آياتها", surah.totalVerses)]
            for (centre, label) in zip(g.medallions, labels) {
                let r = g.medallionRadius * 0.66
                Self.drawCentred(label.0, size: r * 0.8, color: ink,
                                 in: CGRect(x: centre.x - r, y: centre.y - r * 0.92, width: r * 2, height: r * 0.8), context: &context)
                Self.drawCentred(QuranTextCanvas.arabicDigits(label.1), size: r * 1.2, color: ink,
                                 in: CGRect(x: centre.x - r * 0.9, y: centre.y + r * 0.04, width: r * 1.8, height: r * 0.85), context: &context)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(surah.map { "Surah \($0.transliteration), \($0.totalVerses) ayat" } ?? "")
    }

    /// Draws one line of text, shrunk to fit if need be, with its ink centred in `box`.
    private static func drawCentred(_ text: String, size: CGFloat, color: UIColor, in box: CGRect,
                                    context: inout GraphicsContext) {
        guard !text.isEmpty else { return }
        let measured = line(text, size: size, color: color)
        let fitted = SurahFrameGeometry.fittingSize(size, ink: measured.ink, in: box)
        let final = fitted == size ? measured : line(text, size: fitted, color: color)
        let origin = SurahFrameGeometry.centredOrigin(ink: final.ink, in: box)
        context.withCGContext { cg in
            cg.saveGState()
            cg.textMatrix = .identity
            cg.translateBy(x: origin.x, y: origin.y)
            cg.scaleBy(x: 1, y: -1)
            cg.textPosition = .zero
            CTLineDraw(final.line, cg)
            cg.restoreGState()
        }
    }

    private static func line(_ text: String, size: CGFloat, color: UIColor) -> (line: CTLine, ink: CGRect) {
        let ctFont = CTFontCreateWithName(font as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: ctFont, .foregroundColor: color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        return (line, CTLineGetBoundsWithOptions(line, .useGlyphPathBounds))
    }
}
