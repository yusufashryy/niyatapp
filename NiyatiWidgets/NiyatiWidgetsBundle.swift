import SwiftUI
import WidgetKit

@main
struct NiyatiWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextPrayerWidget()
        PrayerTimesWidget()
        DailyVerseWidget()
        TasbihWidget()
    }
}
