import StoreKit
import SwiftUI
import UIKit
import UserNotifications

@main
struct NiyatApp: App {
    @State private var model: AppModel
    #if GROUPS
    @UIApplicationDelegateAdaptor(GroupsAppDelegate.self) private var appDelegate
    #endif

    init() {
        #if DEBUG
        DemoMode.prepareIfRequested()
        #endif
        _model = State(initialValue: AppModel())
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        // Talks to iOS's notification service: don't hold up launch for it.
        DispatchQueue.global(qos: .utility).async { NotificationScheduler.registerCategories() }
        TipJar.shared.startListening()
        #if WATCH
        WatchSync.shared.activate()
        #endif
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
        // The athan playing in full, with Stop, over whatever screen is open.
        .overlay(alignment: .top) { AthanNowPlaying() }
        .animation(.smooth, value: AthanPlayer.shared.playing)
        // Reading Palette here means the whole app re-tints when the theme changes.
        .tint(Palette.accent)
        .toggleStyle(NiyatToggleStyle())
        // Widget taps, e.g. the Qur'an Goal widget opens niyat://quran.
        .onOpenURL { url in
            if url.host() == "quran" { DeepLink.shared.pending = .quranContinueReading }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                model.refresh()
                if hasOnboarded { Task { await model.followCurrentLocation() } }
            case .background: BackgroundRefresh.schedule()
            default: break
            }
        }
        // Memory is low: let go of Qur'an data that's only kept to be quick.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            QuranMemory.releaseCaches()
        }
        // Landing after a flight while Niyat is open: re-time alerts and check the location.
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSSystemTimeZoneDidChange) {
                model.refresh()
                if hasOnboarded { await model.followCurrentLocation() }
            }
        }
    }
}

enum AppTab: Hashable {
    case today, quran, qibla, stats, more
}

struct MainTabView: View {
    @State private var selection: AppTab = .today
    @State private var deepLink = DeepLink.shared
    @AppStorage(TutorialView.seenKey) private var tutorialSeen = false
    @State private var showTutorial = false
    @State private var prompter = ReviewPrompter.shared
    @State private var showFeedback = false
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        // On iOS 26+ the tab bar is Liquid Glass and shrinks while scrolling.
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.horizon.fill", value: .today) { TodayView() }
            Tab("Quran", systemImage: "book.closed.fill", value: .quran) { SurahListView() }
            Tab("Qibla", systemImage: "location.north.circle.fill", value: .qibla) { QiblaView() }
            Tab("Stats", systemImage: "chart.bar.xaxis", value: .stats) { StatsView() }
            Tab("More", systemImage: "circle.grid.2x2.fill", value: .more) { MoreView() }
        }
        // iPad: tabs at the top that can open into a sidebar.
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .haptic(.selection, trigger: selection)
        .onChange(of: deepLink.pending, initial: true) { _, destination in
            if destination?.isQuran == true { selection = .quran }
        }
        // First launch after onboarding: a quick walkthrough.
        .onAppear {
            if !tutorialSeen { showTutorial = true } else { prompter.appOpened() }
        }
        .fullScreenCover(isPresented: $showTutorial) { TutorialView() }
        #if SCREEN_TIME
        // Opening Niyat during a Prayer Lock asks "Have you prayed?" and can unlock.
        .modifier(PrayerLockPromptModifier())
        #endif
        // Apple's own rating prompt, a moment after a happy event (see ReviewPrompter).
        .onChange(of: prompter.askForReview) { _, ask in
            guard ask else { return }
            prompter.askForReview = false
            Task {
                try? await Task.sleep(for: .seconds(3))
                requestReview()
            }
        }
        .alert("How's Niyat working for you?", isPresented: $prompter.offerFeedback) {
            Button("Send feedback") { showFeedback = true }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Niyat is built by one person. Ideas, bugs, or anything that looks inaccurate: we read every message.")
        }
        .sheet(isPresented: $showFeedback) {
            NavigationStack {
                FeedbackView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showFeedback = false } } }
            }
        }
    }
}
