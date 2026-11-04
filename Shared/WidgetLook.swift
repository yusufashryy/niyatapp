import SwiftUI

/// How a widget is drawn: plain (the default) or on Niyat's painted theme.
///
/// Plain asks for no background. On the Default Home Screen look iOS fills
/// it with its own (white, or black in dark mode; no app can be see-through
/// there), and in the Clear and Tinted looks, StandBy and on the Lock Screen
/// iOS shows the wallpaper through glass and tints the content itself. So the
/// theme's artwork only ever shows in full colour.
struct WidgetLook: Equatable {
    enum Style: String, Codable, CaseIterable {
        case minimal
        case theme
        static let `default` = Style.minimal
    }

    let style: Style
    /// Drawn in its own colours (not tinted, not on the Lock Screen).
    let isFullColor: Bool

    /// The painted background and decorations.
    var showsArtwork: Bool { style == .theme && isFullColor }

    /// Asks for no background of its own (iOS decides what shows behind).
    var isTransparent: Bool { !showsArtwork }

    /// The theme's backgrounds are dark, so text on them stays light;
    /// otherwise text follows the phone's light or dark appearance.
    var colorScheme: ColorScheme? { showsArtwork ? .dark : nil }

    /// Highlighted words and marks (the next prayer, a finished goal).
    var accent: Color { Palette.highlight }
    /// Rings and fills that sit behind the highlight.
    var secondaryAccent: Color { Palette.accent }
    /// What a hole in the artwork (an empty dot) is filled with.
    var surface: Color { showsArtwork ? Palette.base : .primary.opacity(0.12) }
}
