import BackgroundTasks
import Foundation
import WidgetKit

/// Lets iOS wake the app occasionally to top up notifications and widgets
/// even if the user hasn't opened it in a while.
enum BackgroundRefresh {
    static let identifier = (Bundle.main.bundleIdentifier ?? "Salah") + ".refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func run() async {
        schedule()
        await NotificationScheduler.reschedule(location: SettingsStore.location,
                                               prayerSettings: SettingsStore.prayerSettings,
                                               notificationSettings: SettingsStore.notificationSettings)
        WidgetCenter.shared.reloadAllTimelines()
        #if SCREEN_TIME
        FocusScheduler.reschedule()
        #endif
    }
}
