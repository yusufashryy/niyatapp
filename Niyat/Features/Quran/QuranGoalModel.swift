import Foundation
import Observation
import WidgetKit

/// Today's Qur'an goal and streak, kept in sync with `QuranProgress` (App Group
/// storage) so the reader, list, Stats, widgets and Groups all agree.
@MainActor
@Observable
final class QuranGoalModel {
    static let shared = QuranGoalModel()

    private(set) var goal: Int?
    private(set) var today = QuranDay(goal: 0)
    private(set) var streak = 0
    /// Set when the goal is reached, to show the celebration once.
    var celebration: Int?

    private init() { refresh() }

    var progress: Double {
        guard let goal, goal > 0 else { return 0 }
        return min(Double(today.count) / Double(goal), 1)
    }

    func refresh(now: Date = .now) {
        goal = QuranProgress.dailyGoal
        today = QuranProgress.day(now)
        streak = QuranProgress.currentStreak(asOf: now)
    }

    func setGoal(_ newGoal: Int) {
        QuranProgress.setGoal(newGoal)
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
        GroupSync.shared.publishSoon()
    }

    /// Records a verse as read (once per day). Shows the celebration the moment
    /// the goal is reached.
    func recordRead(_ verse: Verse) {
        let reference = verse.hafsReference
        let justCompleted = QuranProgress.recordRead(surah: reference.surah, verse: reference.verse,
                                                     letters: verse.letterCount)
        refresh()
        if justCompleted {
            celebration = streak
            WidgetCenter.shared.reloadAllTimelines()
        }
        GroupSync.shared.publishSoon()
    }
}
