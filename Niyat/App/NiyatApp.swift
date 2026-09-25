import SwiftUI
import UserNotifications

@main
struct NiyatApp: App {
    @State private var model: AppModel

    init() {
        #if DEBUG
        DemoMode.prepareIfRequested()
        #endif
        _model = State(initialValue: AppModel())
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
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
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            } else {
                OnboardingView {
                    withAnimation(.smooth(duration: 0.6)) { hasOnboarded = true }
                }
                .transition(.opacity)
            }
        }
        // Reading Palette here means the whole app re-tints when the theme changes.
        .tint(Palette.accent)
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
    case today, quran, qibla, journey, more
}

struct MainTabView: View {
    @State private var selection: AppTab = .today

    var body: some View {
        // On iOS 26+ the tab bar is Liquid Glass and shrinks while scrolling.
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.horizon.fill", value: .today) { TodayView() }
            Tab("Quran", systemImage: "book.closed.fill", value: .quran) { SurahListView() }
            Tab("Qibla", systemImage: "location.north.circle.fill", value: .qibla) { QiblaView() }
            Tab("Journey", systemImage: "calendar", value: .journey) { JourneyView() }
            Tab("More", systemImage: "circle.grid.2x2.fill", value: .more) { MoreView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .haptic(.selection, trigger: selection)
    }
}
