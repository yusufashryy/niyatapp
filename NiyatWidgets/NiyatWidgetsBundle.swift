import SwiftUI
import WidgetKit

@main
struct NiyatWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextPrayerWidget()
        PrayerTimesWidget()
        PrayerDialWidget()
        CountdownRingWidget()
        PrayerLogWidget()
        StreakWidget()
        QuranGoalWidget()
        DailyVerseWidget()
        HijriDateWidget()
        TasbihWidget()
    }
}
