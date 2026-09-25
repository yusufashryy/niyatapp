import SwiftUI

@main
struct SalahApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.salahGreen)
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        Group {
            if hasOnboarded, model.location != nil {
                MainTabView()
            } else {
                OnboardingView { hasOnboarded = true }
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: model.refresh()
            case .background: BackgroundRefresh.schedule()
            default: break
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "clock.fill") }
            SurahListView()
                .tabItem { Label("Quran", systemImage: "book.fill") }
            QiblaView()
                .tabItem { Label("Qibla", systemImage: "location.north.circle.fill") }
            FocusView()
                .tabItem { Label("Focus", systemImage: "lock.shield.fill") }
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
        }
    }
}
