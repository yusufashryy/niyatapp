import CoreLocation
import SwiftUI
import WatchKit

// The watch's extra pages: Qibla, tasbih on the Digital Crown, and the
// Qur'an goal. Each works from what's on the watch, without the iPhone.

// MARK: - Qibla

/// The compass heading, from the watch's own compass (Series 5 and later).
@MainActor
@Observable
final class WatchCompass: NSObject, CLLocationManagerDelegate {
    private(set) var heading: Double?
    private let manager = CLLocationManager()

    var isAvailable: Bool { CLLocationManager.headingAvailable() }

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 2
    }

    func start() { if isAvailable { manager.startUpdatingHeading() } }
    func stop() { manager.stopUpdatingHeading() }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // True north when the watch knows where it is; magnetic north otherwise
        // (a few degrees off in most places).
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = value }
    }
}

/// Which way to face, from the location the iPhone sent.
struct WatchQiblaPage: View {
    let location: SavedLocation
    @State private var compass = WatchCompass()

    private var bearing: Double { QiblaMath.bearing(latitude: location.latitude, longitude: location.longitude) }

    var body: some View {
        let heading = compass.heading
        let facing = heading.map { QiblaMath.isFacing(bearing: bearing, heading: $0) } ?? false
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 2)
                // North, turning with the watch.
                Text("N")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .offset(y: -52)
                    .rotationEffect(.degrees(-(heading ?? 0)))
                // The Qibla: where to face, relative to the watch.
                VStack(spacing: 2) {
                    EightPointStar()
                        .fill(facing ? Palette.highlight : Palette.accent)
                        .frame(width: 22, height: 22)
                    Capsule()
                        .fill(facing ? Palette.highlight : Palette.accent.opacity(0.7))
                        .frame(width: 3, height: 34)
                }
                .offset(y: -28)
                .rotationEffect(.degrees(QiblaMath.needle(bearing: bearing, heading: heading ?? 0)))
            }
            .frame(width: 124, height: 124)
            .animation(.smooth(duration: 0.3), value: heading)
            Text(caption(heading: heading, facing: facing))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(facing ? Palette.highlight : .primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Qibla")
        .containerBackground(for: .tabView) { WatchBackground() }
        .onAppear { compass.start() }
        .onDisappear { compass.stop() }
        .onChange(of: facing) { _, now in if now { WKInterfaceDevice.current().play(.success) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption(heading: heading, facing: facing))
    }

    private func caption(heading: Double?, facing: Bool) -> String {
        guard heading != nil else { return "\(Int(bearing.rounded()))° from north" }
        return facing ? "Facing the Qibla" : "Turn until the star is at the top"
    }
}

// MARK: - Tasbih

/// The tasbih page: the count, a tap to add one, and the crown counter.
/// The crown can't count here: on these pages it scrolls between them.
struct WatchTasbihPage: View {
    @State private var count = TasbihCounter.count
    @State private var dhikr = TasbihCounter.dhikr
    @State private var usesCrown = false

    var body: some View {
        VStack(spacing: 6) {
            WatchTasbihDial(count: count, dhikr: dhikr, onDhikr: nextDhikr) { add(1) }
            Button {
                usesCrown = true
            } label: {
                Label("Use the Crown", systemImage: "digitalcrown.arrow.clockwise")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Palette.control)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Tasbih")
        .containerBackground(for: .tabView) { WatchBackground() }
        .fullScreenCover(isPresented: $usesCrown, onDismiss: { count = TasbihCounter.count }) {
            WatchCrownTasbih(dhikr: dhikr)
        }
    }

    private func add(_ steps: Int) {
        count = WatchTasbihDial.add(steps)
    }

    private func nextDhikr() {
        let all = Dhikr.allCases
        let next = all[(all.firstIndex(of: dhikr).map { $0 + 1 } ?? 0) % all.count]
        TasbihCounter.dhikr = next
        TasbihCounter.reset()
        dhikr = next
        count = 0
    }
}

/// Full screen, so the Digital Crown counts: one click, one count.
struct WatchCrownTasbih: View {
    let dhikr: Dhikr
    @State private var count = TasbihCounter.count
    @State private var crown = 0.0

    var body: some View {
        WatchTasbihDial(count: count, dhikr: dhikr, onDhikr: nil) { count = WatchTasbihDial.add(1) }
            .focusable()
            .digitalCrownRotation($crown, from: 0, through: 100_000, by: 1, sensitivity: .low,
                                  isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: crown) { old, new in count = WatchTasbihDial.add(CrownTasbih.counts(from: old, to: new)) }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset") {
                        TasbihCounter.reset()
                        count = 0
                    }
                }
            }
    }
}

/// The count in a ring that fills towards the target (33 by default).
struct WatchTasbihDial: View {
    let count: Int
    let dhikr: Dhikr
    /// Tapping the dhikr's name changes it (nil: it can't be changed here).
    let onDhikr: (() -> Void)?
    let onCount: () -> Void
    private let target = TasbihCounter.target

    var body: some View {
        VStack(spacing: 4) {
            Button { onDhikr?() } label: {
                Text(dhikr.transliteration)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.highlight)
            .disabled(onDhikr == nil)
            .accessibilityHint(onDhikr == nil ? "" : "Changes the dhikr")

            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 6)
                // Only drawn once there's something to show (no round-ended dot at 0).
                if target > 0, count % target > 0 {
                    Circle()
                        .trim(from: 0, to: CGFloat(count % target) / CGFloat(target))
                        .stroke(Palette.highlight, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text("\(count)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .fitText(0.4)
            }
            .frame(width: 104, height: 104)
            .contentShape(.circle)
            .onTapGesture(perform: onCount)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(count) \(dhikr.transliteration)")
            .accessibilityAction(named: "Count", onCount)
        }
    }

    /// Adds counts, with a tap on the wrist at each target. Returns the new count.
    static func add(_ steps: Int) -> Int {
        guard steps > 0 else { return TasbihCounter.count }
        for _ in 0..<steps { TasbihCounter.increment() }
        let count = TasbihCounter.count
        let target = TasbihCounter.target
        if target > 0, count % target == 0 { WKInterfaceDevice.current().play(.success) }
        return count
    }
}

// MARK: - Qur'an goal

/// Today's ayat against the daily goal, from the iPhone's reading.
struct WatchQuranPage: View {
    let day: QuranDay
    let goal: Int?
    let streak: Int

    var body: some View {
        VStack(spacing: 6) {
            if let goal {
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 8)
                    if day.count > 0 {
                        Circle()
                            .trim(from: 0, to: min(CGFloat(day.count) / CGFloat(max(goal, 1)), 1))
                            .stroke(day.isComplete ? Palette.highlight : Palette.accent,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 0) {
                        Text("\(day.count)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .fitText(0.4)
                        Text("of \(goal) ayat")
                            .font(.caption2)
                            .fitText()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 110, height: 110)
                Label(streak == 1 ? "1-day streak" : "\(streak)-day streak", systemImage: "flame.fill")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(streak > 0 ? Palette.highlight : .secondary)
            } else {
                Image(systemName: "book.closed")
                    .font(.title2)
                    .foregroundStyle(Palette.highlight)
                Text("Set a daily Qur'an goal in Niyat on your iPhone.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Qur'an")
        .containerBackground(for: .tabView) { WatchBackground() }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Background

/// The iPhone app's background in the user's theme, held still: the glow,
/// arabesque pattern and calligraphy, without the drifting animation that
/// would keep the watch redrawing.
struct WatchBackground: View {
    var body: some View {
        AmbientBackground(isStill: true)
    }
}
