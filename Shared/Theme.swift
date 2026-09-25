import SwiftUI

/// Niyat's colours. Dark-first and high contrast: near-black ink, a bright
/// emerald accent and warm gold highlights.
enum Palette {
    /// App background, almost black with a hint of blue.
    static let ink = Color(red: 0.016, green: 0.024, blue: 0.035)
    /// Deep green used in the ambient background glow.
    static let deepEmerald = Color(red: 0.012, green: 0.200, blue: 0.157)
    /// Deep navy used in the ambient background glow.
    static let night = Color(red: 0.027, green: 0.055, blue: 0.137)
    /// Primary accent. Bright enough to read on black.
    static let emerald = Color(red: 0.227, green: 0.878, blue: 0.639)
    /// Secondary accent for highlights (next prayer, Kaaba, streaks).
    static let gold = Color(red: 0.973, green: 0.792, blue: 0.345)
    /// Hairline borders on dark surfaces.
    static let hairline = Color.white.opacity(0.10)
}

extension Font {
    /// Amiri Quran (SIL Open Font License), bundled with the app and widgets.
    static func quran(size: CGFloat) -> Font { .custom("AmiriQuran-Regular", size: size) }

    /// Big rounded numerals for times and counters.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}

/// Slowly drifting emerald/navy glow behind every screen. The Liquid Glass
/// elements on top pick up its colour.
struct AmbientBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate)
            let drift = reduceMotion ? 0 : sin(t / 7) * 0.08
            let drift2 = reduceMotion ? 0 : cos(t / 9) * 0.08
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + drift, 0.45 + drift2], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    Palette.deepEmerald, Palette.ink, Palette.night,
                    Palette.ink, Palette.deepEmerald.opacity(0.55), Palette.ink,
                    Palette.night, Palette.ink, Palette.deepEmerald.opacity(0.7),
                ]
            )
        }
        .background(Palette.ink)
        .ignoresSafeArea()
    }
}

extension View {
    /// Puts the ambient background behind a screen.
    func niyatBackground() -> some View {
        background { AmbientBackground() }
    }

    /// Liquid Glass panel. Use for things that float above content: hero
    /// cards, controls, the current prayer.
    func glassPanel(cornerRadius: CGFloat = 28, tint: Color? = nil, interactive: Bool = false) -> some View {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    /// Quiet dark surface for regular content (list rows, verses), so the
    /// glass elements stand out.
    func surface(cornerRadius: CGFloat = 22) -> some View {
        background(Color.white.opacity(0.055), in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
    }

    /// Small all-caps label above a section.
    func sectionLabelStyle() -> some View {
        font(.caption.weight(.bold))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// Widget background: same palette as the app, without animation.
struct WidgetBackground: View {
    var body: some View {
        ZStack {
            Palette.ink
            RadialGradient(colors: [Palette.deepEmerald, .clear], center: .topLeading, startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Palette.night, .clear], center: .bottomTrailing, startRadius: 0, endRadius: 220)
        }
    }
}
