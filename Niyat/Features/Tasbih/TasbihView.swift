import SwiftUI
import WidgetKit

struct TasbihView: View {
    @State private var count = TasbihCounter.count
    @State private var target = TasbihCounter.target
    @State private var dhikr = TasbihCounter.dhikr
    @State private var lifetime = TasbihCounter.lifetimeCount
    @Environment(\.scenePhase) private var scenePhase

    private let targets = [0, 33, 99, 100, 1000]

    private var progress: CGFloat {
        guard target > 0, count > 0 else { return 0 }
        let inRound = count % target
        return CGFloat(inRound == 0 ? target : inRound) / CGFloat(target)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                dhikrPicker

                VStack(spacing: 6) {
                    Text(dhikr.arabic)
                        .font(.quran(size: 38))
                        .foregroundStyle(Palette.gold)
                    Text(dhikr.meaning)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                counterButton

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Menu {
                            Picker("Target", selection: $target) {
                                ForEach(targets, id: \.self) { value in
                                    Text(value == 0 ? "No target" : "\(value)").tag(value)
                                }
                            }
                        } label: {
                            Label(target == 0 ? "No target" : "Target \(target)", systemImage: "target")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.glass)

                        Button("Reset", systemImage: "arrow.counterclockwise", action: reset)
                            .buttonStyle(.glass)
                    }
                }
                .controlSize(.large)

                Text("Lifetime: \(lifetime.formatted())")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .niyatBackground()
        .navigationTitle("Tasbih")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: target) { _, new in TasbihCounter.target = new }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { syncFromStore() }
        }
        .onAppear(perform: syncFromStore)
        .onDisappear { WidgetCenter.shared.reloadTimelines(ofKind: "TasbihWidget") }
    }

    private var dhikrPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Dhikr.allCases) { option in
                        Button {
                            dhikr = option
                            TasbihCounter.dhikr = option
                            reset()
                        } label: {
                            Text(option.transliteration)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(option == dhikr ? Color.black : Color.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .glassEffect(option == dhikr ? .regular.tint(Palette.emerald).interactive() : .regular.interactive(),
                                             in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .scrollClipDisabled()
    }

    private var counterButton: some View {
        Button(action: increment) {
            ZStack {
                if target > 0 {
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 10)
                        .padding(14)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(LinearGradient(colors: [Palette.emerald, Palette.gold], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(14)
                        .shadow(color: Palette.emerald.opacity(0.6), radius: 8)
                }
                VStack(spacing: 2) {
                    Text("\(count)")
                        .font(.display(84, weight: .heavy))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(count)))
                    Text(target > 0 ? "of \(target)" : "Tap to count")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            }
            .frame(width: 280, height: 280)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Palette.deepEmerald.opacity(0.6)).interactive(), in: .circle)
        .sensoryFeedback(.impact(weight: .light), trigger: count)
        .sensoryFeedback(.success, trigger: count) { _, new in target > 0 && new > 0 && new % target == 0 }
        .accessibilityLabel("Count. \(count)")
    }

    private func syncFromStore() {
        count = TasbihCounter.count
        lifetime = TasbihCounter.lifetimeCount
    }

    private func increment() {
        withAnimation(.snappy) { count = TasbihCounter.increment() }
        lifetime = TasbihCounter.lifetimeCount
    }

    private func reset() {
        TasbihCounter.reset()
        withAnimation(.snappy) { count = 0 }
    }
}
