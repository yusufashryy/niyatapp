import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    let onFinish: () -> Void

    @State private var step = 0

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
                .foregroundStyle(Palette.gold)
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 56))
                .foregroundStyle(Palette.gold)
                .frame(width: 120, height: 120)
                .glassEffect(.regular.tint(Palette.deepEmerald.opacity(0.5)), in: .circle)
            VStack(spacing: 8) {
                Text("Niyat").font(.display(48, weight: .heavy))
                Text("نيّة · intention")
                    .font(.headline)
                    .foregroundStyle(Palette.emerald)
            }
            Text("Prayer times, Quran, Qibla and more. Free forever. No ads, no accounts, no tracking.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
            primaryButton("Get started") { step = 1 }
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
            .foregroundStyle(Palette.gold)
            .frame(width: 96, height: 96)
            .glassEffect(.regular.tint(Palette.deepEmerald.opacity(0.5)), in: .circle)
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
        .tint(Palette.gold)
        .controlSize(.extraLarge)
    }
}
