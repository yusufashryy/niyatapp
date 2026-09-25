import SwiftUI

// Islamic geometric art, drawn in code so it's sharp at any size and takes the
// theme's colours.

/// The 8-pointed star (Rub el Hizb, ۞): two squares, one turned 45°.
struct EightPointStar: Shape {
    /// 1 = sharp points; smaller values make a rounder star.
    var innerRatio: CGFloat = 0.765

    func path(in rect: CGRect) -> Path {
        Self.path(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                  innerRatio: innerRatio)
    }

    static func path(center: CGPoint, radius: CGFloat, innerRatio: CGFloat = 0.765, rotation: Double = 0) -> Path {
        var path = Path()
        for i in 0..<16 {
            let angle = (Double(i) * .pi / 8) - .pi / 2 + rotation
            let r = i.isMultiple(of: 2) ? radius : radius * innerRatio
            let point = CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// A repeating star-and-cross lattice, the kind found on mosque tiles and screens.
struct IslamicPattern: View {
    var tile: CGFloat = 64
    var lineWidth: CGFloat = 1
    var color: Color

    var body: some View {
        Canvas { context, size in
            let starRadius = tile * 0.40
            let innerRadius = tile * 0.20
            let cols = Int(size.width / tile) + 2
            let rows = Int(size.height / tile) + 2
            var path = Path()
            for row in -1..<rows {
                for col in -1..<cols {
                    let center = CGPoint(x: CGFloat(col) * tile + tile / 2, y: CGFloat(row) * tile + tile / 2)
                    path.addPath(EightPointStar.path(center: center, radius: starRadius))
                    path.addPath(EightPointStar.path(center: center, radius: innerRadius, innerRatio: 0.7, rotation: .pi / 8))
                    // Bridges from each star's side points to its neighbours'.
                    path.move(to: CGPoint(x: center.x + starRadius, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + tile - starRadius, y: center.y))
                    path.move(to: CGPoint(x: center.x, y: center.y + starRadius))
                    path.addLine(to: CGPoint(x: center.x, y: center.y + tile - starRadius))
                    // Small diamond where four tiles meet.
                    let corner = CGPoint(x: CGFloat(col) * tile, y: CGFloat(row) * tile)
                    let d = tile * 0.1
                    path.move(to: CGPoint(x: corner.x, y: corner.y - d))
                    path.addLine(to: CGPoint(x: corner.x + d, y: corner.y))
                    path.addLine(to: CGPoint(x: corner.x, y: corner.y + d))
                    path.addLine(to: CGPoint(x: corner.x - d, y: corner.y))
                    path.closeSubpath()
                }
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A single ornamental rosette: layered stars, used as a centrepiece.
struct Rosette: View {
    var color: Color
    var lineWidth: CGFloat = 1.2

    var body: some View {
        ZStack {
            EightPointStar().stroke(color, lineWidth: lineWidth)
            EightPointStar().stroke(color.opacity(0.6), lineWidth: lineWidth).rotationEffect(.degrees(22.5)).scaleEffect(0.82)
            EightPointStar(innerRatio: 0.7).stroke(color.opacity(0.8), lineWidth: lineWidth).scaleEffect(0.5)
            Circle().stroke(color.opacity(0.35), lineWidth: lineWidth).scaleEffect(0.62)
            Circle().stroke(color.opacity(0.25), lineWidth: lineWidth)
        }
        .accessibilityHidden(true)
    }
}

/// A thin divider with a small star in the middle.
struct OrnamentDivider: View {
    var color: Color = Palette.highlight

    var body: some View {
        HStack(spacing: 10) {
            LinearGradient(colors: [.clear, color.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
            EightPointStar().fill(color).frame(width: 10, height: 10)
            LinearGradient(colors: [color.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Sky scenes for each prayer

extension PrayerName {
    /// Top-to-bottom sky colours at this time of day.
    var skyColors: [Color] {
        func c(_ hex: UInt32) -> Color { ThemeColor(hex: hex).color }
        switch self {
        case .fajr: return [c(0x1E1B4B), c(0x5B21B6), c(0xDB7093)]
        case .sunrise: return [c(0x1E3A8A), c(0xEA580C), c(0xFDE68A)]
        case .dhuhr: return [c(0x075985), c(0x0EA5E9), c(0x7DD3FC)]
        case .asr: return [c(0x1E3A8A), c(0xD97706), c(0xFBBF24)]
        case .maghrib: return [c(0x312E81), c(0xB91C1C), c(0xF97316)]
        case .isha: return [c(0x020617), c(0x0B1437), c(0x1E3A8A)]
        }
    }

    var showsStars: Bool { self == .isha || self == .fajr }
    var showsMoon: Bool { self == .isha }
}

/// A painted sky for a prayer: gradient, sun or moon, and stars at night.
struct PrayerSky: View {
    let prayer: PrayerName

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                LinearGradient(colors: prayer.skyColors, startPoint: .top, endPoint: .bottom)

                if prayer.showsStars {
                    Canvas { context, canvasSize in
                        // Fixed pseudo-random stars so they don't jump around between renders.
                        var seed: UInt64 = 0x9E3779B97F4A7C15 &+ UInt64(prayer.rawValue.count)
                        func next() -> CGFloat {
                            seed = seed &* 6364136223846793005 &+ 1442695040888963407
                            return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
                        }
                        for _ in 0..<40 {
                            let point = CGPoint(x: next() * canvasSize.width, y: next() * canvasSize.height * 0.7)
                            let r = 0.4 + next() * 1.1
                            context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: r * 2, height: r * 2)),
                                         with: .color(.white.opacity(0.35 + next() * 0.5)))
                        }
                    }
                }

                celestialBody(size: size)

                // Soft haze at the horizon.
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            }
        }
        .accessibilityHidden(true)
    }

    /// How far down the card the sun sits (0 = top, 1 = bottom).
    private var sunHeight: CGFloat {
        switch prayer {
        case .dhuhr: 0.22
        case .asr: 0.55
        case .sunrise, .maghrib: 0.92
        default: 0.5
        }
    }

    @ViewBuilder
    private func celestialBody(size: CGSize) -> some View {
        let d = min(size.width, size.height) * 0.32
        switch prayer {
        case .isha:
            Image(systemName: "moon.fill")
                .font(.system(size: d * 0.8))
                .foregroundStyle(Color(white: 0.95))
                .shadow(color: .white.opacity(0.6), radius: 12)
                .position(x: size.width * 0.78, y: size.height * 0.28)
        case .fajr:
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: d * 0.5, height: d * 0.5)
                .blur(radius: 6)
                .position(x: size.width * 0.5, y: size.height * 1.02)
        default:
            let y = sunHeight
            Circle()
                .fill(RadialGradient(colors: [.white, Color(white: 1, opacity: 0.9), .white.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: d * 0.6))
                .frame(width: d * 1.2, height: d * 1.2)
                .shadow(color: .yellow.opacity(0.5), radius: 20)
                .position(x: size.width * (prayer == .dhuhr ? 0.78 : 0.7), y: size.height * y)
        }
    }
}
