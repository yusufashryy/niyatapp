import SwiftUI
import UIKit

/// Everything the reader can adjust about the mushaf pages.
struct MushafOptions: Codable, Equatable {
    enum TapAction: String, Codable, CaseIterable, Identifiable {
        case actions, play
        var id: String { rawValue }
        var title: String { self == .actions ? "Show verse options" : "Play recitation" }
    }

    var style = MushafStyle.cream
    var tapAction = TapAction.actions
    var showTranslation = true
    var followRecitation = true
    var keepScreenOn = false

    // v3: rebuilt on the 15-line Madinah layout, cream paper by default.
    private static let key = "quran.mushafOptions.v3"

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
        tapAction = value(.tapAction, d.tapAction)
        showTranslation = value(.showTranslation, d.showTranslation)
        followRecitation = value(.followRecitation, d.followRecitation)
        keepScreenOn = value(.keepScreenOn, d.keepScreenOn)
    }
}

/// Paper colours. These are deliberately fixed (except Night, which follows
/// the app theme): they recreate a printed page rather than the app's look.
enum MushafStyle: String, Codable, CaseIterable, Identifiable {
    case cream, white, sepia, night, black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cream: "Cream"
        case .white: "White"
        case .sepia: "Sepia"
        case .night: "Night"
        case .black: "Black"
        }
    }

    /// Light paper: dark ink, and light-page tajweed colours.
    var isLight: Bool { self == .cream || self == .white || self == .sepia }

    @MainActor
    var colors: MushafColors {
        switch self {
        case .cream:
            MushafColors(paper: .rgb(0.988, 0.969, 0.918), ink: .rgb(0.10, 0.09, 0.07),
                         marker: .rgb(0.55, 0.40, 0.13), frame: .rgb(0.71, 0.56, 0.25), frameFill: .rgb(0.96, 0.92, 0.80),
                         ornament: .rgb(0.25, 0.44, 0.36), label: .rgb(0.36, 0.30, 0.20),
                         band: .rgb(0.99, 0.90, 0.55, 0.55), isLight: true)
        case .white:
            MushafColors(paper: .rgb(1, 1, 1), ink: .rgb(0.05, 0.05, 0.05),
                         marker: .rgb(0.45, 0.35, 0.12), frame: .rgb(0.66, 0.54, 0.28), frameFill: .rgb(0.97, 0.96, 0.92),
                         ornament: .rgb(0.20, 0.42, 0.36), label: .rgb(0.30, 0.30, 0.30),
                         band: .rgb(1.0, 0.92, 0.55, 0.5), isLight: true)
        case .sepia:
            MushafColors(paper: .rgb(0.95, 0.90, 0.79), ink: .rgb(0.18, 0.12, 0.06),
                         marker: .rgb(0.48, 0.31, 0.11), frame: .rgb(0.60, 0.43, 0.20), frameFill: .rgb(0.91, 0.84, 0.69),
                         ornament: .rgb(0.33, 0.42, 0.28), label: .rgb(0.36, 0.25, 0.13),
                         band: .rgb(0.97, 0.84, 0.48, 0.5), isLight: true)
        case .night:
            MushafColors(paper: UIColor(Palette.base.mix(with: .white, by: 0.05)), ink: .rgb(0.96, 0.96, 0.94),
                         marker: UIColor(Palette.highlight), frame: UIColor(Palette.highlight),
                         frameFill: UIColor(Palette.base.mix(with: .white, by: 0.1)),
                         ornament: UIColor(Palette.accent), label: UIColor(Palette.highlight),
                         band: UIColor(Palette.glow.opacity(0.45)), isLight: false)
        case .black:
            // Black for OLED screens: white text, gold ornaments.
            MushafColors(paper: .rgb(0, 0, 0), ink: .rgb(0.96, 0.96, 0.94),
                         marker: .rgb(0.85, 0.68, 0.30), frame: .rgb(0.85, 0.68, 0.30), frameFill: .rgb(0.08, 0.07, 0.05),
                         ornament: .rgb(0.55, 0.72, 0.60), label: .rgb(0.85, 0.80, 0.70),
                         band: .rgb(0.85, 0.68, 0.30, 0.22), isLight: false)
        }
    }
}

struct MushafColors {
    let paper: UIColor
    let ink: UIColor
    /// Ayah-end markers.
    let marker: UIColor
    /// Frame lines around surah titles.
    let frame: UIColor
    let frameFill: UIColor
    /// Small ornaments (stars) in the surah frames.
    let ornament: UIColor
    /// Surah, part and page labels.
    let label: UIColor
    /// Behind the ayah being recited or selected.
    let band: UIColor
    let isLight: Bool

    /// Text style for a page at a size.
    func textStyle(size: CGFloat, tajweed: Bool, highContrast: Bool) -> QuranTextStyle {
        var style = QuranTextStyle()
        style.fontSize = size
        style.ink = ink
        style.marker = marker
        style.tajweed = tajweed
        style.dark = !isLight
        style.highContrast = highContrast
        style.band = band
        style.currentWord = isLight ? UIColor(white: 0, alpha: 0.10) : UIColor(white: 1, alpha: 0.16)
        style.placeholder = isLight ? ink.withAlphaComponent(0.10) : ink.withAlphaComponent(0.14)
        style.uncertain = isLight ? UIColor(white: 0.45, alpha: 0.9) : UIColor(white: 0.65, alpha: 0.9)
        style.mistake = isLight ? UIColor(red: 0.85, green: 0.38, blue: 0.05, alpha: 1)
                                : UIColor(red: 0.98, green: 0.58, blue: 0.22, alpha: 1)
        // Words may be squeezed or stretched a little to fill each line, as in print.
        style.stretch = 0.9...1.1
        return style
    }
}

private extension UIColor {
    static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
