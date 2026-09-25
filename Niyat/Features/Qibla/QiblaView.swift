import CoreLocation
import SwiftUI

struct QiblaView: View {
    @Environment(AppModel.self) private var model
    @State private var compass = CompassModel()
    @State private var showTips = false

    var body: some View {
        NavigationStack {
            Group {
                if let location = currentLocation {
                    content(location: location)
                } else {
                    ContentUnavailableView("Set your location", systemImage: "location.slash",
                                           description: Text("Choose a location in Settings to find the Qibla."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .niyatBackground()
            .navigationTitle("Qibla")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { compass.start() }
        .onDisappear { compass.stop() }
    }

    /// Live GPS position when available (so it's right when you travel), otherwise the saved city.
    private var currentLocation: SavedLocation? {
        if let live = compass.liveLocation {
            return SavedLocation(latitude: live.coordinate.latitude, longitude: live.coordinate.longitude,
                                 name: "Your location", timeZoneIdentifier: TimeZone.current.identifier)
        }
        return model.location
    }

    private func content(location: SavedLocation) -> some View {
        let qibla = PrayerCalculator.qiblaDirection(from: location)
        let heading = compass.heading
        // Positive = turn right (clockwise).
        let turn = heading.map { CompassModel.signedDelta(from: $0, to: qibla) }
        let aligned = turn.map { abs($0) <= 3 } ?? false

        return ScrollView {
            VStack(spacing: 24) {
                instruction(turn: turn, aligned: aligned, qibla: qibla)
                    .padding(.top, 8)
                    .zIndex(1)

                QiblaDial(qibla: qibla, continuousHeading: compass.continuousHeading, turn: turn, aligned: aligned)
                    .frame(width: 310, height: 310)
                    .padding(.top, 20)
                    .haptic(.success, trigger: aligned) { _, now in now }
                    .haptic(.selection, trigger: tickBucket(turn))

                infoRow(location: location, qibla: qibla)

                tipsCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .animation(.smooth(duration: 0.4), value: aligned)
    }

    /// Changes every 5° within 30° of the Qibla, for gentle haptic ticks as you turn.
    private func tickBucket(_ turn: Double?) -> Int {
        guard let turn, abs(turn) < 30 else { return 999 }
        return Int((turn / 5).rounded())
    }

    @ViewBuilder
    private func instruction(turn: Double?, aligned: Bool, qibla: Double) -> some View {
        VStack(spacing: 6) {
            if aligned {
                Label("Facing the Qibla", systemImage: "checkmark.seal.fill")
                    .font(.display(30, weight: .heavy))
                    .foregroundStyle(Palette.highlight)
                    .transition(.scale.combined(with: .opacity))
                Text("الْقِبْلَة")
                    .font(.calligraphy(size: 30))
                    .foregroundStyle(Palette.highlight.opacity(0.8))
            } else if let turn {
                HStack(spacing: 10) {
                    Image(systemName: turn > 0 ? "arrow.turn.up.right" : "arrow.turn.up.left")
                    Text("Turn \(turn > 0 ? "right" : "left")")
                }
                .font(.display(30, weight: .heavy))
                Text("\(Int(abs(turn).rounded()))°")
                    .font(.display(22, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .contentTransition(.numericText(value: abs(turn)))
            } else {
                Text("Face \(Int(qibla.rounded()))° from north")
                    .font(.display(28, weight: .heavy))
                Text("This device has no compass. Use a compass app or a landmark to face this direction.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(minHeight: 96)
    }

    private func infoRow(location: SavedLocation, qibla: Double) -> some View {
        let distance = Measurement(value: QiblaMath.distance(latitude: location.latitude, longitude: location.longitude),
                                   unit: UnitLength.meters)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                infoPill(title: "\(String(format: "%.1f", qibla))°", subtitle: "from true north", systemImage: "location.north.line.fill")
                infoPill(title: distance.formatted(.measurement(width: .abbreviated, usage: .road)),
                         subtitle: "to the Kaaba", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
            }
            HStack(spacing: 10) {
                if compass.isAvailable {
                    infoPill(title: compass.usesTrueNorth ? "True north" : "Magnetic north",
                             subtitle: compass.usesTrueNorth ? "corrected for your location" : "allow location for best accuracy",
                             systemImage: compass.usesTrueNorth ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             tint: compass.usesTrueNorth ? Palette.accent : .orange)
                    infoPill(title: compass.accuracy.map { $0 >= 0 ? "±\(Int($0.rounded()))°" : "Unknown" } ?? "…",
                             subtitle: compass.needsCalibration ? "move in a figure-8" : "compass accuracy",
                             systemImage: "scope",
                             tint: compass.needsCalibration ? .orange : Palette.accent)
                }
            }
            Text(compass.liveLocation == nil ? "Using \(location.name)" : "Using your current GPS position")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func infoPill(title: String, subtitle: String, systemImage: String, tint: Color = Palette.highlight) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .surface(cornerRadius: 18)
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.smooth) { showTips.toggle() }
            } label: {
                HStack {
                    Label("For the most accurate reading", systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showTips ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.pressable)

            if showTips {
                VStack(alignment: .leading, spacing: 8) {
                    tip("Hold your phone flat, screen facing up.")
                    tip("Step away from metal, magnets, cars and laptops. They bend the compass.")
                    tip("If accuracy is poor, move your phone in a figure-8 a few times.")
                    tip("Allow location access so the compass uses true north. Magnetic north can be off by 10° or more in some places.")
                    tip("The Qibla is the great-circle direction to the Kaaba (21.4225° N, 39.8262° E), the same method used by mosques and Islamic authorities.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .surface(cornerRadius: 20)
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            EightPointStar().fill(Palette.highlight).frame(width: 8, height: 8).padding(.top, 4)
            Text(text)
        }
    }
}

/// The compass face. The ring turns with the phone so N always points north; the
/// Kaaba sits on the ring at the Qibla bearing. Line the Kaaba up with the marker
/// at the top and you're facing the Qibla.
private struct QiblaDial: View {
    let qibla: Double
    let continuousHeading: Double?
    let turn: Double?
    let aligned: Bool

    private let radius: CGFloat = 132

    var body: some View {
        let heading = continuousHeading ?? 0
        ZStack {
            // Glow when aligned, kept inside the dial so it never covers the text around it.
            Circle()
                .fill(RadialGradient(colors: [Palette.highlight.opacity(aligned ? 0.35 : 0), .clear],
                                     center: .center, startRadius: 10, endRadius: radius))
                .frame(width: radius * 2, height: radius * 2)
                .allowsHitTesting(false)

            // Rotating face: ticks and N/E/S/W.
            ZStack {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.tint(Palette.glow.opacity(0.25)), in: .circle)
                Rosette(color: Palette.accent.opacity(0.12), lineWidth: 1)
                    .padding(64)
                ForEach(0..<72, id: \.self) { tick in
                    let major = tick % 18 == 0
                    Capsule()
                        .fill(major ? Color.white : Color.white.opacity(tick % 6 == 0 ? 0.45 : 0.2))
                        .frame(width: major ? 3 : 1.5, height: major ? 14 : (tick % 6 == 0 ? 9 : 6))
                        .offset(y: -(radius + 8))
                        .rotationEffect(.degrees(Double(tick) * 5))
                }
                ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { index, letter in
                    Text(letter)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(letter == "N" ? Color.red : Color.white.opacity(0.8))
                        .rotationEffect(.degrees(-Double(index) * 90 + heading))
                        .offset(y: -(radius - 22))
                        .rotationEffect(.degrees(Double(index) * 90))
                }
            }
            .rotationEffect(.degrees(-heading))

            // How far to turn: an arc from the top marker to the Kaaba.
            if let turn, !aligned {
                Circle()
                    .trim(from: 0, to: min(abs(turn), 180) / 360)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2)
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(x: turn < 0 ? -1 : 1, y: 1)
                    .shadow(color: Palette.accent, radius: 8)
            }

            // The Kaaba on the ring, kept upright.
            KaabaMarker(highlighted: aligned)
                .rotationEffect(.degrees(-(qibla - heading)))
                .offset(y: -radius)
                .rotationEffect(.degrees(qibla - heading))

            // Fixed marker: the direction the top of your phone points.
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 22))
                .foregroundStyle(aligned ? Palette.highlight : .white)
                .offset(y: -(radius + 34))
                .shadow(color: aligned ? Palette.highlight : .clear, radius: 8)

            // Centre readout.
            VStack(spacing: 2) {
                Text("\(Int(qibla.rounded()))°")
                    .font(.display(34, weight: .heavy))
                Text("Qibla")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: heading)
        .animation(.smooth(duration: 0.4), value: aligned)
    }
}

/// A small drawing of the Kaaba: a black cube with its gold band (the Kiswah).
private struct KaabaMarker: View {
    let highlighted: Bool

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black)
                .overlay {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.highlight.opacity(0.8), lineWidth: 1)
                }
            Rectangle()
                .fill(Palette.highlight)
                .frame(height: 4)
                .padding(.top, 8)
        }
        .frame(width: 30, height: 32)
        .shadow(color: highlighted ? Palette.highlight : .black.opacity(0.5), radius: highlighted ? 14 : 4)
        .scaleEffect(highlighted ? 1.15 : 1)
        .accessibilityLabel("Kaaba")
    }
}
