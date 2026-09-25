import SwiftUI

/// Niyat's colours, taken from the current theme (see ThemeStore.swift).
/// Dark-first and high contrast.
enum Palette {
    private static var theme: AppTheme { ThemeManager.shared.theme }

    /// App background, almost black.
    static var base: Color { theme.base.color }
    /// Main glow in the ambient background.
    static var glow: Color { theme.glow.color }
    /// Second glow in the ambient background.
    static var glow2: Color { theme.glow2.color }
    /// Primary accent: buttons, icons, selections.
    static var accent: Color { theme.accent.color }
    /// Warm highlight: next prayer, Arabic headings, streaks.
    static var highlight: Color { theme.highlight.color }
    /// Hairline borders on dark surfaces.
    static let hairline = Color.white.opacity(0.10)
}

extension Font {
    /// Amiri Quran (SIL Open Font License), bundled with the app and widgets.
    static func quran(size: CGFloat) -> Font { .custom("AmiriQuran-Regular", size: size) }

    /// Aref Ruqaa (SIL Open Font License): calligraphic Arabic for headings and art.
    static func calligraphy(size: CGFloat) -> Font { .custom("ArefRuqaa-Bold", size: size) }

    /// Big rounded numerals for times and counters.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}

/// Slowly drifting glow in the theme's colours, with faint arabesque patterns
/// at the edges, a turning rosette and calligraphy floating in the background.
/// The Liquid Glass elements on top pick up its colour.
struct AmbientBackground: View {
    var showsPattern = true
    var showsCalligraphy = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Dhikr phrases that float in the background, with where each one drifts.
    private static let phrases: [(text: String, x: CGFloat, y: CGFloat, size: CGFloat, phase: Double)] = [
        ("سُبْحَانَ ٱللَّٰهِ", 0.30, 0.16, 64, 0),
        ("ٱلْحَمْدُ لِلَّٰهِ", 0.72, 0.42, 58, 1.7),
        ("ٱللَّٰهُ أَكْبَرُ", 0.28, 0.68, 62, 3.1),
        ("لَا إِلَٰهَ إِلَّا ٱللَّٰهُ", 0.66, 0.90, 52, 4.4),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let t = Float(time)
            let drift = sin(t / 7) * 0.08
            let drift2 = cos(t / 9) * 0.08
            GeometryReader { geo in
                ZStack {
                    MeshGradient(
                        width: 3, height: 3,
                        points: [
                            [0, 0], [0.5, 0], [1, 0],
                            [0, 0.5], [0.5 + drift, 0.45 + drift2], [1, 0.5],
                            [0, 1], [0.5, 1], [1, 1],
                        ],
                        colors: [
                            Palette.glow, Palette.base, Palette.glow2,
                            Palette.base, Palette.glow.opacity(0.55), Palette.base,
                            Palette.glow2, Palette.base, Palette.glow.opacity(0.7),
                        ]
                    )

                    if showsCalligraphy {
                        Rosette(color: Palette.highlight.opacity(0.06), lineWidth: 1)
                            .frame(width: geo.size.width * 1.3, height: geo.size.width * 1.3)
                            .rotationEffect(.degrees(time.truncatingRemainder(dividingBy: 360) * 2))
                            .position(x: geo.size.width * 0.5, y: geo.size.height * 0.45)

                        ForEach(Array(Self.phrases.enumerated()), id: \.offset) { _, phrase in
                            let dx = CGFloat(sin(time / 11 + phrase.phase)) * 18
                            let dy = CGFloat(cos(time / 13 + phrase.phase)) * 14
                            Text(phrase.text)
                                .font(.calligraphy(size: phrase.size))
                                .foregroundStyle(Palette.highlight.opacity(0.07))
                                .fixedSize()
                                .rotationEffect(.degrees(sin(time / 17 + phrase.phase) * 4))
                                .position(x: geo.size.width * phrase.x + dx, y: geo.size.height * phrase.y + dy)
                        }
                    }
                }
            }
        }
        .overlay {
            if showsPattern {
                IslamicPattern(tile: 78, lineWidth: 0.8, color: Palette.accent.opacity(0.09))
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .clear, location: 0.28),
                            .init(color: .clear, location: 0.72),
                            .init(color: .black, location: 1),
                        ], startPoint: .leading, endPoint: .trailing)
                    }
            }
        }
        .background(Palette.base)
        .ignoresSafeArea()
        .accessibilityHidden(true)
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
            Palette.base
            RadialGradient(colors: [Palette.glow, .clear], center: .topLeading, startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Palette.glow2, .clear], center: .bottomTrailing, startRadius: 0, endRadius: 220)
            IslamicPattern(tile: 44, lineWidth: 0.6, color: Palette.accent.opacity(0.08))
        }
    }
}
