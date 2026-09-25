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

        return VStack(spacing: 28) {
            Spacer()

            ZStack {
                // Compass dial turns so N always points north.
                CompassDial()
                    .rotationEffect(.degrees(-heading))

                // Arrow to the Kaaba.
                VStack(spacing: 0) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(isAligned ? Color.salahGold : Color.salahGreen)
                    Rectangle()
                        .fill(isAligned ? Color.salahGold : Color.salahGreen)
                        .frame(width: 4, height: 80)
                    Spacer().frame(height: 124)
                }
                .rotationEffect(.degrees(relative))

                Image(systemName: "building.columns.fill")
                    .font(.title)
                    .foregroundStyle(isAligned ? Color.salahGold : .secondary)
            }
            .frame(width: 300, height: 300)
            .animation(.easeOut(duration: 0.25), value: heading)
            .sensoryFeedback(.success, trigger: isAligned) { _, aligned in aligned }

            VStack(spacing: 8) {
                if compass.heading == nil {
                    Text("Qibla is \(Int(qibla.rounded()))° from north")
                        .font(.title2.bold())
                    Text("No compass on this device. Use a physical compass, or face \(Int(qibla.rounded()))° clockwise from north.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else if isAligned {
                    Text("You're facing the Qibla").font(.title2.bold()).foregroundStyle(Color.salahGreen)
                } else {
                    Text("Turn \(relative < 180 ? "right" : "left") \(Int((relative < 180 ? relative : 360 - relative).rounded()))°")
                        .font(.title2.bold())
                }
                Text("\(Int(qibla.rounded()))° · \(distanceToKaaba(from: location)) to Makkah")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if compass.needsCalibration {
                    Label("Move your phone in a figure-8 to calibrate the compass. Keep it away from metal and magnets.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
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
                .fill(.background.secondary)
            Circle()
                .stroke(Color.salahGreen.opacity(0.3), lineWidth: 2)
            ForEach(0..<72, id: \.self) { tick in
                Rectangle()
                    .fill(tick % 18 == 0 ? Color.primary : Color.secondary.opacity(0.5))
                    .frame(width: tick % 18 == 0 ? 3 : 1, height: tick % 18 == 0 ? 14 : 7)
                    .offset(y: -140)
                    .rotationEffect(.degrees(Double(tick) * 5))
            }
            ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { index, letter in
                Text(letter)
                    .font(.headline)
                    .foregroundStyle(letter == "N" ? Color.red : Color.primary)
                    .offset(y: -112)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
    }
}
