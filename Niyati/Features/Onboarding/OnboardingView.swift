import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    let onFinish: () -> Void

    @State private var step = 0

    var body: some View {
        ZStack {
            Rectangle().fill(.niyatiBackground).ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                switch step {
                case 0: welcome
                case 1: locationStep
                default: notificationStep
                }
                Spacer()
            }
            .padding(24)
            .foregroundStyle(.white)
            .animation(.easeInOut, value: step)
        }
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Text("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
                .font(.quran(size: 30))
                .foregroundStyle(Color.niyatiGold)
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.niyatiGold)
            Text("Niyati").font(.largeTitle.bold())
            Text("Prayer times, Quran, Qibla and more. Free forever, no ads, no accounts, no tracking.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
            primaryButton("Get started") { step = 1 }
        }
    }

    private var locationStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.niyatiGold)
            Text("Where are you?").font(.title.bold())
            Text("Prayer times depend on where you are. Your location stays on your phone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
            LocationPickerView(style: .onboarding) { location in
                model.setLocation(location)
                step = 2
            }
        }
    }

    private var notificationStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.niyatiGold)
            Text("Never miss a prayer").font(.title.bold())
            if let location = model.location {
                Text("Times for \(location.name) use the \(model.prayerSettings.method.title) method. You can change this any time in More › Settings.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
            }
            primaryButton("Turn on adhan notifications") {
                Task {
                    await NotificationScheduler.requestAuthorization()
                    model.refresh()
                    onFinish()
                }
            }
            Button("Not now", action: onFinish)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.niyatiGold, in: .rect(cornerRadius: 14))
                .foregroundStyle(Color.niyatiDeepGreen)
        }
    }
}
