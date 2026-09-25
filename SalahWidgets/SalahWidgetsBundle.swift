import SwiftUI
import WidgetKit

@main
struct SalahWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextPrayerWidget()
        PrayerTimesWidget()
        DailyVerseWidget()
        TasbihWidget()
    }
}
