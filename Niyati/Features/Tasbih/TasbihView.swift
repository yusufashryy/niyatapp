import SwiftUI
import WidgetKit

struct TasbihView: View {
    @State private var count = TasbihCounter.count
    @State private var target = TasbihCounter.target
    @State private var dhikr = TasbihCounter.dhikr
    @Environment(\.scenePhase) private var scenePhase

    private let targets = [0, 33, 99, 100, 1000]

    var body: some View {
        VStack(spacing: 24) {
            Picker("Dhikr", selection: $dhikr) {
                ForEach(Dhikr.allCases) { dhikr in
                    Text(dhikr.transliteration).tag(dhikr)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: dhikr) { _, new in
                TasbihCounter.dhikr = new
                reset()
            }

            VStack(spacing: 6) {
                Text(dhikr.arabic).font(.quran(size: 34))
                Text(dhikr.meaning).foregroundStyle(.secondary)
            }

            Button(action: increment) {
                ZStack {
                    Circle().fill(.niyatiBackground)
                    if target > 0 {
                        Circle()
                            .trim(from: 0, to: CGFloat(count % target == 0 && count > 0 ? target : count % target) / CGFloat(target))
                            .stroke(Color.niyatiGold, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(8)
                    }
                    VStack {
                        Text("\(count)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        if target > 0 {
                            Text("of \(target)").foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 260, height: 260)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: count)
            .sensoryFeedback(.success, trigger: count) { _, new in target > 0 && new > 0 && new % target == 0 }
            .accessibilityLabel("Count. \(count)")

            HStack {
                Menu {
                    Picker("Target", selection: $target) {
                        ForEach(targets, id: \.self) { value in
                            Text(value == 0 ? "No target" : "\(value)").tag(value)
                        }
                    }
                } label: {
                    Label(target == 0 ? "No target" : "Target \(target)", systemImage: "target")
                }
                .onChange(of: target) { _, new in TasbihCounter.target = new }

                Spacer()

                Button("Reset", systemImage: "arrow.counterclockwise", action: reset)
            }
            .padding(.horizontal)

            Text("Lifetime: \(TasbihCounter.lifetimeCount)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Tasbih")
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { count = TasbihCounter.count }
        }
        .onAppear { count = TasbihCounter.count }
        .onDisappear { WidgetCenter.shared.reloadTimelines(ofKind: "TasbihWidget") }
    }

    private func increment() {
        withAnimation { count = TasbihCounter.increment() }
    }

    private func reset() {
        TasbihCounter.reset()
        withAnimation { count = 0 }
    }
}
