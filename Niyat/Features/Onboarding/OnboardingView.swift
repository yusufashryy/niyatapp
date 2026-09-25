import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    let onFinish: () -> Void

    @State private var step = 0
    @State private var spin = false

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 24) {
                Spacer()
                Group {
                    switch step {
                    case 0: welcome
                    case 1: locationStep
                    default: notificationStep
                    }
                }
                .transition(.blurReplace)
                Spacer()
            }
            .padding(24)
            .animation(.smooth, value: step)
        }
        .foregroundStyle(.white)
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Text("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
                .font(.quran(size: 30))
                .foregroundStyle(Palette.highlight)
            ZStack {
                Rosette(color: Palette.highlight.opacity(0.35), lineWidth: 1.2)
                    .frame(width: 230, height: 230)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 90).repeatForever(autoreverses: false), value: spin)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Palette.highlight)
                    .frame(width: 120, height: 120)
                    .glassEffect(.regular.tint(Palette.glow.opacity(0.5)), in: .circle)
            }
            .onAppear { spin = true }
            VStack(spacing: 4) {
                Text("نيّة")
                    .font(.calligraphy(size: 54))
                    .foregroundStyle(Palette.highlight)
                Text("Niyat").font(.display(44, weight: .heavy))
                Text("intention")
                    .font(.headline)
                    .foregroundStyle(Palette.accent)
            }
            Text("Prayer times, Quran, Qibla and more. Free forever. No ads, no accounts, no tracking.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
            primaryButton("Get started") { step = 1 }
                .haptic(.impact(weight: .medium), trigger: step)
        }
    }

    private var locationStep: some View {
        VStack(spacing: 20) {
            stepIcon("location.fill")
            Text("Where are you?").font(.display(32))
            Text("Prayer times depend on where you are. Your location never leaves your phone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
            LocationPickerView { location in
                model.setLocation(location)
                step = 2
            }
        }
    }

    private var notificationStep: some View {
        VStack(spacing: 20) {
            stepIcon("bell.badge.fill")
            Text("Never miss a prayer").font(.display(32))
            if let location = model.location {
                Text("Times for \(location.name) use the \(model.prayerSettings.method.title) method. You can change this any time in Settings.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))
            }
            primaryButton("Turn on adhan notifications") {
                Task {
                    await NotificationScheduler.requestAuthorization()
                    model.refresh()
                    onFinish()
                }
            }
            Button("Not now", action: onFinish)
                .buttonStyle(.glass)
                .controlSize(.large)
        }
    }

    private func stepIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(Palette.highlight)
            .frame(width: 96, height: 96)
            .glassEffect(.regular.tint(Palette.glow.opacity(0.5)), in: .circle)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(Palette.highlight)
        .controlSize(.extraLarge)
    }
}
