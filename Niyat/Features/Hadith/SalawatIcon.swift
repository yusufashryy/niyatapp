import CoreText
import SwiftUI
import UIKit

/// The Hadith tab's icon: ﷺ (the salawat that follows the Prophet's name in
/// every hadith), drawn on the device in the system's Damascus font (Geeza Pro
/// if it's missing). Drawn at run time with the system's own font, as any text
/// is, so no font artwork is copied into the app.
enum SalawatIcon {
    /// Tried in order; all ship with iOS.
    static let fontNames = ["DamascusBold", "DamascusSemiBold", "Damascus", "GeezaPro-Bold", "GeezaPro"]
    static let character = "\u{FDFA}"
    /// Outline added around the letters, as a share of the icon's size.
    static let strokeShare: CGFloat = 0.012
    /// Empty space under the icon, as a share of its size.
    static let lift: CGFloat = 0.22

    /// The tab bar size, in points.
    @MainActor static let tab = image(size: 28)
    /// Bigger, for the how-to-use guide.
    @MainActor static let large = image(size: 46)

    /// ﷺ filling a square of `size` points, as a template image (it takes the
    /// colour of wherever it's shown). Nil only if no font on the device has the glyph.
    static func image(size: CGFloat) -> UIImage {
        // Clear space below lifts the letters away from the tab's label.
        let canvas = CGSize(width: size, height: size + size * lift)
        guard let path = glyphPath() else { return UIImage(systemName: "text.quote") ?? UIImage() }
        let bounds = path.boundingBoxOfPath
        // Thicker strokes so it weighs the same as the tab bar's other icons.
        let weight = size * strokeShare
        let scale = min((size - weight) / bounds.width, (size - weight) / bounds.height)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let image = renderer.image { context in
            let cg = context.cgContext
            // Glyph outlines point up; the image's y axis points down.
            cg.translateBy(x: canvas.width / 2, y: size / 2)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -bounds.midX, y: -bounds.midY)
            cg.addPath(path)
            cg.setFillColor(UIColor.black.cgColor)
            cg.fillPath()
            cg.addPath(path)
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(weight / scale)
            cg.setLineJoin(.round)
            cg.strokePath()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// The outline of ﷺ in the first font that has it.
    static func glyphPath() -> CGPath? {
        for name in fontNames {
            let font = CTFontCreateWithName(name as CFString, 100, nil)
            // CoreText falls back to another font for unknown names: only use the one asked for.
            guard (CTFontCopyPostScriptName(font) as String) == name else { continue }
            var characters = Array(character.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count), glyphs[0] != 0,
                  let path = CTFontCreatePathForGlyph(font, glyphs[0], nil), !path.isEmpty else { continue }
            return path
        }
        return nil
    }
}
