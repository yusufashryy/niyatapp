import SwiftUI

@main
struct NiyatApp: App {
    @State private var model: AppModel

    init() {
        #if DEBUG
        DemoMode.prepareIfRequested()
        #endif
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.emerald)
                .preferredColorScheme(.dark)
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

enum AppTab: Hashable {
    case today, quran, qibla, focus, more
}

struct MainTabView: View {
    @State private var selection: AppTab = .today

    var body: some View {
        // On iOS 26+ the tab bar is Liquid Glass and shrinks while scrolling.
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.horizon.fill", value: .today) { TodayView() }
            Tab("Quran", systemImage: "book.closed.fill", value: .quran) { SurahListView() }
            Tab("Qibla", systemImage: "location.north.circle.fill", value: .qibla) { QiblaView() }
            Tab("Focus", systemImage: "lock.shield.fill", value: .focus) { FocusView() }
            Tab("More", systemImage: "circle.grid.2x2.fill", value: .more) { MoreView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
