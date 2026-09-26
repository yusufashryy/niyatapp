import Foundation
import Observation
import SwiftUI
import UIKit

/// A colour stored as plain numbers so it can be saved and shared with widgets.
struct ThemeColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: min(max(Double(r), 0), 1), green: min(max(Double(g), 0), 1), blue: min(max(Double(b), 0), 1))
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    // MARK: Hue / saturation / brightness, used to build a full theme from one colour.

    var hsb: (h: Double, s: Double, b: Double) {
        let maxV = max(red, green, blue), minV = min(red, green, blue)
        let delta = maxV - minV
        var hue = 0.0
        if delta > 0 {
            if maxV == red { hue = (green - blue) / delta }
            else if maxV == green { hue = 2 + (blue - red) / delta }
            else { hue = 4 + (red - green) / delta }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxV == 0 ? 0 : delta / maxV, maxV)
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue - floor(hue)) * 6, s = min(max(saturation, 0), 1), v = min(max(brightness, 0), 1)
        let i = Int(h) % 6, f = h - floor(h)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: self.init(red: v, green: t, blue: p)
        case 1: self.init(red: q, green: v, blue: p)
        case 2: self.init(red: p, green: v, blue: t)
        case 3: self.init(red: p, green: q, blue: v)
        case 4: self.init(red: t, green: p, blue: v)
        default: self.init(red: v, green: p, blue: q)
        }
    }

    func with(hueShift: Double = 0, saturation: Double? = nil, brightness: Double) -> ThemeColor {
        let (h, s, _) = hsb
        return ThemeColor(hue: h + hueShift, saturation: saturation ?? s, brightness: brightness)
    }
}

/// A colour scheme for the whole app (and widgets).
struct AppTheme: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    /// Screen background, nearly black.
    var base: ThemeColor
    /// Main glow in the ambient background.
    var glow: ThemeColor
    /// Second glow in the ambient background.
    var glow2: ThemeColor
    /// Buttons, icons, selected things.
    var accent: ThemeColor
    /// Warm highlight: next prayer, Arabic headings, streaks.
    var highlight: ThemeColor

    static let midnight = AppTheme(id: "midnight", name: "Midnight",
                                   base: .init(hex: 0x030712), glow: .init(hex: 0x0B2D63), glow2: .init(hex: 0x081A40),
                                   accent: .init(hex: 0x38BDF8), highlight: .init(hex: 0xFBBF24))
    static let emerald = AppTheme(id: "emerald", name: "Emerald",
                                  base: .init(hex: 0x040609), glow: .init(hex: 0x03332B), glow2: .init(hex: 0x070E23),
                                  accent: .init(hex: 0x3AE0A3), highlight: .init(hex: 0xF8CA58))
    static let desert = AppTheme(id: "desert", name: "Desert",
                                 base: .init(hex: 0x0B0704), glow: .init(hex: 0x4A260A), glow2: .init(hex: 0x2A0F1F),
                                 accent: .init(hex: 0xF59E0B), highlight: .init(hex: 0xFDE68A))
    static let amethyst = AppTheme(id: "amethyst", name: "Amethyst",
                                   base: .init(hex: 0x07040F), glow: .init(hex: 0x2E1065), glow2: .init(hex: 0x0F1A45),
                                   accent: .init(hex: 0xA78BFA), highlight: .init(hex: 0xF9A8D4))
    static let maghrib = AppTheme(id: "maghrib", name: "Maghrib",
                                  base: .init(hex: 0x0C0507), glow: .init(hex: 0x4C0F1F), glow2: .init(hex: 0x1E0B33),
                                  accent: .init(hex: 0xFB7185), highlight: .init(hex: 0xFDBA74))
    static let onyx = AppTheme(id: "onyx", name: "Onyx",
                               base: .init(hex: 0x000000), glow: .init(hex: 0x1C1C1E), glow2: .init(hex: 0x0E0E10),
                               accent: .init(hex: 0xF5F5F5), highlight: .init(hex: 0xD4AF37))

    static let presets: [AppTheme] = [.onyx, .midnight, .emerald, .desert, .amethyst, .maghrib]

    /// Builds a full theme from the two colours the user picks.
    static func custom(accent: ThemeColor, highlight: ThemeColor) -> AppTheme {
        let saturation = accent.hsb.s
        return AppTheme(id: "custom", name: "Custom",
                        base: accent.with(saturation: saturation * 0.6, brightness: 0.05),
                        glow: accent.with(saturation: min(saturation, 0.9), brightness: 0.34),
                        glow2: accent.with(hueShift: 0.08, saturation: min(saturation, 0.8), brightness: 0.2),
                        accent: accent,
                        highlight: highlight)
    }
}

/// The current theme. Views that read `Palette` colours update automatically
/// when it changes, because this class is @Observable.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private(set) var theme: AppTheme = .onyx
    private(set) var selectedID: String = AppTheme.onyx.id
    private(set) var customAccent: ThemeColor = AppTheme.midnight.accent
    private(set) var customHighlight: ThemeColor = AppTheme.midnight.highlight

    private enum Key {
        static let selected = "theme.selected"
        static let customAccent = "theme.customAccent"
        static let customHighlight = "theme.customHighlight"
    }

    private init() { reload() }

    /// Re-reads the saved theme (widgets call this, since the app may have changed it).
    func reload() {
        let defaults = AppGroup.defaults
        selectedID = defaults.string(forKey: Key.selected) ?? AppTheme.onyx.id
        customAccent = defaults.decoded(ThemeColor.self, forKey: Key.customAccent) ?? AppTheme.midnight.accent
        customHighlight = defaults.decoded(ThemeColor.self, forKey: Key.customHighlight) ?? AppTheme.midnight.highlight
        recompute()
    }

    func select(_ id: String) {
        selectedID = id
        AppGroup.defaults.set(id, forKey: Key.selected)
        recompute()
    }

    func setCustom(accent: ThemeColor, highlight: ThemeColor) {
        customAccent = accent
        customHighlight = highlight
        AppGroup.defaults.setEncoded(accent, forKey: Key.customAccent)
        AppGroup.defaults.setEncoded(highlight, forKey: Key.customHighlight)
        select("custom")
    }

    private func recompute() {
        let newTheme = selectedID == "custom"
            ? AppTheme.custom(accent: customAccent, highlight: customHighlight)
            : AppTheme.presets.first { $0.id == selectedID } ?? .onyx
        if newTheme != theme { theme = newTheme }
    }
}
