import SwiftUI
import WidgetKit

@main
struct NiyatWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextPrayerWidget()
        PrayerTimesWidget()
        DailyVerseWidget()
        TasbihWidget()
    }
}
