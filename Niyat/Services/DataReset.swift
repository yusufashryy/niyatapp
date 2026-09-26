import Foundation
import UserNotifications
import WidgetKit
#if SCREEN_TIME
import DeviceActivity
#endif

/// "Erase all data": puts Niyat back to how it was when first installed.
///
/// Clears every setting, prayer log, Qur'an progress, bookmark, tasbih count
/// and theme stored on this device (both the app's own storage and the App
/// Group shared with the widgets), removes pending notifications and stops
/// Prayer Lock. The bundled Qur'an text is never touched.
@MainActor
enum DataReset {
    static func eraseEverything(model: AppModel) {
        RecitationPlayer.shared.stop()

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        #if SCREEN_TIME
        DeviceActivityCenter().stopMonitoring()
        FocusScheduler.clearShield()
        #endif

        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        AppGroup.defaults.removePersistentDomain(forName: AppGroup.identifier)
        // Belt and braces: removePersistentDomain can miss keys cached in memory.
        for key in AppGroup.defaults.dictionaryRepresentation().keys {
            AppGroup.defaults.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
        AppGroup.defaults.synchronize()

        // Reload what's held in memory so nothing old lingers on screen.
        QuranStore.shared.reloadUserData()
        QuranGoalModel.shared.refresh()
        ThemeManager.shared.reload()
        model.reloadFromStorage()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
