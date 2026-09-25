import CoreLocation
import SwiftUI

struct QiblaView: View {
    @Environment(AppModel.self) private var model
    @State private var compass = CompassModel()

    var body: some View {
        NavigationStack {
            Group {
                if let location = model.location {
                    content(location: location)
                } else {
                    ContentUnavailableView("Set your location", systemImage: "location.slash",
                                           description: Text("Choose a location in Settings to find the Qibla."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .niyatBackground()
            .navigationTitle("Qibla")
        }
        .onAppear { compass.start() }
        .onDisappear { compass.stop() }
    }

    private func content(location: SavedLocation) -> some View {
        let qibla = PrayerCalculator.qiblaDirection(from: location)
        let heading = compass.heading ?? 0
        // Angle of the Qibla relative to the top of the phone.
        let relative = normalized(qibla - heading)
        let isAligned = compass.heading != nil && (relative < 3 || relative > 357)
        let accent = isAligned ? Palette.gold : Palette.emerald

        return VStack(spacing: 28) {
            Spacer(minLength: 0)

            ZStack {
                // Dial turns so N always points north.
                CompassDial()
                    .rotationEffect(.degrees(-heading))

                // Pointer to the Kaaba.
                VStack(spacing: 0) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 30))
                    Capsule()
                        .frame(width: 5, height: 78)
                    Spacer().frame(height: 118)
                }
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.9), radius: 10)
                .rotationEffect(.degrees(relative))

                KaabaIcon(highlighted: isAligned)
            }
            .frame(width: 310, height: 310)
            .animation(.easeOut(duration: 0.25), value: heading)
            .sensoryFeedback(.success, trigger: isAligned) { _, aligned in aligned }

            VStack(spacing: 8) {
                if compass.heading == nil {
                    Text("\(Int(qibla.rounded()))° from north")
                        .font(.display(34))
                    Text("No compass on this device. Face \(Int(qibla.rounded()))° clockwise from north.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else if isAligned {
                    Text("Facing the Qibla")
                        .font(.display(30))
                        .foregroundStyle(Palette.gold)
                } else {
                    Text("Turn \(relative < 180 ? "right" : "left") \(Int((relative < 180 ? relative : 360 - relative).rounded()))°")
                        .font(.display(30))
                }
                Text("\(Int(qibla.rounded()))° · \(distanceToKaaba(from: location)) to Makkah")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                if compass.needsCalibration {
                    Label("Move your phone in a figure-8 to calibrate. Keep it away from metal and magnets.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .glassPanel(cornerRadius: 28)
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
    }

    private func normalized(_ angle: Double) -> Double {
        let value = angle.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private func distanceToKaaba(from location: SavedLocation) -> String {
        let here = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let kaaba = CLLocation(latitude: 21.4225, longitude: 39.8262)
        let distance = Measurement(value: here.distance(from: kaaba), unit: UnitLength.meters)
        return distance.formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

private struct CompassDial: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.clear)
                .glassEffect(.regular, in: .circle)
            ForEach(0..<72, id: \.self) { tick in
                let major = tick % 18 == 0
                Capsule()
                    .fill(major ? Color.white : Color.white.opacity(0.3))
                    .frame(width: major ? 3 : 1.5, height: major ? 14 : 7)
                    .offset(y: -140)
                    .rotationEffect(.degrees(Double(tick) * 5))
            }
            ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { index, letter in
                Text(letter)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(letter == "N" ? Color.red : Color.white)
                    .offset(y: -112)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
    }
}

/// A small drawing of the Kaaba: a black cube with its gold band (the Kiswah).
private struct KaabaIcon: View {
    let highlighted: Bool

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black)
                .overlay {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.25), lineWidth: 1)
                }
            Rectangle()
                .fill(Palette.gold)
                .frame(height: 4)
                .padding(.top, 9)
        }
        .frame(width: 34, height: 36)
        .shadow(color: highlighted ? Palette.gold : .clear, radius: 12)
        .accessibilityLabel("Kaaba")
    }
}
